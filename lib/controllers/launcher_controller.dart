import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../models/app_exception.dart';
import '../models/server_config.dart';
import '../services/config_store.dart';
import '../services/immich_opener.dart';
import '../services/network_probe.dart';
import '../services/relay_client.dart';
import '../services/ssh_service.dart';
import '../services/tailscale_service.dart';
import '../services/wake_on_lan.dart';

enum ServerStatus { unknown, checking, online, offline }

/// Result of a user-triggered action, shown as a snackbar by the UI.
class ActionOutcome {
  const ActionOutcome.success([this.message]) : isError = false;
  const ActionOutcome.error(String this.message) : isError = true;
  const ActionOutcome.cancelled()
      : message = 'Cancelled.',
        isError = false;

  final String? message;
  final bool isError;
}

/// Holds the app state and implements the "open locally", "open remotely",
/// status polling and shutdown flows.
class LauncherController extends ChangeNotifier {
  LauncherController({
    required ServerConfig config,
    required this.store,
    this.probe = const NetworkProbe(),
    this.wol = const WakeOnLan(),
    this.tailscale = const TailscaleService(),
    this.immich = const ImmichOpener(),
    RelayClient? relay,
    SshService? ssh,
  })  : _config = config,
        relay = relay ?? RelayClient(),
        ssh = ssh ?? SshService(),
        _lastRoute = store.lastRoute;

  final ConfigStore store;
  final NetworkProbe probe;
  final WakeOnLan wol;
  final TailscaleService tailscale;
  final ImmichOpener immich;
  final RelayClient relay;
  final SshService ssh;

  ServerConfig _config;
  ServerConfig get config => _config;

  ServerStatus _status = ServerStatus.unknown;
  ServerStatus get status => _status;

  /// Route through which the last status check reached the server.
  ConnectionRoute? _onlineVia;
  ConnectionRoute? get onlineVia => _onlineVia;

  DateTime? _lastChecked;
  DateTime? get lastChecked => _lastChecked;

  /// Route of the last "Open …" action (persisted).
  ConnectionRoute? _lastRoute;
  ConnectionRoute? get lastRoute => _lastRoute;

  bool _busy = false;
  bool get busy => _busy;

  String? _progress;
  String? get progress => _progress;

  Timer? _pollTimer;
  bool _statusCheckRunning = false;
  Completer<void>? _cancelSignal;
  bool _disposed = false;

  /// Route to use for SSH shutdown: the last one used to open Immich, falling
  /// back to the one the status check found working.
  ConnectionRoute? get shutdownRoute => _lastRoute ?? _onlineVia;

  // ---------------------------------------------------------------------------
  // Status polling
  // ---------------------------------------------------------------------------

