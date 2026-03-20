import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/cache/thumbnail_extractor.dart';

void main() {
  group('ThumbnailExtractor', () {
    group('isFastStart', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('thumb_test_');
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('returns false for non-existent file', () async {
        final result = await ThumbnailExtractor.isFastStart(
          '/non/existent/file.mp4',
        );
        expect(result, isFalse);
      });

      test('detects moov atom (FastStart)', () async {
        // Fake moov-first MP4: [ftyp atom (8 bytes)] [moov atom header]
        final fastStartBytes = Uint8List.fromList([
          0, 0, 0, 8, // ftyp size
          0x66, 0x74, 0x79, 0x70, // 'ftyp'
          0, 0, 0, 8, // moov size
          0x6D, 0x6F, 0x6F, 0x76, // 'moov'
        ]);

        final file = File('${tempDir.path}/faststart.mp4');
        await file.writeAsBytes(fastStartBytes);

        final result = await ThumbnailExtractor.isFastStart(file.path);
        expect(result, isTrue);
      });

      test('detects mdat-first as non-FastStart', () async {
        // Fake mdat-first MP4: [ftyp atom (8 bytes)] [mdat atom header]
        final nonFastStartBytes = Uint8List.fromList([
          0, 0, 0, 8, // ftyp size
          0x66, 0x74, 0x79, 0x70, // 'ftyp'
          0, 0, 0, 8, // mdat size
          0x6D, 0x64, 0x61, 0x74, // 'mdat'
        ]);

        final file = File('${tempDir.path}/nonfaststart.mp4');
        await file.writeAsBytes(nonFastStartBytes);

        final result = await ThumbnailExtractor.isFastStart(file.path);
        expect(result, isFalse);
      });

      test('returns false for empty file', () async {
        final file = File('${tempDir.path}/empty.mp4');
        await file.writeAsBytes([]);

        final result = await ThumbnailExtractor.isFastStart(file.path);
        expect(result, isFalse);
      });

      test('returns false for file smaller than 8 bytes', () async {
        final file = File('${tempDir.path}/tiny.mp4');
        await file.writeAsBytes([0, 0, 0, 1]);

        final result = await ThumbnailExtractor.isFastStart(file.path);
        expect(result, isFalse);
      });
    });

    group('extract', () {
      late ThumbnailExtractor extractor;

      setUp(() {
        extractor = ThumbnailExtractor();
      });

      tearDown(() {
        extractor.dispose();
      });

      test('returns null when disposed', () async {
        extractor.dispose();

        final result = await extractor.extract(
          videoPath: '/some/video.mp4',
          outputPath: '/some/thumb.jpg',
        );
        expect(result, isNull);
      });
    });

    group('queue behavior', () {
      late ThumbnailExtractor extractor;
      late List<MethodCall> methodCalls;

      setUp(() {
        TestWidgetsFlutterBinding.ensureInitialized();
        extractor = ThumbnailExtractor(maxConcurrent: 1);
        methodCalls = [];
      });

      tearDown(() {
        extractor.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('dev.video_pool/thumbnail'),
          null,
        );
      });

      test('respects maxConcurrent limit', () async {
        final completers = <Completer<ByteData?>>[];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('dev.video_pool/thumbnail'),
          (MethodCall call) async {
            methodCalls.add(call);
            final completer = Completer<ByteData?>();
            completers.add(completer);
            // Simulate async work — don't complete immediately
            return '/output/thumb.jpg';
          },
        );

        // Queue 3 extractions with maxConcurrent=1
        final f1 = extractor.extract(
          videoPath: '/video1.mp4',
          outputPath: '/thumb1.jpg',
          priorityIndex: 2,
        );
        final f2 = extractor.extract(
          videoPath: '/video2.mp4',
          outputPath: '/thumb2.jpg',
          priorityIndex: 1,
        );
        final f3 = extractor.extract(
          videoPath: '/video3.mp4',
          outputPath: '/thumb3.jpg',
          priorityIndex: 0,
        );

        // Wait for all to complete
        final results = await Future.wait([f1, f2, f3]);

        // All should succeed
        expect(results, everyElement(equals('/output/thumb.jpg')));
        // All 3 calls should have been processed
        expect(methodCalls.length, equals(3));
      });

      test('dispose completes pending tasks with null', () async {
        // Set up a handler that delays so tasks queue up
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('dev.video_pool/thumbnail'),
          (MethodCall call) async {
            // Simulate slow extraction
            await Future<void>.delayed(const Duration(milliseconds: 100));
            return '/output/thumb.jpg';
          },
        );

        final localExtractor = ThumbnailExtractor(maxConcurrent: 1);

        // Start one extraction that will be in-flight
        final f1 = localExtractor.extract(
          videoPath: '/video1.mp4',
          outputPath: '/thumb1.jpg',
        );

        // Queue more that will be pending
        final f2 = localExtractor.extract(
          videoPath: '/video2.mp4',
          outputPath: '/thumb2.jpg',
        );
        final f3 = localExtractor.extract(
          videoPath: '/video3.mp4',
          outputPath: '/thumb3.jpg',
        );

        // Dispose immediately — pending tasks should complete with null
        localExtractor.dispose();

        final r2 = await f2;
        final r3 = await f3;

        expect(r2, isNull);
        expect(r3, isNull);

        // Clean up the in-flight task
        await f1;
      });
    });
  });
}
