import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import '../utils/path_utils.dart';
import 'database_service.dart';
import 'logger_service.dart';

/// 语音消息服务：从 media_[0-99].db 中读取 voice_data，调用内置解码器转为 mp3，缓存到本地。
class VoiceMessageService {
  VoiceMessageService(this.databaseService);

  final DatabaseService databaseService;
  final Map<String, Future<File>> _ongoingDecodes = {};
  final Map<String, Future<int?>> _ongoingDuration = {};
  final StreamController<String> _decodeFinishedController =
      StreamController<String>.broadcast();

  static const _sampleRate = 24000;
  static const _assetsSilk = 'assets/silk_v3_decoder.exe';
  static const _assetsFfmpeg = 'assets/ffmpeg.exe';

  Stream<String> get decodeFinishedStream => _decodeFinishedController.stream;

  /// 检查本地是否已有解码后的 mp3
  Future<File?> findExistingVoiceFile(
    Message message,
    String sessionUsername,
  ) async {
    final outputFile = await _buildOutputFile(message, sessionUsername);
    if (await outputFile.exists()) {
      await logger.debug(
        'VoiceMessageService',
        'hit cached mp3: ${outputFile.path}',
      );
      return outputFile;
    }
    return null;
  }

  /// 确保语音已解码，如未解码则执行解码并返回 mp3 文件。
  Future<File> ensureVoiceDecoded(
    Message message,
    String sessionUsername,
  ) async {
    final outputFile = await _buildOutputFile(message, sessionUsername);
    if (await outputFile.exists()) {
      await logger.debug(
        'VoiceMessageService',
        'ensureVoiceDecoded: already exists ${outputFile.path}',
      );
      _notifyDecodeFinished(outputFile);
      return outputFile;
    }

    final key = outputFile.path;
    if (_ongoingDecodes.containsKey(key)) {
      await logger.debug(
        'VoiceMessageService',
        'ensureVoiceDecoded: join ongoing $key',
      );
      return _ongoingDecodes[key]!;
    }

    final future = _decodeAndSave(message, sessionUsername, outputFile)
        .then((file) {
      _notifyDecodeFinished(file);
      return file;
    }).whenComplete(() => _ongoingDecodes.remove(key));
    _ongoingDecodes[key] = future;
    return future;
  }

  /// 获取解码后文件的路径（不触发解码）
  Future<File> getOutputFile(
    Message message,
    String sessionUsername,
  ) {
    return _buildOutputFile(message, sessionUsername);
  }

  /// 获取语音时长（秒），仅依赖数据库中的 voice_data，不保存文件。
  Future<int?> fetchDurationSeconds(Message message) async {
    final key = 'dur_${message.createTime}_${message.localId}_${message.senderUsername ?? ""}';
    if (_ongoingDuration.containsKey(key)) {
      return _ongoingDuration[key]!;
    }
    final future = _calcDuration(message).whenComplete(() {
      _ongoingDuration.remove(key);
    });
    _ongoingDuration[key] = future;
    return future;
  }

  Future<File> _decodeAndSave(
    Message message,
    String sessionUsername,
    File outputFile,
  ) async {
    final senderWxid = message.senderUsername ?? message.myWxid;
    if (senderWxid == null || senderWxid.isEmpty) {
      throw Exception('未找到语音发送者 wxid，无法定位语音数据');
    }

    final voiceBytes = await databaseService.fetchVoiceData(
      senderWxid: senderWxid,
      createTime: message.createTime,
    );
    if (voiceBytes == null || voiceBytes.isEmpty) {
      throw Exception('未在媒体数据库中找到语音原始数据');
    }

    await logger.info(
      'VoiceMessageService',
      'start decode: sender=$senderWxid create=${message.createTime} '
      'localId=${message.localId} bytes=${voiceBytes.length}',
    );

    final binaries = await _ensureBinariesReady();

    final tempDir = await getTemporaryDirectory();
    final silkPath = PathUtils.join(
      tempDir.path,
      'voice_${message.createTime}_${senderWxid}.silk',
    );
    final pcmPath = PathUtils.replaceExtension(silkPath, '.pcm');
    final tempMp3Path = PathUtils.replaceExtension(silkPath, '.mp3');

    await File(silkPath).writeAsBytes(voiceBytes, flush: true);

    // Silk -> PCM
    final decodeResult = await Process.run(
      binaries.silkDecoder,
      [
        silkPath,
        pcmPath,
        '-Fs_API',
        '$_sampleRate',
      ],
    );
    if (decodeResult.exitCode != 0 || !File(pcmPath).existsSync()) {
      final stderrMsg = decodeResult.stderr?.toString() ?? '';
      throw Exception('Silk 解码失败: $stderrMsg');
    }

    // PCM -> MP3
    final ffmpegResult = await Process.run(
      binaries.ffmpeg,
      [
        '-y',
        '-f',
        's16le',
        '-ar',
        '$_sampleRate',
        '-ac',
        '1',
        '-i',
        pcmPath,
        tempMp3Path,
      ],
    );
    if (ffmpegResult.exitCode != 0 || !File(tempMp3Path).existsSync()) {
      final stderrMsg = ffmpegResult.stderr?.toString() ?? '';
      throw Exception('FFmpeg 转换失败: $stderrMsg');
    }

    await logger.info(
      'VoiceMessageService',
      'decode success -> ${outputFile.path}',
    );

    await PathUtils.ensureParentExists(outputFile.path);
    await File(tempMp3Path).copy(outputFile.path);

    // 清理临时文件
    try {
      File(silkPath).deleteSync();
      File(pcmPath).deleteSync();
      File(tempMp3Path).deleteSync();
    } catch (_) {}

    await logger.info(
      'VoiceMessageService',
      '语音解码完成: ${outputFile.path}',
    );
    _notifyDecodeFinished(outputFile);

    return outputFile;
  }

