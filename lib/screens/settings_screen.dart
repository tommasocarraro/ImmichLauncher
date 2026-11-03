import 'package:flutter/material.dart';

import '../controllers/launcher_controller.dart';
import '../models/server_config.dart';
import '../widgets/config_form_fields.dart';

/// Shows all configuration fields pre-filled and lets the user edit them.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final LauncherController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _controllers = ConfigControllers(widget.controller.config);
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _snack('Please fix the highlighted fields.');
      return;
    }
    final config = _controllers.toConfig();
    if (config == null) {
      _snack('Please fix the highlighted fields.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.updateConfig(config);
      if (!mounted) return;
      _snack('Settings saved.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not save settings: $e');
    }
  }

  Future<void> _forgetPassword() async {
    await widget.controller.ssh.forgetPassword();
    if (mounted) _snack('Saved SSH password removed.');
  }

  Future<void> _forgetHostKeys() async {
    await widget.controller.ssh.forgetHostKeys();
    if (mounted) _snack('Trusted SSH host keys reset.');
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Home network'),
              ConfigFieldGroup(
                fields: const [ConfigField.localIp, ConfigField.macAddress],
                controllers: _controllers,
              ),
              _section('Tailscale'),
              ConfigFieldGroup(
                fields: const [
                  ConfigField.tailscaleIp,
                  ConfigField.relayIp,
                  ConfigField.relayPort,
                ],
                controllers: _controllers,
              ),
              _section('Server access'),
              ConfigFieldGroup(
                fields: const [
                  ConfigField.sshUsername,
                  ConfigField.sshPort,
                  ConfigField.immichPort,
                ],
                controllers: _controllers,
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              const SizedBox(height: 24),
              const Divider(),
              _section('Security'),
              ListTile(
                leading: const Icon(Icons.key_off_outlined),
                title: const Text('Forget saved SSH password'),
                onTap: _forgetPassword,
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Reset trusted SSH host keys'),
                subtitle: const Text('Needed only after reinstalling the server OS'),
                onTap: _forgetHostKeys,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
