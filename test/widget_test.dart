import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:immich_launcher/models/app_exception.dart';
import 'package:immich_launcher/models/server_config.dart';
import 'package:immich_launcher/models/validators.dart';
import 'package:immich_launcher/services/tailscale_service.dart';
import 'package:immich_launcher/services/wake_on_lan.dart';

void main() {
  group('WakeOnLan', () {
    test('magic packet is 6x0xFF followed by the MAC repeated 16 times', () {
      final packet = WakeOnLan.buildMagicPacket('68:1D:EF:4A:6B:DA');
      expect(packet.length, 102);
      expect(packet.sublist(0, 6), everyElement(0xFF));
      const mac = [0x68, 0x1D, 0xEF, 0x4A, 0x6B, 0xDA];
      for (var i = 0; i < 16; i++) {
        expect(packet.sublist(6 + i * 6, 12 + i * 6), mac);
      }
    });

    test('accepts different MAC notations', () {
      final expected = WakeOnLan.parseMac('68:1D:EF:4A:6B:DA');
      expect(WakeOnLan.parseMac('68-1d-ef-4a-6b-da'), expected);
      expect(WakeOnLan.parseMac('681DEF4A6BDA'), expected);
    });

    test('rejects invalid MACs', () {
      expect(() => WakeOnLan.parseMac('68:1D:EF'), throwsA(isA<AppException>()));
      expect(() => WakeOnLan.parseMac('ZZ:1D:EF:4A:6B:DA'),
          throwsA(isA<AppException>()));
    });

    test('broadcast targets include limited and /24 directed broadcast', () {
      expect(WakeOnLan.broadcastTargets('192.168.1.10'),
          ['255.255.255.255', '192.168.1.255']);
    });
  });

  group('Validators', () {
    test('ipv4', () {
      expect(Validators.ipv4('192.168.1.10'), isNull);
      expect(Validators.ipv4('192.168.1.300'), isNotNull);
      expect(Validators.ipv4(''), isNotNull);
    });

    test('host accepts IPs and MagicDNS names', () {
      expect(Validators.host('100.101.102.103'), isNull);
      expect(Validators.host('server.tail1234.ts.net'), isNull);
      expect(Validators.host('1.2.3.999'), isNotNull);
      expect(Validators.host('not a host'), isNotNull);
    });

    test('mac', () {
      expect(Validators.mac('68:1D:EF:4A:6B:DA'), isNull);
      expect(Validators.mac('68-1D-EF-4A-6B-DA'), isNull);
      expect(Validators.mac('68:1D-EF:4A:6B:DA'), isNotNull);
    });

    test('port', () {
      expect(Validators.port('2283'), isNull);
      expect(Validators.port('0'), isNotNull);
      expect(Validators.port('70000'), isNotNull);
      expect(Validators.port('abc'), isNotNull);
    });
  });

  group('ServerConfig', () {
    final values = {
      ConfigField.localIp: '192.168.1.10',
      ConfigField.macAddress: '68:1d:ef:4a:6b:da',
      ConfigField.tailscaleIp: '100.101.102.103',
      ConfigField.relayIp: '100.64.0.2',
      ConfigField.relayPort: '8765',
      ConfigField.sshUsername: 'ubuntu',
      ConfigField.sshPort: '22',
      ConfigField.immichPort: '2283',
    };

    test('round-trips through values', () {
      final config = ServerConfig.tryFromValues(values)!;
      expect(config.immichUrlFor(ConnectionRoute.local), 'http://192.168.1.10:2283');
      expect(config.immichUrlFor(ConnectionRoute.remote),
          'http://100.101.102.103:2283');
      expect(ServerConfig.tryFromValues(config.toValues())!.toValues(),
          config.toValues());
    });

    test('returns null when a value is missing or invalid', () {
      expect(ServerConfig.tryFromValues({...values, ConfigField.relayPort: null}),
          isNull);
      expect(ServerConfig.tryFromValues({...values, ConfigField.localIp: 'x'}),
          isNull);
    });
  });

  test('Tailscale CGNAT range detection', () {
    expect(TailscaleService.isTailscaleAddress(InternetAddress('100.64.0.1')), isTrue);
    expect(TailscaleService.isTailscaleAddress(InternetAddress('100.127.255.1')), isTrue);
    expect(TailscaleService.isTailscaleAddress(InternetAddress('100.128.0.1')), isFalse);
    expect(TailscaleService.isTailscaleAddress(InternetAddress('192.168.1.1')), isFalse);
  });
}
