import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom sheet showing live SDK trace lines.
///
/// The subscription exists only while the sheet is open — closing it detaches
/// the listener, which stops native trace collection (listener-bound
/// collection at the bridge).
class TraceLogSheet {
  TraceLogSheet._();

  static Future<void> show(BuildContext context, Stream<String> lines) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) =>
            TraceLogView(lines: lines, controller: controller),
      ),
    );
  }
}

class TraceLogView extends StatefulWidget {
  final Stream<String> lines;
  final ScrollController? controller;

  const TraceLogView({super.key, required this.lines, this.controller});

  @override
  State<TraceLogView> createState() => _TraceLogViewState();
}

class _TraceLogViewState extends State<TraceLogView> {
  final _buffer = <String>[];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: widget.lines,
      builder: (context, snapshot) {
        if (snapshot.hasData) _buffer.add(snapshot.data!);
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Trace (${_buffer.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy all',
                  onPressed: () => Clipboard.setData(
                      ClipboardData(text: _buffer.join('\n'))),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: widget.controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _buffer.length,
                itemBuilder: (context, i) => Text(
                  _buffer[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
