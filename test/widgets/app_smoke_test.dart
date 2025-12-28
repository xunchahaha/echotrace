import 'package:echotrace/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EchoTrace app smoke test', (tester) async {
    await tester.pumpWidget(const EchoTraceApp());
    expect(find.text('EchoTrace'), findsWidgets);
  });
}
