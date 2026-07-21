import 'dart:async';

import 'package:demo_core/demo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scoop_nfc/scoop_nfc.dart';
import 'package:scoop_popp/scoop_popp.dart';

/// Drives the full PoPP check-in: LEI selection (QR payload, VZD search,
/// favorites), consent, auth method, CAN/known card, result + history.
class PoppScreen extends StatefulWidget {
  final DemoSettings settings;

  const PoppScreen({super.key, required this.settings});

  @override
  State<PoppScreen> createState() => _PoppScreenState();
}

class _PoppScreenState extends State<PoppScreen> {
  static const _serviceUrl = 'https://popp-sample-server-dev.demo.scoop-gmbh.de';

  final _flow = PoppFlow();
  PoppFlowState _state = const PoppIdleState();
  StreamSubscription<PoppFlowState>? _stateSub;
  StreamSubscription<String>? _nfcSub;
  final List<String> _history = [];
  String _telematikId = '';
  String _qrPayload = '';
  String _vzdQuery = '';
  String _can = '';
  String _nfcMessage = '';

  @override
  void initState() {
    super.initState();
    _stateSub = _flow.stateStream.listen(
      (s) {
        if (s is PoppCompletedState) {
          _history.insert(0, _describeResult(s.result));
        }
        setState(() => _state = s);
      },
      onError: (Object e) => _snack('$e'),
    );
    _nfcSub =
        _flow.nfcMessageStream.listen((m) => setState(() => _nfcMessage = m));
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _nfcSub?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    try {
      await _flow.startCheckIn(
        config: const PoppFlowConfig(
          poppServiceBaseUrl: _serviceUrl,
          vzdBaseUrl: _serviceUrl,
          clientId: 'scoop-cardlink-demo',
        ),
        telematikId: _telematikId.isEmpty ? null : _telematikId,
      );
    } on PlatformException catch (e) {
      _snack('${e.code}: ${e.message}');
    }
  }

