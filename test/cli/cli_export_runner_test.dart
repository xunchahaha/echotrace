import 'package:echotrace/cli/cli_export_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns null when no CLI args (fall through to UI)', () async {
    final runner = CliExportRunner();
    final code = await runner.tryHandle([]);
    expect(code, isNull);
  });

  test('shows help and exits 0 when -h is provided', () async {
    final runner = CliExportRunner();
    final code = await runner.tryHandle(['-h']);
    expect(code, 0);
  });

  test('errors on unsupported format', () async {
    final runner = CliExportRunner();
    final code = await runner.tryHandle(['-e', 'C:\\\\tmp', '--format', 'bad']);
    expect(code, 1);
  });

  test('errors when -e has no directory', () async {
    final runner = CliExportRunner();
    final code = await runner.tryHandle(['-e']);
    expect(code, 1);
  });
}
