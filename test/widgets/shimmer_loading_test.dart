import 'package:echotrace/widgets/common/shimmer_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shimmer_loading shows child when loading', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShimmerLoading(
          isLoading: true,
          child: Text('content'),
        ),
      ),
    );

    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('shimmer_loading stops animation when loading false',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShimmerLoading(
          isLoading: false,
          child: Text('loaded'),
        ),
      ),
    );

    expect(find.text('loaded'), findsOneWidget);
    // pump a frame to ensure no animation throws
    await tester.pump(const Duration(milliseconds: 500));
  });
}
