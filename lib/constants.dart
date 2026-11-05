/// Central place for every tunable value used by the app.
///
/// User-specific values (IPs, MAC, ports, username) are never hardcoded:
/// they come from the setup wizard / settings screen. This file only holds
/// defaults offered to the user, protocol constants and timing parameters.
class AppConstants {
  AppConstants._();

  static const appName = 'ImmichLauncher';

  // ---- Defaults suggested in the setup wizard -----------------------------
  static const defaultRelayPort = 8765;
  static const defaultImmichPort = 2283;
  static const defaultSshPort = 22;

  // ---- Wake-on-LAN protocol ------------------------------------------------
  static const wolPort = 9;
  static const wolLimitedBroadcast = '255.255.255.255';

  // ---- Relay HTTP API ------------------------------------------------------
  static const relayWakePath = '/wake';

  // ---- Android packages of the apps we hand off to ------------------------
  static const immichPackage = 'app.alextran.immich';
  static const tailscalePackage = 'com.tailscale.ipn';

  /// Tailscale's exported receiver that connects/disconnects the VPN without
  /// opening the app (the same one Tasker/automation apps use).
  static const tailscaleReceiver = 'com.tailscale.ipn.IPNReceiver';
  static const tailscaleConnectAction = 'com.tailscale.ipn.CONNECT_VPN';

  // ---- Timing --------------------------------------------------------------
  /// How often the status indicator re-checks the server.
  static const statusPollInterval = Duration(seconds: 30);

  /// Timeout of a single reachability probe (TCP connect / ICMP ping).
  static const probeTimeout = Duration(seconds: 2);

  /// Delay between reachability checks while waiting for the server to boot.
  static const bootPollInterval = Duration(seconds: 5);

  /// Give up waiting for the server (and Immich) after this long.
  static const bootTimeout = Duration(minutes: 5);

  /// While the server is still unreachable, re-send the wake request this often
  /// (a single UDP packet can be lost).
  static const wakeResendInterval = Duration(seconds: 30);

  /// When Tailscale was stopped by the system, how long to let its process
  /// start after opening it before sending the connect request.
  static const tailscaleStartupDelay = Duration(milliseconds: 1500);

  /// How long to wait for the purely background connect request to work
  /// before opening Tailscale briefly instead.
  static const tailscaleBackgroundConnectTimeout = Duration(seconds: 4);

  /// How long to wait for Tailscale to connect after asking it to in the
  /// background, before falling back to opening the Tailscale app.
  static const tailscaleAutoConnectTimeout = Duration(seconds: 15);

  /// After Tailscale connects, how long to wait for the tailnet (server or
  /// relay) to become reachable before deciding the server is off.
  static const tailscaleWarmupTimeout = Duration(seconds: 15);

  /// How long to wait for the user to connect Tailscale.
  static const tailscaleWaitTimeout = Duration(minutes: 2);
  static const tailscalePollInterval = Duration(seconds: 2);

  static const relayRequestTimeout = Duration(seconds: 10);

  static const sshConnectTimeout = Duration(seconds: 10);
  static const sshCommandTimeout = Duration(seconds: 15);
}
