import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';

/// Persists the [ServerConfig] (and a little app state) with shared_preferences.
class ConfigStore {
  ConfigStore._(this._prefs);

  static Future<ConfigStore> create() async =>
      ConfigStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static String _key(ConfigField f) => 'config.${f.name}';
  static const _lastRouteKey = 'state.lastRoute';

  /// Returns the saved config, or `null` if setup was never completed (or the
  /// stored values are incomplete/invalid).
  ServerConfig? load() => ServerConfig.tryFromValues({
        for (final f in ConfigField.values) f: _prefs.getString(_key(f)),
      });

  Future<void> save(ServerConfig config) async {
    for (final entry in config.toValues().entries) {
      await _prefs.setString(_key(entry.key), entry.value);
    }
  }

  ConnectionRoute? get lastRoute {
    final name = _prefs.getString(_lastRouteKey);
    for (final r in ConnectionRoute.values) {
      if (r.name == name) return r;
    }
    return null;
  }

  Future<void> setLastRoute(ConnectionRoute route) =>
      _prefs.setString(_lastRouteKey, route.name);
}
