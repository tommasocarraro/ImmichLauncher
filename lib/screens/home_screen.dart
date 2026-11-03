import 'package:flutter/material.dart';

import '../controllers/launcher_controller.dart';
import '../models/server_config.dart';
import '../widgets/status_indicator.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final LauncherController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  LauncherController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't poll in the background; refresh immediately when coming back.
    if (state == AppLifecycleState.resumed) {
      _c.startPolling();
    } else if (state == AppLifecycleState.paused) {
      _c.stopPolling();
    }
  }

  void _show(ActionOutcome outcome) {
    if (!mounted || outcome.message == null) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(outcome.message!),
        backgroundColor: outcome.isError ? theme.colorScheme.error : null,
        duration: Duration(seconds: outcome.isError ? 8 : 4),
        showCloseIcon: true,
      ));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(controller: _c),
    ));
  }

  Future<void> _confirmShutdown() async {
    final route = _c.shutdownRoute;
    if (route == null) return;
    final host = _c.config.hostFor(route);
    final saved = await _c.ssh.savedPassword();
    if (!mounted) return;

    final result = await showDialog<_ShutdownRequest>(
      context: context,
      builder: (_) => _ShutdownDialog(
        username: _c.config.sshUsername,
        host: host,
        routeLabel: route.label,
        savedPassword: saved,
      ),
    );
    if (result == null) return;
    _show(await _c.shutdown(
      password: result.password,
      rememberPassword: result.remember,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final busy = _c.busy;
        return Scaffold(
          appBar: AppBar(
            title: const Text('ImmichLauncher'),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings),
                onPressed: busy ? null : _openSettings,
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                StatusIndicator(
                  status: _c.status,
                  onlineVia: _c.onlineVia,
                  lastChecked: _c.lastChecked,
                  onRefresh: _c.refreshStatus,
                ),
                const SizedBox(height: 32),
                _BigButton(
                  icon: Icons.home_outlined,
                  label: 'Open Locally',
                  caption: 'On your home Wi-Fi · ${_c.config.localIp}',
                  onPressed: busy ? null : () async => _show(await _c.openLocally()),
                ),
                const SizedBox(height: 16),
                _BigButton(
                  icon: Icons.public,
                  label: 'Open Remotely',
                  caption: 'Through Tailscale · ${_c.config.tailscaleIp}',
                  onPressed: busy ? null : () async => _show(await _c.openRemotely()),
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: busy
                      ? _ProgressCard(
                          message: _c.progress ?? 'Working…',
                          onCancel: _c.cancel,
                        )
                      : const SizedBox.shrink(),
                ),
                if (_c.status == ServerStatus.online && !busy) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(color: Theme.of(context).colorScheme.error),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _confirmShutdown,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Shut down server'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(84),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                Text(caption,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.message, required this.onCancel});

  final String message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _ShutdownRequest {
  const _ShutdownRequest(this.password, this.remember);

  final String password;
  final bool remember;
}

class _ShutdownDialog extends StatefulWidget {
  const _ShutdownDialog({
    required this.username,
    required this.host,
    required this.routeLabel,
    required this.savedPassword,
  });

  final String username;
  final String host;
  final String routeLabel;
  final String? savedPassword;

  @override
  State<_ShutdownDialog> createState() => _ShutdownDialogState();
}

class _ShutdownDialogState extends State<_ShutdownDialog> {
  late final _password = TextEditingController(text: widget.savedPassword ?? '');
  late bool _remember = widget.savedPassword != null;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.of(context).pop(_ShutdownRequest(_password.text, _remember));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.power_settings_new),
      title: const Text('Shut down the server?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This logs in as ${widget.username}@${widget.host} '
                '(${widget.routeLabel}) and runs "sudo shutdown now". Immich '
                'will be unavailable until the server is woken again.'),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofocus: widget.savedPassword == null,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password for ${widget.username}',
                helperText: 'Used for SSH login and sudo',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              title: const Text('Remember password on this device'),
              subtitle: const Text('Stored encrypted in the Android Keystore'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _password.text.isEmpty ? null : _submit,
          child: const Text('Shut down'),
        ),
      ],
    );
  }
}
