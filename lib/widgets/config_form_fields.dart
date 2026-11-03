import 'package:flutter/material.dart';

import '../models/server_config.dart';

/// Owns one [TextEditingController] per [ConfigField].
class ConfigControllers {
  ConfigControllers([ServerConfig? initial]) {
    final values = initial?.toValues();
    for (final spec in configFieldSpecs.values) {
      _controllers[spec.field] = TextEditingController(
        text: values?[spec.field] ?? spec.defaultValue ?? '',
      );
    }
  }

  final _controllers = <ConfigField, TextEditingController>{};

  TextEditingController operator [](ConfigField f) => _controllers[f]!;

  ServerConfig? toConfig() => ServerConfig.tryFromValues({
        for (final e in _controllers.entries) e.key: e.value.text,
      });

  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }
}

/// A labelled text field with hint, explanation and validation for one
/// configuration value.
class ConfigFormField extends StatelessWidget {
  const ConfigFormField({
    super.key,
    required this.spec,
    required this.controller,
    this.textInputAction = TextInputAction.next,
  });

  final ConfigFieldSpec spec;
  final TextEditingController controller;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: controller,
            keyboardType: spec.keyboardType,
            textInputAction: textInputAction,
            autocorrect: false,
            enableSuggestions: false,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: spec.validator,
            decoration: InputDecoration(
              labelText: spec.label,
              hintText: spec.hint,
              hintMaxLines: 2,
              prefixIcon: Icon(spec.icon),
              border: const OutlineInputBorder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              spec.help,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A column of [ConfigFormField]s for [fields].
class ConfigFieldGroup extends StatelessWidget {
  const ConfigFieldGroup({
    super.key,
    required this.fields,
    required this.controllers,
  });

  final List<ConfigField> fields;
  final ConfigControllers controllers;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < fields.length; i++)
          ConfigFormField(
            spec: configFieldSpecs[fields[i]]!,
            controller: controllers[fields[i]],
            textInputAction: i == fields.length - 1
                ? TextInputAction.done
                : TextInputAction.next,
          ),
      ],
    );
  }
}
