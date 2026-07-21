import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom sheet showing the SDK trace log.
///
/// Backed by a [ValueListenable] the host screen keeps filling from the flow's
/// trace stream for the whole session — so the log is already populated
/// whenever the sheet is opened, and keeps updating live while it's open.
class TraceLogSheet {
  TraceLogSheet._();

  static Future<void> show(
    BuildContext context,
    ValueListenable<List<String>> log,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ValueListenableBuilder<List<String>>(
          valueListenable: log,
          builder: (context, lines, _) =>
              TraceLogView(lines: lines, controller: controller),
        ),
      ),
    );
  }
}

class TraceLogView extends StatelessWidget {
  final List<String> lines;
  final ScrollController? controller;

  const TraceLogView({super.key, required this.lines, this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Trace (${lines.length})',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy all',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: lines.join('\n'))),
            ),
          ],
        ),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('No trace events yet.'))
              : ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lines.length,
                  itemBuilder: (context, i) => Text(
                    lines[i],
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
        ),
      ],
    );
  }
}
