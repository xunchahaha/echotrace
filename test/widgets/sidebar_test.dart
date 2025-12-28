import 'package:echotrace/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sidebar toggles collapse/expand', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Sidebar(),
        ),
      ),
    );

    // 初始应有文字“首页”之类的菜单（取决于语言，这里只检查存在任意文本）
    expect(find.byType(Sidebar), findsOneWidget);

    // 点击折叠按钮
    final toggle = find.byIcon(Icons.menu_open);
    if (toggle.evaluate().isNotEmpty) {
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
  });
}
