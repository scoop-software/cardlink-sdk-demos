import 'dart:async';

import 'package:demo_core/demo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scoop_cardlink/scoop_cardlink_flow.dart';
import 'package:scoop_nfc/scoop_nfc.dart';

/// Drives the full Cardlink flow: phone/SMS verification, CAN entry with the
/// NFC-owned scanner, known-card quick selection, live NFC progress, and the
/// prescription list with completion details.
class ScanScreen extends StatefulWidget {
  final DemoSettings settings;

  const ScanScreen({super.key, required this.settings});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _flow = CardlinkFlow.instance;
  CardlinkFlowState _state = const IdleState();
  StreamSubscription<CardlinkFlowState>? _sub;
  List<KnownCard> _knownCards = const [];
  final List<String> _prescriptions = [];
  String? _completedIccsn;
  int? _lastTimingMs;
  String _phone = '';
  String _smsCode = '';
  String _can = '';
  bool _progressSheetOpen = false;
  final _smsController = TextEditingController();
  // Accumulated for the whole session so the trace log is populated whenever
  // the sheet is opened (the flow's trace SharedFlow does not replay). Keeping
  // this subscription alive also keeps the bridge's trace collection bound.
  final ValueNotifier<List<String>> _traceLog = ValueNotifier([]);
  StreamSubscription<CardlinkTraceEvent>? _traceSub;

  @override
  void initState() {
    super.initState();
    _sub = _flow.stateStream.listen(_onState, onError: (Object e) {
      _snack('$e');
    });
    _traceSub = _flow.traceStream.listen(
      (e) => _traceLog.value = [..._traceLog.value, e.toString()],
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _traceSub?.cancel();
    _traceLog.dispose();
    _smsController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onState(CardlinkFlowState state) async {
    setState(() => _state = state);
    switch (state) {
      case NeedsSmsCodeState(:final debugSmsCode):
        // In dev/test the server echoes the code back — prefill it so the
        // tester can just tap Verify. Clear otherwise (no stale code).
        _smsCode = debugSmsCode ?? '';
        _smsController.text = debugSmsCode ?? '';
      case NeedsCanState():
        _knownCards = await _flow.getKnownCards();
        if (mounted) setState(() {});
      case WaitingForCardState():
        _openProgressSheet();
      case CompletedState(
          :final iccsn,
          :final prescriptions,
          :final cardContactToResultMs
        ):
        _closeProgressSheet();
        setState(() {
          _completedIccsn = iccsn;
          _lastTimingMs = cardContactToResultMs;
          _prescriptions
            ..clear()
            ..addAll(prescriptions);
        });
        if (cardContactToResultMs != null) {
          widget.settings.recordTiming(TimingEntry(
              label: 'Scan $iccsn', milliseconds: cardContactToResultMs));
        }
      case ErrorState():
      case CancelledState():
        _closeProgressSheet();
      default:
        break;
    }
  }

  void _openProgressSheet() {
    if (_progressSheetOpen || !mounted) return;
    _progressSheetOpen = true;
    NfcProgressSheet.show(context, ScoopNfc.progressStream)
        .whenComplete(() => _progressSheetOpen = false);
  }

  void _closeProgressSheet() {
    if (_progressSheetOpen && mounted) {
      Navigator.of(context).pop();
      _progressSheetOpen = false;
    }
  }

  CardlinkFlowConfig _config() {
    final s = widget.settings;
    return CardlinkFlowConfig(
      environment: s.environment,
      websocketUrl: s.websocketUrl.isEmpty ? null : s.websocketUrl,
      oauthBaseUrl: s.oauthBaseUrl.isEmpty ? null : s.oauthBaseUrl,
      oauthClientId: s.oauthClientId.isEmpty ? null : s.oauthClientId,
      restBaseUrl: s.restBaseUrl.isEmpty ? null : s.restBaseUrl,
      allowLoopbackCleartext: s.allowLoopbackCleartext,
      username: s.username,
      password: s.password,
      enableCache: s.enableCache,
      enableApduTracing: s.enableApduTracing,
      flowType: s.flowType,
    );
  }

  Future<void> _start() async {
    try {
      await _flow.start(_config());
    } on PlatformException catch (e) {
      _snack('${e.code}: ${e.message}');
    }
  }

  Widget _panel() {
    switch (_state) {
      case IdleState() || CancelledState():
        return _centered([
          FilledButton(onPressed: _start, child: const Text('Start scan')),
          if (_state is CancelledState) const Text('Previous run cancelled.'),
        ]);
      case ConnectingState():
        return _busy('Connecting…');
      case NeedsPhoneNumberState():
        return _centered([
          TextField(
            key: const ValueKey('phoneField'),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Phone number', border: OutlineInputBorder()),
            onChanged: (v) => _phone = v,
          ),
          FilledButton(
            onPressed: () => _flow.submitPhoneNumber(_phone),
            child: const Text('Request SMS code'),
          ),
        ]);
      case SmsRequestedState(:final phoneNumber):
        return _busy('SMS requested for $phoneNumber…');
      case NeedsSmsCodeState(:final phoneNumber, :final debugSmsCode):
        return _centered([
          Text('Code sent to $phoneNumber'
              '${debugSmsCode != null ? ' (debug: $debugSmsCode)' : ''}'),
          TextField(
            key: const ValueKey('smsField'),
            controller: _smsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'SMS code', border: OutlineInputBorder()),
            onChanged: (v) => _smsCode = v,
          ),
          FilledButton(
            onPressed: () => _flow.submitSmsCode(_smsCode),
            child: const Text('Verify'),
          ),
        ]);
      case NeedsCanState(:final previousCan):
        return _centered([
          if (previousCan != null) Text('Previous CAN: $previousCan'),
          CanInputField(onCanChanged: (v) => _can = v),
          if (_knownCards.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final card in _knownCards)
                  ActionChip(
                    label: Text(card.displayName ?? card.iccsn),
                    onPressed: () =>
                        _flow.submitKnownCard(card.can, iccsn: card.iccsn),
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
      case WaitingForCardState():
        return _busy('Hold the card to the phone…');
      case ReadingCardState(:final progress, :final stepLabel):
        return _centered([
          LinearProgressIndicator(value: progress),
          Text(stepLabel),
        ]);
      case RegisteringState():
        return _busy('Registering…');
      case WaitingForPrescriptionsState():
        return _busy('Waiting for prescriptions…');
      case CompletedState(:final patientData):
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Completed',
                style: Theme.of(context).textTheme.headlineSmall),
            if (_completedIccsn != null) Text('ICCSN: $_completedIccsn'),
            if (_lastTimingMs != null)
              Text('Card contact → result: $_lastTimingMs ms'),
            if (patientData != null) Text('Patient: ${patientData.fullName}'),
            const SizedBox(height: 12),
            Text('Prescriptions (${_prescriptions.length})',
                style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _prescriptions.length; i++)
              ListTile(
                dense: true,
                title: Text('Prescription ${i + 1}'),
                subtitle: Text(
                  _prescriptions[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _prescriptions.removeAt(i)),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _start, child: const Text('Scan another card')),
          ],
        );
      case ErrorState(:final message, :final isTerminal):
        return _centered([
          Text('Error: $message'),
          if (!isTerminal)
            FilledButton(onPressed: _flow.retry, child: const Text('Retry')),
          TextButton(onPressed: _start, child: const Text('Start over')),
        ]);
    }
  }

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
        title: const Text('Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Trace log',
            onPressed: () => TraceLogSheet.show(context, _traceLog),
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