  Widget _panel() {
    switch (_state) {
      case PoppIdleState() || PoppCancelledState():
        return _centered([
          TextField(
            decoration: const InputDecoration(
              labelText: 'Telematik-ID (optional)',
              helperText: 'Leave empty for interactive LEI selection',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _telematikId = v,
          ),
          FilledButton(onPressed: _start, child: const Text('Start check-in')),
          if (_state is PoppCancelledState)
            Text('Cancelled: ${(_state as PoppCancelledState).message}'),
          if (_history.isNotEmpty) ...[
            const Divider(),
            Text('History', style: Theme.of(context).textTheme.titleMedium),
            for (final entry in _history.take(5)) Text(entry),
          ],
        ]);
      case PoppInitializingState():
        return _busy('Initializing…');
      case PoppNeedsLeiSelectionMethodState(:final hasFavorites):
        return _centered([
          FilledButton(
            onPressed: () =>
                _flow.submitLeiSelectionMethod(PoppLeiSelectionMethod.qrScan),
            child: const Text('QR code'),
          ),
          FilledButton(
            onPressed: () => _flow
                .submitLeiSelectionMethod(PoppLeiSelectionMethod.vzdSearch),
            child: const Text('Search (VZD)'),
          ),
          FilledButton(
            onPressed: hasFavorites
                ? () => _flow
                    .submitLeiSelectionMethod(PoppLeiSelectionMethod.favorites)
                : null,
            child: const Text('Favorites'),
          ),
        ]);
      case PoppScanningQrState():
        return _centered([
          TextField(
            decoration: const InputDecoration(
              labelText: 'QR payload',
              helperText: 'Paste the popp:// payload from the practice QR',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _qrPayload = v,
          ),
          FilledButton(
            onPressed: () => _flow.submitQrScanResult(_qrPayload),
            child: const Text('Submit'),
          ),
          TextButton(
            onPressed: () => _flow.submitQrScanResult(null),
            child: const Text('Back'),
          ),
        ]);
      case PoppNeedsVzdSearchState():
        return _centered([
          TextField(
            decoration: const InputDecoration(
                labelText: 'Practice name', border: OutlineInputBorder()),
            onChanged: (v) => _vzdQuery = v,
          ),
          FilledButton(
            onPressed: () => _flow.submitVzdSearch(_vzdQuery),
            child: const Text('Search'),
          ),
          TextButton(
            onPressed: () => _flow.submitVzdSearch(null),
            child: const Text('Back'),
          ),
        ]);
      case PoppNeedsFavoriteSelectionState(:final favorites):
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final favorite in favorites)
              ListTile(
                title: Text(favorite.name),
                subtitle: Text(favorite.address ?? favorite.telematikId),
                onTap: () => _flow.submitFavoriteSelection(favorite),
              ),
            TextButton(
              onPressed: () => _flow.submitFavoriteSelection(null),
              child: const Text('Back'),
            ),
          ],
        );
      case PoppNeedsConsentState(:final lei):
        return _centered([
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lei.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(lei.type),
                  if (lei.address != null) Text(lei.address!),
                  Text(lei.telematikId,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          FilledButton(
            onPressed: () => _flow.submitConsent(true),
            child: const Text('Check in here'),
          ),
          TextButton(
            onPressed: () => _flow.submitConsent(false),
            child: const Text('Decline'),
          ),
        ]);
      case PoppNeedsAuthMethodState(:final gidAvailable):
        return _centered([
          FilledButton(
            onPressed: () => _flow.submitAuthMethod(PoppAuthMethod.egk),
            child: const Text('eGK (card)'),
          ),
          FilledButton(
            onPressed: gidAvailable
                ? () => _flow.submitAuthMethod(PoppAuthMethod.gesundheitsId)
                : null,
            child: const Text('GesundheitsID'),
          ),
        ]);
      case PoppNeedsCanState(:final knownCards, :final errorMessage):
        return _centered([
          if (errorMessage != null)
            Text(errorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          CanInputField(onCanChanged: (v) => _can = v),
          if (knownCards.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final card in knownCards)
                  ActionChip(
                    label: Text(card.displayName ?? card.iccsn),
                    onPressed: () => _flow.submitKnownCard(card),
                  ),
              ],
            ),
          FilledButton(
            onPressed: () {
              if (_can.length == 6) _flow.submitCan(_can);
            },
            child: const Text('Read card'),
          ),
        ]);
      case PoppWaitingForCardState():
        return _busy(_nfcMessage.isEmpty
            ? 'Hold the card to the phone…'
            : _nfcMessage);
      case PoppAuthenticatingEgkState():
        return _busy('Authenticating with eGK…');
      case PoppAuthenticatingGidState():
        return _busy('Authenticating with GesundheitsID…');
      case PoppCompletedState(:final result):
        final text = _describeResult(result);
        return _centered([
          Icon(
            result is PoppCheckInSuccess
                ? Icons.check_circle
                : Icons.info_outline,
            size: 48,
          ),
          Text(text, textAlign: TextAlign.center),
          FilledButton(onPressed: _start, child: const Text('New check-in')),
        ]);
      case PoppErrorState(:final message):
        return _centered([
          Text('Error: $message'),
          FilledButton(onPressed: _start, child: const Text('Start over')),
        ]);
    }
  }

  String _describeResult(PoppCheckInResult result) => switch (result) {
        PoppCheckInSuccess(:final poppDatasetId) =>
          'Check-in successful (dataset $poppDatasetId)',
        PoppCheckInPending(:final message) => 'Pending: $message',
        PoppCheckInCancelled(:final message) => 'Cancelled: $message',
        PoppCheckInError(:final code, :final message) => '$code: $message',
      };

  Widget _centered(List<Widget> children) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children) ...[child, const SizedBox(height: 12)],
            ],
          ),
        ),
      );

  Widget _busy(String label) => _centered([
        const Center(child: CircularProgressIndicator()),
        Text(label, textAlign: TextAlign.center),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PoPP check-in'),
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Trace log',
            onPressed: () => TraceLogSheet.show(context, _flow.traceStream),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _flow.cancel,
          ),
        ],
      ),
      body: _panel(),
    );
  }
}
