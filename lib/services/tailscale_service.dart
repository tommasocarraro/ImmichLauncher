import 'dart:io';

import '../constants.dart';
import 'platform_bridge.dart';

/// Detects whether Tailscale is connected on the phone and opens the app.
class TailscaleService {
  const TailscaleService({this.bridge = const PlatformBridge()});

  final PlatformBridge bridge;

  /// Tailscale assigns addresses from the CGNAT range 100.64.0.0/10.
  static bool isTailscaleAddress(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final b = address.rawAddress;
    return b[0] == 100 && b[1] >= 64 && b[1] <= 127;
  }

  Future<bool> _hasTailscaleInterface() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces.any((i) => i.addresses.any(isTailscaleAddress));
    } catch (_) {
      return false;
    }
  }

  /// True if the phone has a Tailscale address, or (if interfaces can't be
  /// inspected) Android reports an active VPN.
  Future<bool> isConnected() async =>
      await _hasTailscaleInterface() || await bridge.isVpnActive();

  Future<bool> isInstalled() =>
      bridge.isAppInstalled(AppConstants.tailscalePackage);

  /// Asks Tailscale to connect in the background, without showing its UI.
  /// Returns false if the installed Tailscale version doesn't support it.
  /// Connecting only works if Tailscale is logged in and has been granted the
  /// VPN permission once.
  ///
  /// Android drops this request if Tailscale is in the "stopped" state, and
  /// some OEM battery managers (vivo, Xiaomi, …) also refuse to start its
  /// process for it when it isn't running. [requestConnectViaApp] covers that.
  Future<bool> requestConnect() => bridge.sendBroadcast(
        package: AppConstants.tailscalePackage,
        receiver: AppConstants.tailscaleReceiver,
        action: AppConstants.tailscaleConnectAction,
      );

  /// Opens Tailscale for a moment so its process starts, asks it to connect,
  /// then closes it again, returning to ImmichLauncher.
  Future<bool> requestConnectViaApp() async {
    if (!await bridge.launchAppBriefly(AppConstants.tailscalePackage)) {
      return false;
    }
    await Future<void>.delayed(AppConstants.tailscaleStartupDelay);
    final sent = await requestConnect();
    await bridge.closeBriefApp();
    return sent;
  }

  /// Whether Android has put Tailscale in the "stopped" state, where it
  /// can't receive the background connect request at all.
  Future<bool> isStopped() =>
      bridge.isAppStopped(AppConstants.tailscalePackage);

  Future<bool> openApp() => bridge.launchApp(AppConstants.tailscalePackage);
}