  void _notifyDecodeFinished(File outputFile) {
    try {
      if (!_decodeFinishedController.isClosed) {
        _decodeFinishedController.add(outputFile.path);
      }
    } catch (_) {}
  }

  Future<_BinaryPaths> _ensureBinariesReady() async {
    final docs = await getApplicationDocumentsDirectory();
    final binDir = Directory(PathUtils.join(docs.path, 'EchoTrace', 'bin'));
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }

    final silkPath = await _ensureBinary(
      assetPath: _assetsSilk,
      fileName: 'silk_v3_decoder.exe',
      binDir: binDir,
    );
    final ffmpegPath = await _ensureBinary(
      assetPath: _assetsFfmpeg,
      fileName: 'ffmpeg.exe',
      binDir: binDir,
    );

    return _BinaryPaths(silkDecoder: silkPath, ffmpeg: ffmpegPath);
  }

  Future<String> _ensureBinary({
    required String assetPath,
    required String fileName,
    required Directory binDir,
  }) async {
    final dest = File(PathUtils.join(binDir.path, fileName));
    if (await dest.exists()) {
      return dest.path;
    }

    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  Future<File> _buildOutputFile(
    Message message,
    String sessionUsername,
  ) async {
    final docs = await getApplicationDocumentsDirectory();
    final voicesDir = Directory(
      PathUtils.join(
        docs.path,
        'EchoTrace',
        'voice',
        sessionUsername,
      ),
    );
    if (!await voicesDir.exists()) {
      await voicesDir.create(recursive: true);
    }

    final sender = message.senderUsername ?? message.myWxid ?? 'unknown';
    final fileName =
        '${message.createTime}_${message.localId}_${sender.replaceAll(RegExp(r"[^a-zA-Z0-9_@.-]"), "_")}.mp3';
    return File(PathUtils.join(voicesDir.path, fileName));
  }

  Future<int?> _calcDuration(Message message) async {
    final senderWxid = message.senderUsername ?? message.myWxid;
    if (senderWxid == null || senderWxid.isEmpty) return null;

    final voiceBytes = await databaseService.fetchVoiceData(
      senderWxid: senderWxid,
      createTime: message.createTime,
    );
    if (voiceBytes == null || voiceBytes.isEmpty) return null;

    final binaries = await _ensureBinariesReady();
    final tempDir = await getTemporaryDirectory();
    final silkPath = PathUtils.join(
      tempDir.path,
      'voice_${message.createTime}_${senderWxid}_dur.silk',
    );
    final pcmPath = PathUtils.replaceExtension(silkPath, '.pcm');

    await File(silkPath).writeAsBytes(voiceBytes, flush: true);

    final decodeResult = await Process.run(
      binaries.silkDecoder,
      [
        silkPath,
        pcmPath,
        '-Fs_API',
        '$_sampleRate',
      ],
    );
    if (decodeResult.exitCode != 0 || !File(pcmPath).existsSync()) {
      try {
        File(silkPath).deleteSync();
      } catch (_) {}
      return null;
    }

    final pcmFile = File(pcmPath);
    final bytes = await pcmFile.readAsBytes();
    final durationSeconds = (bytes.length / (_sampleRate * 2)).round();

    try {
      File(silkPath).deleteSync();
      File(pcmPath).deleteSync();
    } catch (_) {}

    return durationSeconds;
  }

}

class _BinaryPaths {
  _BinaryPaths({
    required this.silkDecoder,
    required this.ffmpeg,
  });

  final String silkDecoder;
  final String ffmpeg;
}
