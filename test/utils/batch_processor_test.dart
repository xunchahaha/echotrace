import 'package:echotrace/utils/batch_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('processBatches processes all items and yields per batch', () async {
    final processed = <int>[];
    await BatchProcessor.processBatches<int>(
      List.generate(5, (i) => i),
      (item, idx) async {
        processed.add(item);
      },
      batchSize: 2,
      yieldEveryBatch: true,
    );
    expect(processed, [0, 1, 2, 3, 4]);
  });

  test('processBatchesWithResult collects mapper output', () async {
    final results = await BatchProcessor.processBatchesWithResult<int, String>(
      [1, 2, 3],
      (item, idx) async => 'v$item',
      batchSize: 2,
    );
    expect(results, ['v1', 'v2', 'v3']);
  });

  test('processBatchesWithAggregation aggregates values', () async {
    final sum = await BatchProcessor.processBatchesWithAggregation<int, int>(
      [1, 2, 3, 4],
      (acc, item) async => acc + item,
      initialValue: 0,
      batchSize: 3,
    );
    expect(sum, 10);
  });
}
