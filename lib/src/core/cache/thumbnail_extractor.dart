/// First-frame thumbnail extraction for cached videos.
///
/// Resolves to the native implementation (`dart:io` + the
/// `dev.video_pool/thumbnail` platform channel) when `dart:io` is available,
/// and to an inert web stub otherwise, so the package compiles on web.
library;

export 'thumbnail_extractor_web.dart'
    if (dart.library.io) 'thumbnail_extractor_io.dart';
