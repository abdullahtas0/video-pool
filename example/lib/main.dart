import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_pool/video_pool.dart';

import 'discover_tab.dart';
import 'event_debug_overlay.dart';
import 'feed_tab.dart';
import 'insights_tab.dart';
import 'video_sources.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ShowcaseApp());
}

/// Production-grade showcase app for the video_pool package.
///
/// Three tabs:
/// - Feed: TikTok/Reels full-screen vertical video feed
/// - Discover: Instagram-style mixed content list
/// - Insights: Live analytics dashboard
class ShowcaseApp extends StatelessWidget {
  const ShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'video_pool Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const _AppShell(),
    );
  }
}

/// The app shell managing bottom navigation and shared pool lifecycle.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _currentTab = 0;

  // Shared pool for Feed + Insights tabs.
  VideoPool? _pool;
  FilePreloadManager? _cacheManager;
  DeviceMonitor? _deviceMonitor;
  AudioFocusManager? _audioFocusManager;
  StreamSubscription<DeviceStatus>? _statusSubscription;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initPool();
  }

  Future<void> _initPool() async {
    // Initialize disk cache.
    final cacheDir = await getTemporaryDirectory();
    final cacheManager = FilePreloadManager(
      cacheDirectory: '${cacheDir.path}/video_pool_cache',
    );
    await cacheManager.loadManifest();

    if (!mounted) {
      cacheManager.dispose();
      return;
    }

    // Create the shared pool.
    final pool = VideoPool(
      config: const VideoPoolConfig(
        maxConcurrent: 3,
        preloadCount: 1,
        logLevel: LogLevel.debug,
      ),
      adapterFactory: (_) => MediaKitAdapter(),
      sourceResolver: (index) =>
          index >= 0 && index < feedVideos.length ? feedVideos[index] : null,
      filePreloadManager: cacheManager,
    );

    // Device monitoring.
    final deviceMonitor = DeviceMonitor();
    try {
      await deviceMonitor.startMonitoring();
    } catch (_) {
      // May not be available on all platforms.
    }

    final statusSub = deviceMonitor.statusStream.listen((status) {
      pool.onDeviceStatusChanged(
        thermalLevel: status.thermalLevel,
        memoryPressure: status.memoryPressureLevel,
      );
    });

    // Audio focus.
    final audioFocus = AudioFocusManager(platform: deviceMonitor);
    audioFocus.setCallbacks(
      onPause: () {
        pool.onVisibilityChanged(
          primaryIndex: -1,
          visibilityRatios: const {},
        );
      },
      onResume: () {
        pool.resumeLastState();
      },
    );
    audioFocus.startObserving();

    if (!mounted) {
      pool.dispose();
      cacheManager.dispose();
      statusSub.cancel();
      audioFocus.dispose();
      return;
    }

    setState(() {
      _pool = pool;
      _cacheManager = cacheManager;
      _deviceMonitor = deviceMonitor;
      _audioFocusManager = audioFocus;
      _statusSubscription = statusSub;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _audioFocusManager?.dispose().catchError((_) {});
    _pool?.dispose().catchError((_) {});
    _cacheManager?.dispose();
    try {
      _deviceMonitor?.stopMonitoring();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _pool == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF7C4DFF)),
              SizedBox(height: 16),
              Text(
                'Initializing pool...',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentTab,
        children: [
          // Tab 0: Feed
          VideoPoolProvider(
            pool: _pool!,
            child: const EventDebugOverlay(
              child: FeedTab(),
            ),
          ),

          // Tab 1: Discover (owns its own pool via VideoPoolScope)
          const DiscoverTab(),

          // Tab 2: Insights
          InsightsTab(pool: _pool!),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) {
          setState(() => _currentTab = index);
        },
        backgroundColor: const Color(0xFF0D0D1A),
        indicatorColor: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle_filled,
                color: Color(0xFF7C4DFF)),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon:
                Icon(Icons.explore, color: Color(0xFF7C4DFF)),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon:
                Icon(Icons.insights, color: Color(0xFF7C4DFF)),
            label: 'Insights',
          ),
        ],
      ),
    );
  }
}
