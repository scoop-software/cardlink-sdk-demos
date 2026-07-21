import 'dart:async';

import 'package:demo_core/demo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scoop_cardlink/scoop_cardlink_flow.dart';
import 'package:scoop_nfc/scoop_nfc.dart';

/// eRezept upload: bundle selection → card selection → NFC read → upload.
class UploadScreen extends StatefulWidget {
  final DemoSettings settings;

  const UploadScreen({super.key, required this.settings});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _upload = CardlinkUpload.instance;
  CardlinkUploadState? _state;
  StreamSubscription<CardlinkUploadState>? _sub;
  String _can = '';

  @override
  void initState() {
    super.initState();
    _sub = _upload.stateStream.listen(
      (s) => setState(() => _state = s),
      onError: (Object e) => _snack('$e'),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    final s = widget.settings;
    try {
      await _upload.start(CardlinkFlowConfig(
        environment: s.environment,
        websocketUrl: s.websocketUrl.isEmpty ? null : s.websocketUrl,
        oauthBaseUrl: s.oauthBaseUrl.isEmpty ? null : s.oauthBaseUrl,
        oauthClientId: s.oauthClientId.isEmpty ? null : s.oauthClientId,
        allowLoopbackCleartext: s.allowLoopbackCleartext,
        username: s.username,
        password: s.password,
        enableCache: s.enableCache,
      ));
    } on PlatformException catch (e) {
      _snack('${e.code}: ${e.message}');
    }
  }

  Widget _panel() {
    switch (_state) {
      case null:
        return Center(
          child: FilledButton(
              onPressed: _start, child: const Text('Start upload flow')),
        );
      case UploadNeedsBundleState(:final bundles):
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Select a prescription bundle',
                style: Theme.of(context).textTheme.titleMedium),
            for (final bundle in bundles)
              ListTile(
                title: Text(bundle.medicationName),
                subtitle: Text('${bundle.bundleType} · ${bundle.id}'),
                onTap: () => _upload.submitBundle(bundle.id),
              ),
          ],
        );
      case UploadNeedsCardState(:final selectedBundle, :final knownCards):
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Card for ${selectedBundle.medicationName}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            CanInputField(onCanChanged: (v) => _can = v),
            const SizedBox(height: 8),
            for (final card in knownCards)
              ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text(card.displayName ?? card.iccsn),
                onTap: () => _upload.submitKnownCard(card),
              ),
            FilledButton(
              onPressed: () {
                if (_can.length == 6) _upload.submitCardInfo(_can);
              },
              child: const Text('Read card'),
            ),
          ],
        );
      case UploadWaitingForCardState():
        return const Center(child: Text('Hold the card to the phone…'));
      case UploadReadingCardState(:final progress, :final stepLabel):
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(stepLabel),
              ],
            ),
          ),
        );
      case UploadUploadingState():
        return const Center(child: CircularProgressIndicator());
      case UploadCompletedState(:final statusCode):
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Upload complete (HTTP $statusCode)'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _start, child: const Text('Upload another')),
            ],
          ),
        );
      case UploadErrorState(:final message, :final phase):
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error in $phase: $message'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _start, child: const Text('Start over')),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _upload.cancel,
          ),
        ],
      ),
      body: _panel(),
    );
  }
}
