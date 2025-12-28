import 'dart:io';

import 'package:echotrace/services/wxid_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('scan returns wxid from directory names', () async {
    final tmp = await Directory.systemTemp.createTemp('wxid_scan_test');
    final target = Directory(p.join(tmp.path, 'wxid_abc123'));
    await target.create(recursive: true);

    final wxids = await WxidScanService.scanWxids(tmp.path);
    expect(wxids, contains('wxid_abc123'));
  });
}
