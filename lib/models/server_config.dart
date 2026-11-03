import 'package:flutter/material.dart';

import '../constants.dart';
import 'validators.dart';

/// Every user-configurable setting.
enum ConfigField {
  localIp,
  macAddress,
  tailscaleIp,
  relayIp,
  relayPort,
  sshUsername,
  sshPort,
  immichPort,
}

/// How the app reached (or will reach) the server.
enum ConnectionRoute {
  local,
  remote;

  String get label => this == local ? 'local network' : 'Tailscale';
}

/// Describes how a [ConfigField] is presented and validated in the UI.
class ConfigFieldSpec {
  const ConfigFieldSpec({
    required this.field,
    required this.label,
    required this.hint,
    required this.help,
    required this.icon,
    required this.validator,
    this.keyboardType = TextInputType.text,
    this.defaultValue,
  });

  final ConfigField field;
  final String label;
  final String hint;
  final String help;
  final IconData icon;
  final String? Function(String?) validator;
  final TextInputType keyboardType;
  final String? defaultValue;
}

const _ipKeyboard = TextInputType.numberWithOptions(decimal: true);

/// The single source of truth for the configuration form, shared by the
/// setup wizard and the settings screen.
final Map<ConfigField, ConfigFieldSpec> configFieldSpecs = {
  ConfigField.localIp: const ConfigFieldSpec(
    field: ConfigField.localIp,
    label: 'Server local IP',
    hint: 'e.g. 192.168.1.10',
    help: 'The address of your Immich server on your home network. Find it '
        'with "ip -4 addr" on the server or in your router\'s device list. '
        'Give the server a fixed IP (DHCP reservation) so it never changes.',
    icon: Icons.lan_outlined,
    validator: Validators.ipv4,
    keyboardType: _ipKeyboard,
  ),
  ConfigField.macAddress: const ConfigFieldSpec(
    field: ConfigField.macAddress,
    label: 'Server MAC address',
    hint: 'e.g. 68:1D:EF:4A:6B:DA — find it with ip link show on your server',
    help: 'The hardware address of the server\'s wired network card, used to '
        'wake it with Wake-on-LAN. In the output of "ip link show" it is the '
        'value after "link/ether" for your ethernet interface.',
    icon: Icons.memory_outlined,
    validator: Validators.mac,
    keyboardType: TextInputType.visiblePassword, // no autocorrect/suggestions
  ),
  ConfigField.tailscaleIp: const ConfigFieldSpec(
    field: ConfigField.tailscaleIp,
    label: 'Server Tailscale IP',
    hint: 'find it with tailscale ip -4 on your server',
    help: 'The server\'s address inside your Tailscale network (usually '
        'starts with 100.). Used to reach the server when you are away from '
        'home.',
    icon: Icons.vpn_lock_outlined,
    validator: Validators.host,
    keyboardType: TextInputType.url,
  ),
  ConfigField.relayIp: const ConfigFieldSpec(
    field: ConfigField.relayIp,
    label: 'Relay device Tailscale IP',
    hint: 'the Tailscale IP of your always-on relay device',
    help: 'An always-on device on the same home network as the server (e.g. '
        'a Raspberry Pi) running the relay script. When you are away it '
        'sends the Wake-on-LAN packet on your behalf. Find its address with '
        '"tailscale ip -4" on that device.',
    icon: Icons.router_outlined,
    validator: Validators.host,
    keyboardType: TextInputType.url,
  ),
  ConfigField.relayPort: ConfigFieldSpec(
    field: ConfigField.relayPort,
    label: 'Relay port',
    hint: 'default: ${AppConstants.defaultRelayPort}',
    help: 'The port the relay script listens on. Leave the default unless '
        'you changed it when starting the relay.',
    icon: Icons.settings_ethernet,
    validator: Validators.port,
    keyboardType: TextInputType.number,
    defaultValue: '${AppConstants.defaultRelayPort}',
  ),
  ConfigField.sshUsername: const ConfigFieldSpec(
    field: ConfigField.sshUsername,
    label: 'SSH username',
    hint: 'your Ubuntu username',
    help: 'The account used to log into the server over SSH to shut it '
        'down. It must be allowed to use sudo. Run "whoami" on the server if '
        'unsure.',
    icon: Icons.person_outline,
    validator: Validators.username,
    keyboardType: TextInputType.visiblePassword,
  ),
  ConfigField.sshPort: ConfigFieldSpec(
    field: ConfigField.sshPort,
    label: 'SSH port',
    hint: 'default: ${AppConstants.defaultSshPort}',
    help: 'The port of the SSH server on your server. Leave the default '
        'unless you changed it in /etc/ssh/sshd_config.',
    icon: Icons.terminal,
    validator: Validators.port,
    keyboardType: TextInputType.number,
    defaultValue: '${AppConstants.defaultSshPort}',
  ),
  ConfigField.immichPort: ConfigFieldSpec(
    field: ConfigField.immichPort,
    label: 'Immich port',
    hint: 'default: ${AppConstants.defaultImmichPort}',
    help: 'The port Immich is published on (the left side of the "ports:" '
        'mapping of immich-server in docker-compose.yml).',
    icon: Icons.photo_library_outlined,
    validator: Validators.port,
    keyboardType: TextInputType.number,
    defaultValue: '${AppConstants.defaultImmichPort}',
  ),
};

/// The user's saved configuration.
@immutable
class ServerConfig {
  const ServerConfig({
    required this.localIp,
    required this.macAddress,
    required this.tailscaleIp,
    required this.relayIp,
    required this.relayPort,
    required this.sshUsername,
    required this.sshPort,
    required this.immichPort,
  });

  final String localIp;
  final String macAddress;
  final String tailscaleIp;
  final String relayIp;
  final int relayPort;
  final String sshUsername;
  final int sshPort;
  final int immichPort;

  String hostFor(ConnectionRoute route) =>
      route == ConnectionRoute.local ? localIp : tailscaleIp;

  String immichUrlFor(ConnectionRoute route) =>
      Uri(scheme: 'http', host: hostFor(route), port: immichPort).toString();

  /// Builds a config from raw string values. Returns `null` if any value is
  /// missing or invalid.
  static ServerConfig? tryFromValues(Map<ConfigField, String?> values) {
    for (final spec in configFieldSpecs.values) {
      if (spec.validator(values[spec.field]) != null) return null;
    }
    String s(ConfigField f) => values[f]!.trim();
    int i(ConfigField f) => int.parse(s(f));
    return ServerConfig(
      localIp: s(ConfigField.localIp),
      macAddress: s(ConfigField.macAddress).toUpperCase(),
      tailscaleIp: s(ConfigField.tailscaleIp),
      relayIp: s(ConfigField.relayIp),
      relayPort: i(ConfigField.relayPort),
      sshUsername: s(ConfigField.sshUsername),
      sshPort: i(ConfigField.sshPort),
      immichPort: i(ConfigField.immichPort),
    );
  }

  Map<ConfigField, String> toValues() => {
        ConfigField.localIp: localIp,
        ConfigField.macAddress: macAddress,
        ConfigField.tailscaleIp: tailscaleIp,
        ConfigField.relayIp: relayIp,
        ConfigField.relayPort: '$relayPort',
        ConfigField.sshUsername: sshUsername,
        ConfigField.sshPort: '$sshPort',
        ConfigField.immichPort: '$immichPort',
      };
}
