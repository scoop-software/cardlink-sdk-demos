import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import 'timing_list.dart';

/// Demo settings shared across screens, persisted across app launches and —
/// on iOS — shared between the demo apps that declare the same App Group.
///
/// Persistence is a demo convenience only. Production apps hold OAuth tokens
/// and session state via the SDK's `CredentialStorage` (Keychain-backed); the
/// raw username/password here are stored in the App Group's UserDefaults suite
/// purely so the demos remember them and hand them off between each other.
class DemoSettings extends ChangeNotifier {
  DemoSettings._(this._store);

  /// App Group id used as the iOS UserDefaults suite so both demo apps share
  /// the same settings. Must match the App Group in the apps' entitlements.
  static const _appGroupSuite = 'group.de.scoopsoftware.cardlink.demo';

  final SharedPreferencesAsync _store;

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

  /// Loads persisted settings from the shared suite. Call once before runApp.
  static Future<DemoSettings> load() async {
    // On Apple platforms the App Group's UserDefaults suite makes the store
    // shared across the demo apps; elsewhere it's a normal per-app store.
    final options = (Platform.isIOS || Platform.isMacOS)
        ? SharedPreferencesAsyncFoundationOptions(suiteName: _appGroupSuite)
        : const SharedPreferencesOptions();
    final store = SharedPreferencesAsync(options: options);
    final s = DemoSettings._(store);
    try {
      s.username = await store.getString('username') ?? '';
      s.password = await store.getString('password') ?? '';
      s.environment = await store.getString('environment') ?? 'default';
      s.websocketUrl = await store.getString('websocketUrl') ?? '';
      s.oauthBaseUrl = await store.getString('oauthBaseUrl') ?? '';
      s.oauthClientId = await store.getString('oauthClientId') ?? '';
      s.restBaseUrl = await store.getString('restBaseUrl') ?? '';
      s.allowLoopbackCleartext =
          await store.getBool('allowLoopbackCleartext') ?? false;
      s.enableCache = await store.getBool('enableCache') ?? true;
      s.enableApduTracing = await store.getBool('enableApduTracing') ?? false;
      s.flowType = await store.getString('flowType') ?? 'client';
    } catch (_) {
      // First run or storage unavailable — defaults are fine.
    }
    return s;
  }

  void update(void Function() mutate) {
    mutate();
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      await _store.setString('username', username);
      await _store.setString('password', password);
      await _store.setString('environment', environment);
      await _store.setString('websocketUrl', websocketUrl);
      await _store.setString('oauthBaseUrl', oauthBaseUrl);
      await _store.setString('oauthClientId', oauthClientId);
      await _store.setString('restBaseUrl', restBaseUrl);
      await _store.setBool('allowLoopbackCleartext', allowLoopbackCleartext);
      await _store.setBool('enableCache', enableCache);
      await _store.setBool('enableApduTracing', enableApduTracing);
      await _store.setString('flowType', flowType);
    } catch (_) {
      // Best-effort persistence; ignore storage failures in the demo.
    }
  }

  void recordTiming(TimingEntry entry) {
    timings.insert(0, entry);
    notifyListeners();
  }
}
