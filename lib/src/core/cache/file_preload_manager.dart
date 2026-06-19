/// Disk-cache manager for video pre-fetching.
///
/// Resolves to the native implementation (`dart:io` + `dart:isolate` based
/// downloads) when `dart:io` is available, and to an inert web stub otherwise,
/// so the package compiles and runs on the web target where `dart:io` does
/// not exist. The shared [CachedFile] type is always available.
library;

export 'file_preload_types.dart';
export 'file_preload_manager_web.dart'
    if (dart.library.io) 'file_preload_manager_io.dart';
