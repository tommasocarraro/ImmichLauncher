import 'dart:async';
import 'dart:io';

import '../constants.dart';

enum PortState {
  /// A TCP connection was established: something is listening.
  open,

  /// The host actively refused the connection: it is up, but nothing listens.
  refused,

  /// No answer at all (host down, wrong address, or filtered).
  unreachable,
}

/// Reachability checks.
///
/// Android apps cannot send raw ICMP packets, so "ping" is implemented as a
/// combination of TCP connects (which also detect a live host when the port
/// is closed, thanks to the TCP reset) and the system `ping` binary as a
/// fallback.
class NetworkProbe {
  const NetworkProbe({this.timeout = AppConstants.probeTimeout});

  final Duration timeout;

  // ECONNREFUSED on Linux/Android.
  static const _econnrefused = 111;

  Future<PortState> probePort(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return PortState.open;
    } on SocketException catch (e) {
      final refused = e.osError?.errorCode == _econnrefused ||
          (e.osError?.message.toLowerCase().contains('refused') ?? false);
      return refused ? PortState.refused : PortState.unreachable;
    } catch (_) {
      return PortState.unreachable;
    } finally {
      socket?.destroy();
    }
  }

  Future<bool> isPortOpen(String host, int port) async =>
      await probePort(host, port) == PortState.open;

  /// ICMP echo through the system `ping` binary. Returns false if the binary
  /// is unavailable or the host does not answer.
  Future<bool> ping(String host) async {
    final seconds = timeout.inSeconds < 1 ? 1 : timeout.inSeconds;
    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '$seconds', host],
      ).timeout(timeout + const Duration(seconds: 2));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// True if the host appears to be up: any of [ports] answers (open or
  /// refused) or it replies to ping. Checks run in parallel and the result is
  /// returned as soon as one of them succeeds.
  Future<bool> isHostOnline(String host, Iterable<int> ports) {
    final checks = <Future<bool>>[
      for (final p in ports.toSet())
        probePort(host, p).then((s) => s != PortState.unreachable),
      ping(host),
    ];
    final completer = Completer<bool>();
    var pending = checks.length;
    for (final check in checks) {
      check.then((ok) {
        pending--;
        if (completer.isCompleted) return;
        if (ok) {
          completer.complete(true);
        } else if (pending == 0) {
          completer.complete(false);
        }
      });
    }
    return completer.future;
  }
}
