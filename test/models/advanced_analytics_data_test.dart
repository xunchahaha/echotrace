import 'package:echotrace/models/advanced_analytics_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ActivityHeatmap returns counts and normalized values', () {
    final heatmap = ActivityHeatmap(
      data: {
        8: {1: 5, 2: 1},
        9: {1: 10},
      },
      maxCount: 10,
    );

    expect(heatmap.getCount(8, 1), 5);
    expect(heatmap.getCount(7, 1), 0);
    expect(heatmap.getNormalizedValue(9, 1), 1.0);

    final most = heatmap.getMostActiveTime();
    expect(most['hour'], 9);
    expect(most['weekday'], 1);
    expect(most['count'], 10);
  });
}