  void startPolling() {
    _pollTimer?.cancel();
    unawaited(refreshStatus());
    _pollTimer = Timer.periodic(
      AppConstants.statusPollInterval,
      (_) => unawaited(refreshStatus()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  List<int> get _probePorts => [_config.immichPort, _config.sshPort];

  Future<void> refreshStatus() async {
    if (_statusCheckRunning || _disposed) return;
    _statusCheckRunning = true;
    if (_status == ServerStatus.unknown) {
      _status = ServerStatus.checking;
      _notify();
    }
    try {
      ConnectionRoute? via;
      // Check the route used last first, then the other one.
      final order = _lastRoute == ConnectionRoute.remote
          ? [ConnectionRoute.remote, ConnectionRoute.local]
          : [ConnectionRoute.local, ConnectionRoute.remote];
      for (final route in order) {
        if (await probe.isHostOnline(_config.hostFor(route), _probePorts)) {
          via = route;
          break;
        }
      }
      _onlineVia = via;
      _status = via == null ? ServerStatus.offline : ServerStatus.online;
      _lastChecked = DateTime.now();
    } catch (_) {
      _status = ServerStatus.offline;
      _onlineVia = null;
    } finally {
      _statusCheckRunning = false;
      _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // Open flows
  // ---------------------------------------------------------------------------

  Future<ActionOutcome> openLocally() => _runFlow(() async {
        final host = _config.localIp;
        Future<void> sendWake() async {
          _setProgress('Sending Wake-on-LAN packet…');
          await wol.wake(mac: _config.macAddress, serverIp: host);
        }

        await _ensureImmichReachable(
          route: ConnectionRoute.local,
          wake: sendWake,
          offlineHint: 'Make sure you are connected to your home Wi-Fi and that '
              'Wake-on-LAN is enabled in the server BIOS and network card.',
        );
        return _openImmich(ConnectionRoute.local);
      });

  Future<ActionOutcome> openRemotely() => _runFlow(() async {
        await _ensureTailscaleConnected();
        Future<void> sendWake() async {
          _setProgress('Asking the relay device to wake the server…');
          await relay.wake(host: _config.relayIp, port: _config.relayPort);
        }

        await _ensureImmichReachable(
          route: ConnectionRoute.remote,
          wake: sendWake,
          offlineHint: 'Check that the relay device can wake the server and '
              'that Tailscale starts automatically on the server at boot.',
        );
        return _openImmich(ConnectionRoute.remote);
      });

  /// Makes sure Tailscale is up, connecting it in the background if needed.
  /// Only opens the Tailscale app if the background connect doesn't work
  /// (e.g. logged out, or VPN permission never granted).
  Future<void> _ensureTailscaleConnected() async {
    _setProgress('Checking Tailscale connection…');
    if (await tailscale.isConnected()) return;

    if (!await tailscale.isInstalled()) {
      throw const AppException(
          'Tailscale is not installed on this phone. Install it from the Play '
          'Store and log in to your tailnet.');
    }

    _setProgress('Connecting Tailscale…');
    // 1. Fully in the background: works while Tailscale's process is alive.
    if (!await tailscale.isStopped() &&
        await tailscale.requestConnect() &&
        await _waitForTailscale(AppConstants.tailscaleBackgroundConnectTimeout)) {
      await _waitForTailnet();
      return;
    }
    // 2. Tailscale is stopped or its process can't be started from the
    //    background: open it for a moment, then come back.
    if (await tailscale.requestConnectViaApp() &&
        await _waitForTailscale(AppConstants.tailscaleAutoConnectTimeout)) {
      await _waitForTailnet();
      return;
    }

    _setProgress('Tailscale could not connect by itself. Turn it on in the '
        'Tailscale app, then come back here…');
    await tailscale.openApp();
    if (await _waitForTailscale(AppConstants.tailscaleWaitTimeout)) {
      await _waitForTailnet();
      return;
    }
    throw const AppException(
        'Tailscale did not connect in time. Turn it on in the Tailscale app and '
        'try again.');
  }

  Future<bool> _waitForTailscale(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await _sleep(AppConstants.tailscalePollInterval);
      if (await tailscale.isConnected()) return true;
    }
    return false;
  }

  /// Right after Tailscale connects, peers can take a few seconds to become
  /// reachable. Wait until the server or the relay answers so a slow tunnel
  /// isn't mistaken for a server that is off (or an unreachable relay).
  Future<void> _waitForTailnet() async {
    _setProgress('Tailscale connected, reaching your home network…');
    final deadline = DateTime.now().add(AppConstants.tailscaleWarmupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final results = await Future.wait([
        probe.isHostOnline(_config.tailscaleIp, _probePorts),
        probe.isHostOnline(_config.relayIp, [_config.relayPort]),
      ]);
      if (results.any((ok) => ok)) return;
      await _sleep(AppConstants.tailscalePollInterval);
    }
    // Carry on anyway: the wake step reports a precise error if needed.
  }

  /// Makes sure Immich answers on [route], waking the server if necessary.
  Future<void> _ensureImmichReachable({
    required ConnectionRoute route,
    required Future<void> Function() wake,
    required String offlineHint,
  }) async {
    final host = _config.hostFor(route);
    final port = _config.immichPort;

    _setProgress('Checking if the server is online…');
    if (await probe.isPortOpen(host, port)) return;

    var hostUp = await probe.isHostOnline(host, [_config.sshPort]);
    DateTime? lastWake;
    if (!hostUp) {
      await wake();
      lastWake = DateTime.now();
      _setProgress('Waiting for the server to boot…');
    } else {
      _setProgress('Server is on, waiting for Immich to start…');
    }

    final deadline = DateTime.now().add(AppConstants.bootTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await _sleep(AppConstants.bootPollInterval);
      if (await probe.isPortOpen(host, port)) return;

      if (!hostUp && await probe.isHostOnline(host, [_config.sshPort])) {
        hostUp = true;
        _setProgress('Server is up, waiting for Immich to start…');
      }
      if (!hostUp &&
          lastWake != null &&
          DateTime.now().difference(lastWake) >= AppConstants.wakeResendInterval) {
        try {
          await wake();
        } on AppException {
          // Keep waiting; the first wake request may still work.
        }
        lastWake = DateTime.now();
        _setProgress('Waiting for the server to boot…');
      }
    }

    final minutes = AppConstants.bootTimeout.inMinutes;
    if (hostUp) {
      throw AppException(
          'The server is on, but Immich did not answer on port $port within '
          '$minutes minutes. Check that the Immich containers are running and '
          'that the Immich port in Settings is correct.');
    }
    throw AppException(
        'The server did not come online within $minutes minutes. $offlineHint');
  }

  Future<String?> _openImmich(ConnectionRoute route) async {
    _lastRoute = route;
    await store.setLastRoute(route);
    _status = ServerStatus.online;
    _onlineVia = route;
    _lastChecked = DateTime.now();
    _setProgress('Opening Immich…');
    return immich.open(_config.immichUrlFor(route));
  }

  // ---------------------------------------------------------------------------
  // Shutdown
  // ---------------------------------------------------------------------------

  Future<ActionOutcome> shutdown({
    required String password,
    required bool rememberPassword,
  }) {
    return _runFlow(() async {
      final route = shutdownRoute;
      if (route == null) {
        throw const AppException('The server does not seem to be online.');
      }
      final host = _config.hostFor(route);
      _setProgress('Shutting down the server via ${route.label} ($host)…');
      await ssh.shutdown(
        host: host,
        port: _config.sshPort,
        username: _config.sshUsername,
        password: password,
      );
      if (rememberPassword) {
        await ssh.savePassword(password);
      } else {
        await ssh.forgetPassword();
      }
      _status = ServerStatus.offline;
      _onlineVia = null;
      _lastChecked = DateTime.now();
      return 'Shutdown command sent. The server is turning off.';
    });
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<void> updateConfig(ServerConfig config) async {
    await store.save(config);
    _config = config;
    _status = ServerStatus.unknown;
    _onlineVia = null;
    _notify();
    unawaited(refreshStatus());
  }

  // ---------------------------------------------------------------------------
  // Flow plumbing
  // ---------------------------------------------------------------------------

  void cancel() {
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<ActionOutcome> _runFlow(Future<String?> Function() body) async {
    if (_busy) {
      return const ActionOutcome.error('Another action is already running.');
    }
    _busy = true;
    _cancelSignal = Completer<void>();
    _notify();
    try {
      final message = await body();
      _checkCancelled();
      return ActionOutcome.success(message);
    } on FlowCancelledException {
      return const ActionOutcome.cancelled();
    } on AppException catch (e) {
      return ActionOutcome.error(e.message);
    } catch (e) {
      return ActionOutcome.error('Something went wrong: $e');
    } finally {
      _busy = false;
      _progress = null;
      _cancelSignal = null;
      _notify();
    }
  }

  void _checkCancelled() {
    if (_cancelSignal?.isCompleted ?? false) {
      throw const FlowCancelledException();
    }
  }

  void _setProgress(String message) {
    _checkCancelled();
    _progress = message;
    _notify();
  }

  /// Sleeps for [duration], returning early (with an exception) on cancel.
  Future<void> _sleep(Duration duration) async {
    final signal = _cancelSignal;
    await Future.any<void>([
      Future<void>.delayed(duration),
      if (signal != null) signal.future,
    ]);
    _checkCancelled();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    cancel();
    relay.close();
    super.dispose();
  }
}
