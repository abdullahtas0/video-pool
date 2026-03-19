import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_pool/src/core/adapter/player_adapter.dart';
import 'package:video_pool/src/core/adapter/player_state.dart';
import 'package:video_pool/src/core/models/video_source.dart';
import 'package:video_pool/src/core/pool/pool_config.dart';
import 'package:video_pool/src/core/pool/video_pool.dart';
import 'package:video_pool/src/widgets/video_pool_provider.dart';

class MockPlayerAdapter extends Mock implements PlayerAdapter {}

void main() {
  late VideoPool pool;
  late MockPlayerAdapter mockAdapter;

  setUp(() {
    mockAdapter = MockPlayerAdapter();
    when(() => mockAdapter.stateNotifier)
        .thenReturn(ValueNotifier(const PlayerState()));
    when(() => mockAdapter.estimatedMemoryBytes).thenReturn(0);

    pool = VideoPool(
      config: const VideoPoolConfig(maxConcurrent: 1, preloadCount: 0),
      adapterFactory: (_) => mockAdapter,
      sourceResolver: (_) => const VideoSource(url: 'test://video'),
    );
  });

  tearDown(() async {
    when(() => mockAdapter.dispose()).thenAnswer((_) async {});
    await pool.dispose();
  });

  group('VideoPoolProvider', () {
    testWidgets('of() returns pool when provider exists', (tester) async {
      VideoPool? foundPool;

      await tester.pumpWidget(
        VideoPoolProvider(
          pool: pool,
          child: Builder(
            builder: (context) {
              foundPool = VideoPoolProvider.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(foundPool, equals(pool));
    });

    testWidgets('maybeOf() returns null when no provider exists',
        (tester) async {
      VideoPool? foundPool;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            foundPool = VideoPoolProvider.maybeOf(context);
            return const SizedBox();
          },
        ),
      );

      expect(foundPool, isNull);
    });

    testWidgets('maybeOf() returns pool when provider exists', (tester) async {
      VideoPool? foundPool;

      await tester.pumpWidget(
        VideoPoolProvider(
          pool: pool,
          child: Builder(
            builder: (context) {
              foundPool = VideoPoolProvider.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(foundPool, equals(pool));
    });

    testWidgets('of() throws when no provider exists', (tester) async {
      FlutterError? caughtError;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            try {
              VideoPoolProvider.of(context);
            } on FlutterError catch (e) {
              caughtError = e;
            }
            return const SizedBox();
          },
        ),
      );

      expect(caughtError, isNotNull);
      expect(caughtError!.message, contains('VideoPoolProvider'));
    });
  });
}
