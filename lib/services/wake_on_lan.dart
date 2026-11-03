import 'dart:io';
import 'dart:typed_data';

import '../constants.dart';
import '../models/app_exception.dart';
import '../models/validators.dart';

/// Sends Wake-on-LAN magic packets over UDP broadcast.
class WakeOnLan {
  const WakeOnLan();

  /// Parses a MAC address in `AA:BB:CC:DD:EE:FF`, `AA-BB-...` or
  /// `AABBCCDDEEFF` form into its 6 bytes.
  static Uint8List parseMac(String mac) {
    final hex = mac.trim().replaceAll(RegExp(r'[:\-.]'), '');
    if (!RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(hex)) {
      throw AppException('"$mac" is not a valid MAC address.');
    }
    return Uint8List.fromList([
      for (var i = 0; i < 12; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  /// 6 bytes of 0xFF followed by the MAC address repeated 16 times (102 bytes).
  static Uint8List buildMagicPacket(String mac) {
    final macBytes = parseMac(mac);
    final packet = Uint8List(6 + 16 * 6)..fillRange(0, 6, 0xFF);
    for (var i = 0; i < 16; i++) {
      packet.setAll(6 + i * 6, macBytes);
    }
    return packet;
  }

  /// The broadcast addresses the packet is sent to: the limited broadcast
  /// (255.255.255.255) plus, as a fallback for networks/phones that drop
  /// limited broadcasts, the /24 directed broadcast of [serverIp]'s subnet.
  static List<String> broadcastTargets(String serverIp) {
    final targets = <String>[AppConstants.wolLimitedBroadcast];
    if (Validators.isIPv4(serverIp)) {
      final parts = serverIp.trim().split('.');
      targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return targets;
  }

  Future<void> wake({required String mac, required String serverIp}) async {
    final packet = buildMagicPacket(mac);
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      var sent = 0;
      for (final target in broadcastTargets(serverIp)) {
        try {
          sent += socket.send(packet, InternetAddress(target), AppConstants.wolPort);
        } on SocketException {
          // Try the next target.
        }
      }
      if (sent == 0) {
        throw const AppException(
          'Could not send the Wake-on-LAN packet. Make sure the phone is '
          'connected to your home Wi-Fi.',
        );
      }
    } on SocketException catch (e) {
      throw AppException(
        'Could not send the Wake-on-LAN packet (${e.osError?.message ?? e.message}). '
        'Make sure the phone is connected to your home Wi-Fi.',
      );
    } finally {
      socket?.close();
    }
  }
}
