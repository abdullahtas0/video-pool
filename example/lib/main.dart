import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'tiktok_example.dart';
import 'instagram_example.dart';
import 'custom_policy_example.dart';
import 'direct_test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ExampleApp());
}

/// Root widget with navigation to the example screens.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'video_pool Examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _HomeScreen(),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('video_pool Examples')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.swipe_vertical),
            title: const Text('TikTok / Reels Feed'),
            subtitle: const Text('Full-screen vertical video feed'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TikTokExample(),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: const Text('Instagram Feed'),
            subtitle: const Text('Mixed content list with video cards'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const InstagramExample(),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.play_circle),
            title: const Text('Direct media_kit Test'),
            subtitle: const Text('No pool — raw media_kit player'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DirectTest(),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Custom Policy'),
            subtitle: const Text('Battery-saver lifecycle policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CustomPolicyExample(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
