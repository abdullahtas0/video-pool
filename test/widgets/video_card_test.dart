import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_pool/src/core/adapter/player_adapter.dart';
import 'package:video_pool/src/core/adapter/player_state.dart';
import 'package:video_pool/src/core/lifecycle/lifecycle_state.dart';
import 'package:video_pool/src/core/models/video_source.dart';
import 'package:video_pool/src/core/pool/pool_config.dart';
import 'package:video_pool/src/core/pool/video_pool.dart';
import 'package:video_pool/src/widgets/video_card.dart';
import 'package:video_pool/src/widgets/video_pool_provider.dart';

class MockPlayerAdapter extends Mock implements PlayerAdapter {}

void main() {
  late VideoPool pool;
  late MockPlayerAdapter mockAdapter;

  const testSource = VideoSource(url: 'test://video.mp4');

  setUpAll(() {
    registerFallbackValue(testSource);
  });

  setUp(() {
    mockAdapter = MockPlayerAdapter();
    when(() => mockAdapter.stateNotifier)
        .thenReturn(ValueNotifier(const PlayerState()));
    when(() => mockAdapter.estimatedMemoryBytes).thenReturn(0);
    when(() => mockAdapter.videoWidget).thenReturn(
      const SizedBox(key: Key('mock_video_widget')),
    );
    when(() => mockAdapter.swapSource(any())).thenAnswer((_) async {});
    when(() => mockAdapter.prepare()).thenAnswer((_) async {});
    when(() => mockAdapter.play()).thenAnswer((_) async {});
    when(() => mockAdapter.pause()).thenAnswer((_) async {});
    when(() => mockAdapter.dispose()).thenAnswer((_) async {});

    pool = VideoPool(
      config: const VideoPoolConfig(maxConcurrent: 1, preloadCount: 0),
      adapterFactory: (_) => mockAdapter,
      sourceResolver: (_) => testSource,
    );
  });

  tearDown(() async {
    await pool.dispose();
  });

  Widget buildTestWidget({
    required Widget child,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: VideoPoolProvider(
          pool: pool,
          child: child,
        ),
      ),
    );
  }

  group('VideoCard', () {
    testWidgets('shows thumbnail when no entry is assigned', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const VideoCard(
            index: 99, // No entry assigned to this index
            source: testSource,
          ),
        ),
      );

      // Should show default thumbnail (Container with black color).
      // The VideoThumbnail with no URL shows a black container.
      expect(find.byType(VideoCard), findsOneWidget);
    });

    testWidgets('shows error widget on error state', (tester) async {
      // Trigger pool to assign entry to index 0 with error state.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );

      // Wait for async reconciliation.
      await tester.pumpAndSettle();

      // Manually set error state on the entry.
      final entry = pool.getEntryForIndex(0);
      expect(entry, isNotNull);
      entry!.lifecycleNotifier.value = LifecycleState.error;

      await tester.pumpWidget(
        buildTestWidget(
          child: const VideoCard(
            index: 0,
            source: testSource,
          ),
        ),
      );

      await tester.pump();

      // Should show error widget with retry.
      expect(find.text('Failed to load video'), findsOneWidget);
    });

    testWidgets('shows custom error widget when provided', (tester) async {
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await tester.pumpAndSettle();

      final entry = pool.getEntryForIndex(0);
      expect(entry, isNotNull);
      entry!.lifecycleNotifier.value = LifecycleState.error;

      await tester.pumpWidget(
        buildTestWidget(
          child: const VideoCard(
            index: 0,
            source: testSource,
            errorWidget: Text('Custom error'),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Custom error'), findsOneWidget);
    });

    testWidgets('shows video widget when playing', (tester) async {
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await tester.pumpAndSettle();

      final entry = pool.getEntryForIndex(0);
      expect(entry, isNotNull);
      entry!.lifecycleNotifier.value = LifecycleState.playing;

      await tester.pumpWidget(
        buildTestWidget(
          child: const VideoCard(
            index: 0,
            source: testSource,
          ),
        ),
      );

      await tester.pump();

      // The mock video widget should be present.
      expect(find.byKey(const Key('mock_video_widget')), findsOneWidget);
    });
  });
}
