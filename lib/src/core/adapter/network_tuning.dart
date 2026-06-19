/// Conditional entry point for libmpv network/HLS tuning.
///
/// Resolves to the native implementation (which calls
/// `NativePlayer.setProperty`) when `dart:io` is available, and to a web
/// no-op otherwise — so the package compiles for the web target where
/// `NativePlayer.setProperty` does not exist.
library;

export 'network_tuning_web.dart' if (dart.library.io) 'network_tuning_io.dart';
