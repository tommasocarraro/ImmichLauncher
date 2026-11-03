/// Input validators used by the setup wizard and the settings screen.
///
/// Each validator returns `null` when the value is valid, or a user-friendly
/// error message otherwise (the [FormField.validator] contract).
class Validators {
  Validators._();

  static final _ipv4 = RegExp(
    r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
  );

  static final _hostname = RegExp(
    r'^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.?$',
  );

  static final _mac = RegExp(
    r'^([0-9A-Fa-f]{2}([:-]))([0-9A-Fa-f]{2}\2){4}[0-9A-Fa-f]{2}$|^[0-9A-Fa-f]{12}$',
  );

  static final _username = RegExp(r'^[A-Za-z0-9._][A-Za-z0-9._-]*\$?$');

  static bool isIPv4(String value) => _ipv4.hasMatch(value.trim());

  /// Accepts an IPv4 address or a hostname (e.g. a Tailscale MagicDNS name).
  static String? host(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'This field is required';
    if (isIPv4(v)) return null;
    // Looks like an IP but isn't a valid one (e.g. 192.168.1.300).
    if (RegExp(r'^[\d.]+$').hasMatch(v)) {
      return 'Not a valid IPv4 address (four numbers 0–255 separated by dots)';
    }
    if (_hostname.hasMatch(v)) return null;
    return 'Enter an IPv4 address like 192.168.1.10 or a hostname';
  }

  /// The local server address must be an IPv4 address: it is also used to
  /// derive the subnet broadcast address for Wake-on-LAN.
  static String? ipv4(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'This field is required';
    if (!isIPv4(v)) {
      return 'Enter an IPv4 address like 192.168.1.10';
    }
    return null;
  }

  static String? mac(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'This field is required';
    if (!_mac.hasMatch(v)) {
      return 'Enter 6 pairs of hex digits, e.g. 68:1D:EF:4A:6B:DA';
    }
    return null;
  }

  static String? port(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'This field is required';
    final p = int.tryParse(v);
    if (p == null || p < 1 || p > 65535) {
      return 'Enter a port number between 1 and 65535';
    }
    return null;
  }

  static String? username(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'This field is required';
    if (!_username.hasMatch(v)) {
      return 'Usernames cannot contain spaces or special characters';
    }
    return null;
  }
}
