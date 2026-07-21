import 'package:cardlink_demo/screens/scan_screen.dart';
import 'package:cardlink_demo/screens/settings_screen.dart';
import 'package:cardlink_demo/screens/timing_screen.dart';
import 'package:cardlink_demo/screens/upload_screen.dart';
import 'package:demo_core/demo_core.dart';
import 'package:flutter/material.dart';

import 'screens/popp_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await DemoSettings.load();
  runApp(FullDemoApp(settings: settings));
}

class FullDemoApp extends StatefulWidget {
  final DemoSettings settings;

  const FullDemoApp({super.key, required this.settings});

  @override
  State<FullDemoApp> createState() => _FullDemoAppState();
}

class _FullDemoAppState extends State<FullDemoApp> {
  DemoSettings get _settings => widget.settings;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scoop Full Demo',
      theme: DemoTheme.light,
      darkTheme: DemoTheme.dark,
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            ScanScreen(settings: _settings),
            UploadScreen(settings: _settings),
            PoppScreen(settings: _settings),
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
            NavigationDestination(
                icon: Icon(Icons.local_hospital), label: 'PoPP'),
            NavigationDestination(icon: Icon(Icons.timeline), label: 'Timing'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
