# Contributing to video_pool

Thanks for your interest in improving `video_pool`! Contributions of all kinds
are welcome — bug reports, feature ideas, docs, and pull requests.

## Getting started

```bash
git clone https://github.com/abdullahtas0/video-pool.git
cd video-pool
flutter pub get
flutter test
```

The example app lives in [`example/`](example/):

```bash
cd example
flutter run            # or: flutter run -d chrome / -d macos
```

## Before opening a pull request

Please make sure the same checks the CI runs pass locally:

```bash
dart format .
flutter analyze
flutter test
```

- Keep changes focused and add tests for new behavior — the suite is the
  contract (currently 269+ tests).
- Match the surrounding style; files are small and single-purpose by design.
- Update `CHANGELOG.md` under a new `## Unreleased` heading.

## Reporting bugs

Open an issue with: the platform(s) affected, a minimal repro (ideally a tweak
to the example app), `flutter doctor -v` output, and what you expected vs. saw.

## Architecture in one paragraph

`VideoPoolScope` owns a `VideoPool` that keeps a fixed set of `PoolEntry` slots,
each wrapping a `PlayerAdapter` (media_kit by default, or `video_player`). A
`LifecycleOrchestrator` + `LifecyclePolicy` decide which slots play, preload, or
release on every visibility/device-status change, reusing players via
`swapSource()` instead of disposing them. See the
[Architecture section of the README](README.md#architecture).

By contributing you agree that your contributions are licensed under the MIT
License.
