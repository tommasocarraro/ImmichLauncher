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

  /// Asks Tailscale to connect without showing its UI. Returns false if the
  /// installed Tailscale version doesn't support it. Connecting only works if
  /// Tailscale is logged in and has been granted the VPN permission once.
  Future<bool> requestConnect() => bridge.sendBroadcast(
        package: AppConstants.tailscalePackage,
        receiver: AppConstants.tailscaleReceiver,
        action: AppConstants.tailscaleConnectAction,
      );

  Future<bool> openApp() => bridge.launchApp(AppConstants.tailscalePackage);
}
