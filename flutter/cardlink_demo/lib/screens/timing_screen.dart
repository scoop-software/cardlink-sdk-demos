import 'package:demo_core/demo_core.dart';
import 'package:flutter/material.dart';

/// Per-scan timing summaries recorded from completed flows.
class TimingScreen extends StatelessWidget {
  final DemoSettings settings;

  const TimingScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timing')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => TimingList(entries: settings.timings),
      ),
    );
  }
}
