import 'database_service.dart';
import '../models/message.dart';
import '../models/contact_record.dart';
import '../models/contact.dart';

/// 双人报告数据服务
class DualReportService {
  final DatabaseService _databaseService;

  DualReportService(this._databaseService);

  /// 生成双人报告数据
  Future<Map<String, dynamic>> generateDualReportData({
    required String friendUsername,
    required String friendName,
    required String myName,
    int? year,
  }) async {
    // 获取第一次聊天信息
    final firstChat = await _getFirstChatInfo(friendUsername);

    // 获取今年第一次聊天信息
    final thisYearFirstChat = await _getThisYearFirstChatInfo(
      friendUsername,
      friendName,
      year ?? DateTime.now().year,
    );

    // 获取我的微信显示名称
    final myDisplayName = await _getMyDisplayName(myName);

    return {
      'myName': myDisplayName,
      'friendUsername': friendUsername,
      'friendName': friendName,
      'year': year,
      'firstChat': firstChat,
      'thisYearFirstChat': thisYearFirstChat,
    };
  }

  /// 获取我的微信显示名称
  Future<String> _getMyDisplayName(String myWxid) async {
    try {
      // 从 contact 数据库获取所有联系人，找到自己的记录
      final contacts = await _databaseService.getAllContacts();

      // 尝试精确匹配
      final myContactRecord = contacts.firstWhere(
        (c) => c.contact.username == myWxid,
        orElse: () => contacts.firstWhere(
          (c) => c.contact.username.contains(myWxid) || myWxid.contains(c.contact.username),
          orElse: () => ContactRecord(
            contact: Contact(
              id: 0,
              username: myWxid,
              localType: 0,
              alias: '',
              encryptUsername: '',
              flag: 0,
              deleteFlag: 0,
              verifyFlag: 0,
              remark: '',
              remarkQuanPin: '',
              remarkPinYinInitial: '',
              nickName: '',
              pinYinInitial: '',
              quanPin: '',
              bigHeadUrl: '',
              smallHeadUrl: '',
              headImgMd5: '',
              chatRoomNotify: 0,
              isInChatRoom: 0,
              description: '',
              extraBuffer: [],
              chatRoomType: 0,
            ),
            source: ContactRecognitionSource.friend,
            origin: ContactDataOrigin.unknown,
          ),
        ),
      );

      // 使用 Contact 的 displayName getter（已处理 remark/nickName/alias 优先级）
      return myContactRecord.contact.displayName;
    } catch (e) {
      print('获取我的显示名称失败: $e');
      return myWxid;
    }
  }

  /// 获取第一次聊天信息
  Future<Map<String, dynamic>?> _getFirstChatInfo(String username) async {
    try {
      // 使用 getMessagesByDate 从1970年1月1日到现在，获取所有历史消息
      final now = DateTime.now();
      final startTimestamp = 0; // 1970年1月1日
      final endTimestamp = now.millisecondsSinceEpoch ~/ 1000; // 当前时间

      print('查询所有历史消息范围: $startTimestamp - $endTimestamp (${DateTime.fromMillisecondsSinceEpoch(startTimestamp*1000)} - ${DateTime.fromMillisecondsSinceEpoch(endTimestamp*1000)})');
      final allMessages = await _databaseService.getMessagesByDate(
        username,
        startTimestamp,
        endTimestamp,
      );

      print('所有历史消息数量: ${allMessages.length}');
      if (allMessages.isEmpty) {
        print('没有找到历史消息');
        return null;
      }

      // getMessagesByDate 返回的是降序（最新在前），需要按升序排序
      allMessages.sort((a, b) => a.createTime.compareTo(b.createTime));

      // 调试：打印前5条消息的时间
      print('排序后的前5条消息时间:');
      for (int i = 0; i < (allMessages.length > 5 ? 5 : allMessages.length); i++) {
        final msg = allMessages[i];
        final timeMs = msg.createTime * 1000;
        print('  [$i] ${msg.createTime} -> ${DateTime.fromMillisecondsSinceEpoch(timeMs)}');
      }

      final firstMessage = allMessages.first;
      // createTime 是秒级时间戳，需要转换为毫秒
      final createTimeMs = firstMessage.createTime * 1000;
      print('找到的第一条消息时间: ${firstMessage.createTime} -> ${DateTime.fromMillisecondsSinceEpoch(createTimeMs)}');

      return {
        'createTime': createTimeMs,  // 毫秒时间戳
        'createTimeStr': _formatDateTime(createTimeMs), // 格式化的时间字符串
        'content': firstMessage.messageContent,
        'isSentByMe': firstMessage.isSend == 1,
        'senderUsername': firstMessage.senderUsername,
      };
    } catch (e) {
      print('获取第一次聊天信息失败: $e');
      return null;
    }
  }

  /// 获取今年第一次聊天信息（包括前三句对话）
  Future<Map<String, dynamic>?> _getThisYearFirstChatInfo(
    String username,
    String friendName,
    int year,
  ) async {
    try {
      // 定义今年的时间范围
      final startOfYear = DateTime(year, 1, 1);
      final endOfYear = DateTime(year, 12, 31, 23, 59, 59);

      final startTimestamp = startOfYear.millisecondsSinceEpoch ~/ 1000;
      final endTimestamp = endOfYear.millisecondsSinceEpoch ~/ 1000;

      // 直接按日期范围查询今年的消息
      print('查询今年消息范围: $startTimestamp - $endTimestamp (${DateTime.fromMillisecondsSinceEpoch(startTimestamp*1000)} - ${DateTime.fromMillisecondsSinceEpoch(endTimestamp*1000)})');
      final thisYearMessages = await _databaseService.getMessagesByDate(
        username,
        startTimestamp,
        endTimestamp,
      );

      print('今年消息数量: ${thisYearMessages.length}');
      if (thisYearMessages.isEmpty) {
        print('今年没有找到消息');
        return null;
      }

      // 确保按时间升序排序，第一条就是今年最早的
      thisYearMessages.sort((a, b) => a.createTime.compareTo(b.createTime));
      final firstMessage = thisYearMessages.first;
      final createTimeMs = firstMessage.createTime * 1000; // 转换为毫秒
      print('找到的今年第一条消息时间: ${firstMessage.createTime} -> ${DateTime.fromMillisecondsSinceEpoch(createTimeMs)}');

      // 获取前三条消息（包含时间）
      final firstThreeMessages = thisYearMessages.take(3).map((msg) {
        final msgTimeMs = msg.createTime * 1000;
        return {
          'content': msg.messageContent,
          'isSentByMe': msg.isSend == 1,
          'createTime': msg.createTime,
          'createTimeStr': _formatDateTime(msgTimeMs),
        };
      }).toList();

      return {
        'createTime': createTimeMs,
        'createTimeStr': _formatDateTime(createTimeMs),
        'content': firstMessage.messageContent,
        'isSentByMe': firstMessage.isSend == 1,
        'friendName': friendName,
        'firstThreeMessages': firstThreeMessages,
      };
    } catch (e) {
      print('获取今年第一次聊天信息失败: $e');
      return null;
    }
  }

  /// 格式化时间（显示日期和时间）
  String _formatDateTime(int millisecondsSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}
