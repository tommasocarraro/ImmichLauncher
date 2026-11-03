import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants.dart';
import '../models/app_exception.dart';

/// Shuts the server down over SSH and keeps the (optional) saved password
/// and the trusted host keys in the Android Keystore-backed secure storage.
class SshService {
  SshService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _passwordKey = 'ssh.password';
  static String _hostKeyKey(String host, int port) => 'ssh.hostkey.$host:$port';

  Future<String?> savedPassword() async {
    try {
      return await _storage.read(key: _passwordKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePassword(String password) =>
      _storage.write(key: _passwordKey, value: password);

  Future<void> forgetPassword() => _storage.delete(key: _passwordKey);

  /// Forgets all trusted host keys (needed after reinstalling the server OS).
  Future<void> forgetHostKeys() async {
    final all = await _storage.readAll();
    for (final key in all.keys.where((k) => k.startsWith('ssh.hostkey.'))) {
      await _storage.delete(key: key);
    }
  }

  /// Trust-on-first-use host key verification: the first key seen for a
  /// host is remembered; a different key later aborts the connection.
  Future<bool> _verifyHostKey(
      String host, int port, String type, Uint8List fingerprint) async {
    final key = _hostKeyKey(host, port);
    final seen = '$type:${base64.encode(fingerprint)}';
    final trusted = await _storage.read(key: key);
    if (trusted == null) {
      await _storage.write(key: key, value: seen);
      return true;
    }
    return trusted == seen;
  }

  /// Connects to [host] and runs `sudo shutdown now`, feeding [password] to
  /// sudo through stdin (so it also works without a NOPASSWD sudoers rule).
  Future<void> shutdown({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(host, port,
          timeout: AppConstants.sshConnectTimeout);
    } on SocketException {
      throw AppException(
          'Could not connect to SSH on $host:$port. Is the server online and '
          'is the SSH server (openssh-server) running?');
    } on TimeoutException {
      throw AppException('Connecting to $host:$port over SSH timed out.');
    } catch (e) {
      throw AppException('Could not connect to $host:$port over SSH ($e).');
    }

    var hostKeyMismatch = false;
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
      onUserInfoRequest: (request) =>
          request.prompts.map((_) => password).toList(),
      onVerifyHostKey: (type, fingerprint) async {
        final ok = await _verifyHostKey(host, port, type, fingerprint);
        if (!ok) hostKeyMismatch = true;
        return ok;
      },
    );

    try {
      try {
        await client.authenticated.timeout(AppConstants.sshConnectTimeout);
      } on SSHAuthFailError {
        throw const AppException(
            'SSH login failed: check the username in Settings and your password.');
      } on SSHAuthAbortError {
        throw const AppException('The server closed the SSH connection during login.');
      } on TimeoutException {
        throw const AppException('SSH login timed out.');
      } catch (e) {
        if (hostKeyMismatch) {
          throw AppException(
              'The SSH host key of $host changed since the last connection. '
              'If you reinstalled the server, reset trusted keys in Settings; '
              'otherwise someone may be impersonating your server.');
        }
        throw AppException('SSH login failed ($e).');
      }

      final session = await client.execute("sudo -S -p '' shutdown now");
      final stderr = StringBuffer();
      final stderrDone = session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(stderr.write, onError: (_) {})
          .asFuture<void>()
          .catchError((_) {});
      // Drain stdout so the channel never stalls on flow control.
      session.stdout.listen((_) {}, onError: (_) {});

      session.stdin.add(Uint8List.fromList(utf8.encode('$password\n')));
      await session.stdin.close();

      try {
        await session.done.timeout(AppConstants.sshCommandTimeout);
      } catch (_) {
        // The connection usually drops while the server shuts down: that is
        // the expected outcome, not an error.
      }
      await stderrDone.timeout(const Duration(seconds: 1), onTimeout: () {});

      final code = session.exitCode;
      if (code != null && code != 0) {
        final msg = stderr.toString().trim();
        if (msg.contains('incorrect password') ||
            msg.contains('Sorry, try again')) {
          throw const AppException(
              'sudo rejected the password. The password must be the one of the '
              'SSH user on the server.');
        }
        if (msg.contains('not in the sudoers')) {
          throw AppException('User "$username" is not allowed to use sudo on the server.');
        }
        throw AppException(
            'Shutdown failed (exit code $code)${msg.isEmpty ? '' : ': $msg'}');
      }
    } finally {
      client.close();
    }
  }
}
