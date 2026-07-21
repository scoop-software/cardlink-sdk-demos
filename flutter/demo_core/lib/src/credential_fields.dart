import 'package:flutter/material.dart';

import 'settings_widgets.dart';

/// Username/password entry pair used by all demos.
class CredentialFields extends StatelessWidget {
  final String username;
  final String password;
  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<String> onPasswordChanged;

  const CredentialFields({
    super.key,
    required this.username,
    required this.password,
    required this.onUsernameChanged,
    required this.onPasswordChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsTextField(
            label: 'Username', value: username, onChanged: onUsernameChanged),
        SettingsTextField(
            label: 'Password',
            value: password,
            obscure: true,
            onChanged: onPasswordChanged),
      ],
    );
  }
}
