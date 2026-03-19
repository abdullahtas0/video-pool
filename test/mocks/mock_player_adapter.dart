import 'package:mocktail/mocktail.dart';
import 'package:video_pool/video_pool.dart';

/// Mock [PlayerAdapter] for use in unit tests.
///
/// Uses mocktail to generate stubs for all abstract methods.
class MockPlayerAdapter extends Mock implements PlayerAdapter {}

/// A fake [VideoSource] that can be used with mocktail's `registerFallbackValue`.
class FakeVideoSource extends Fake implements VideoSource {}

/// Register all fallback values needed for [MockPlayerAdapter] tests.
///
/// Call this in `setUpAll` before using `any()` matchers with these types.
void registerPlayerAdapterFallbacks() {
  registerFallbackValue(FakeVideoSource());
  registerFallbackValue(Duration.zero);
}
