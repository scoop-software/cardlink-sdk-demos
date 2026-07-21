import 'package:demo_core/demo_core.dart';
import 'package:flutter/material.dart';

import 'screens/scan_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/timing_screen.dart';
import 'screens/upload_screen.dart';

void main() => runApp(CardlinkDemoApp());

class CardlinkDemoApp extends StatefulWidget {
  const CardlinkDemoApp({super.key});

  @override
  State<CardlinkDemoApp> createState() => _CardlinkDemoAppState();
}

class _CardlinkDemoAppState extends State<CardlinkDemoApp> {
  final _settings = DemoSettings();
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardlink Demo',
      theme: DemoTheme.light,
      darkTheme: DemoTheme.dark,
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            ScanScreen(settings: _settings),
            UploadScreen(settings: _settings),
            TimingScreen(settings: _settings),
            SettingsScreen(settings: _settings),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.nfc), label: 'Scan'),
            NavigationDestination(
                icon: Icon(Icons.upload_file), label: 'Upload'),
            NavigationDestination(icon: Icon(Icons.timeline), label: 'Timing'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
