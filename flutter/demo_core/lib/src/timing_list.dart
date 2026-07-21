import 'package:flutter/material.dart';

/// One per-scan timing measurement.
class TimingEntry {
  final String label;
  final int milliseconds;

  const TimingEntry({required this.label, required this.milliseconds});
}

/// Timing summaries as a list with simple proportional bars — no chart
/// package.
class TimingList extends StatelessWidget {
  final List<TimingEntry> entries;

  const TimingList({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No timings recorded yet.'));
    }
    final max = entries
        .map((e) => e.milliseconds)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, 1 << 31);
    final barColor = Theme.of(context).colorScheme.primary;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final e = entries[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.label} — ${e.milliseconds} ms'),
            const SizedBox(height: 4),
            FractionallySizedBox(
              widthFactor: e.milliseconds / max,
              child: Container(height: 8, color: barColor),
            ),
          ],
        );
      },
    );
  }
}
