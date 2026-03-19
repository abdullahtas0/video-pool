import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/widgets/video_error_widget.dart';

void main() {
  group('VideoErrorWidget', () {
    testWidgets('shows default error message when errorMessage is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoErrorWidget(),
          ),
        ),
      );

      expect(find.text('Failed to load video'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows custom error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoErrorWidget(
              errorMessage: 'Network error occurred',
            ),
          ),
        ),
      );

      expect(find.text('Network error occurred'), findsOneWidget);
    });

    testWidgets('shows retry button when onRetry is provided',
        (tester) async {
      var retryCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoErrorWidget(
              onRetry: () => retryCount++,
            ),
          ),
        ),
      );

      expect(find.text('Tap to retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      await tester.tap(find.text('Tap to retry'));
      expect(retryCount, 1);
    });

    testWidgets('does not show retry button when onRetry is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoErrorWidget(),
          ),
        ),
      );

      expect(find.text('Tap to retry'), findsNothing);
    });
  });
}
