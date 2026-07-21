import 'package:flutter/foundation.dart';

import 'timing_list.dart';

/// In-memory demo settings + recorded timings, shared across screens.
///
/// Deliberately not persisted: the demos show credential *handling*, and the
/// SDKs' CredentialStorage interface is the production path for persistence.
class DemoSettings extends ChangeNotifier {
  String username = '';
  String password = '';

  /// 'default' or 'custom'.
  String environment = 'default';
  String websocketUrl = '';
  String oauthBaseUrl = '';
  String oauthClientId = '';
  String restBaseUrl = '';
  bool allowLoopbackCleartext = false;
  bool enableCache = true;
  bool enableApduTracing = false;

  /// 'client' or 'server'.
  String flowType = 'client';

  final List<TimingEntry> timings = [];

  void update(void Function() mutate) {
    mutate();
    notifyListeners();
  }

  void recordTiming(TimingEntry entry) {
    timings.insert(0, entry);
    notifyListeners();
  }
}
