import 'package:flutter/services.dart';

/// Thin wrapper around the native Android code in `MainActivity.kt`.
class PlatformBridge {
  const PlatformBridge();

  static const _channel = MethodChannel('immich_launcher/platform');

  Future<bool> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Whether any VPN network is currently active on the device.
  Future<bool> isVpnActive() => _call('isVpnActive');

  Future<bool> isAppInstalled(String package) =>
      _call('isAppInstalled', {'package': package});

  /// Opens the app's launcher activity. Returns false if it isn't installed.
  Future<bool> launchApp(String package) =>
      _call('launchApp', {'package': package});

  /// Sends an ACTION_VIEW intent for [url] restricted to [package]. Returns
  /// false if the app is missing or doesn't handle such links.
  Future<bool> openUrlWithApp(String package, String url) =>
      _call('openUrlWithApp', {'package': package, 'url': url});

  /// Sends an explicit broadcast [action] to [receiver] in [package]. Returns
  /// false if that receiver doesn't exist.
  Future<bool> sendBroadcast({
    required String package,
    required String receiver,
    required String action,
  }) =>
      _call('sendBroadcast',
          {'package': package, 'receiver': receiver, 'action': action});

  /// Opens [url] in whatever app handles it (usually the browser).
  Future<bool> openUrl(String url) => _call('openUrl', {'url': url});
}
