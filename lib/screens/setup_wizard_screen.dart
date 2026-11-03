import 'package:flutter/material.dart';

import '../models/server_config.dart';
import '../services/config_store.dart';
import '../widgets/config_form_fields.dart';

class _WizardStep {
  const _WizardStep(this.title, this.description, this.fields);

  final String title;
  final String description;
  final List<ConfigField> fields;
}

const _steps = [
  _WizardStep(
    'Home network',
    'Used by "Open Locally" to wake the server with Wake-on-LAN while you are '
        'on your home Wi-Fi.',
    [ConfigField.localIp, ConfigField.macAddress],
  ),
  _WizardStep(
    'Tailscale',
    'Used by "Open Remotely": the app connects through Tailscale and asks your '
        'always-on relay device to wake the server.',
    [ConfigField.tailscaleIp, ConfigField.relayIp, ConfigField.relayPort],
  ),
  _WizardStep(
    'Server access',
    'How to reach Immich, and how to log in over SSH to shut the server down.',
    [ConfigField.sshUsername, ConfigField.sshPort, ConfigField.immichPort],
  ),
];

/// First-run wizard collecting the configuration, step by step.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({
    super.key,
    required this.store,
    required this.onComplete,
  });

  final ConfigStore store;
  final ValueChanged<ServerConfig> onComplete;

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final _controllers = ConfigControllers();
  final _formKeys = List.generate(_steps.length, (_) => GlobalKey<FormState>());
  int _current = 0;
  bool _saving = false;

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  bool get _isLast => _current == _steps.length - 1;

  Future<void> _next() async {
    final form = _formKeys[_current].currentState;
    if (form == null || !form.validate()) return;
    if (!_isLast) {
      setState(() => _current++);
      return;
    }
    final config = _controllers.toConfig();
    if (config == null) {
      // A previous step became invalid somehow: jump back to it.
      final bad = _steps.indexWhere((s) => s.fields.any((f) =>
          configFieldSpecs[f]!.validator(_controllers[f].text) != null));
      setState(() => _current = bad < 0 ? 0 : bad);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.store.save(config);
      widget.onComplete(config);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the configuration: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up ImmichLauncher')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Tell ImmichLauncher how to find and wake your server. You can '
                'change everything later from Settings.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: Stepper(
                currentStep: _current,
                onStepContinue: _saving ? null : _next,
                onStepCancel: _current == 0 || _saving
                    ? null
                    : () => setState(() => _current--),
                onStepTapped: (i) {
                  // Only allow going back, so every step gets validated.
                  if (i < _current) setState(() => _current = i);
                },
                controlsBuilder: (context, details) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      FilledButton(
                        onPressed: details.onStepContinue,
                        child: _saving && _isLast
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isLast ? 'Finish' : 'Next'),
                      ),
                      const SizedBox(width: 12),
                      if (details.onStepCancel != null)
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: const Text('Back'),
                        ),
                    ],
                  ),
                ),
                steps: [
                  for (var i = 0; i < _steps.length; i++)
                    Step(
                      title: Text(_steps[i].title),
                      subtitle: i == _current ? null : Text(_steps[i].description,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      isActive: i <= _current,
                      state: i < _current ? StepState.complete : StepState.indexed,
                      content: Form(
                        key: _formKeys[i],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(_steps[i].description),
                            ),
                            ConfigFieldGroup(
                              fields: _steps[i].fields,
                              controllers: _controllers,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
