import 'package:demo_core/demo_core.dart';
import 'package:flutter/material.dart';

/// Environment selection (Default/Custom incl. the development loopback
/// policy) and credential handling.
class SettingsScreen extends StatelessWidget {
  final DemoSettings settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          children: [
            SettingsSection(title: 'Credentials', children: [
              CredentialFields(
                username: settings.username,
                password: settings.password,
                onUsernameChanged: (v) =>
                    settings.update(() => settings.username = v),
                onPasswordChanged: (v) =>
                    settings.update(() => settings.password = v),
              ),
            ]),
            SettingsSection(title: 'Environment', children: [
              RadioGroup<String>(
                groupValue: settings.environment,
                onChanged: (v) =>
                    settings.update(() => settings.environment = v!),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                        title: Text('Default'), value: 'default'),
                    RadioListTile<String>(
                        title: Text('Custom'), value: 'custom'),
                  ],
                ),
              ),
              if (settings.environment == 'custom') ...[
                SettingsTextField(
                  label: 'WebSocket URL (wss://…)',
                  value: settings.websocketUrl,
                  onChanged: (v) =>
                      settings.update(() => settings.websocketUrl = v),
                ),
                SettingsTextField(
                  label: 'OAuth base URL (https://…)',
                  value: settings.oauthBaseUrl,
                  onChanged: (v) =>
                      settings.update(() => settings.oauthBaseUrl = v),
                ),
                SettingsTextField(
                  label: 'OAuth client id',
                  value: settings.oauthClientId,
                  onChanged: (v) =>
                      settings.update(() => settings.oauthClientId = v),
                ),
                SettingsTextField(
                  label: 'REST base URL (server flow)',
                  value: settings.restBaseUrl,
                  onChanged: (v) =>
                      settings.update(() => settings.restBaseUrl = v),
                ),
                SwitchListTile(
                  title: const Text('Allow loopback cleartext (dev only)'),
                  subtitle: const Text(
                      'Permits ws/http to localhost-class hosts only'),
                  value: settings.allowLoopbackCleartext,
                  onChanged: (v) => settings
                      .update(() => settings.allowLoopbackCleartext = v),
                ),
              ],
            ]),
            SettingsSection(title: 'Flow', children: [
              SwitchListTile(
                title: const Text('Server-driven flow'),
                value: settings.flowType == 'server',
                onChanged: (v) => settings
                    .update(() => settings.flowType = v ? 'server' : 'client'),
              ),
              SwitchListTile(
                title: const Text('Card file cache'),
                value: settings.enableCache,
                onChanged: (v) =>
                    settings.update(() => settings.enableCache = v),
              ),
              SwitchListTile(
                title: const Text('APDU tracing'),
                value: settings.enableApduTracing,
                onChanged: (v) =>
                    settings.update(() => settings.enableApduTracing = v),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
