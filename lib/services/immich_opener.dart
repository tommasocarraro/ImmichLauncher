import 'package:flutter/services.dart';

import '../constants.dart';
import '../models/app_exception.dart';
import 'platform_bridge.dart';

/// Hands the user off to Immich.
class ImmichOpener {
  const ImmichOpener({this.bridge = const PlatformBridge()});

  final PlatformBridge bridge;

  /// Opens Immich for [url]. Returns an informational message for the user,
  /// or `null` if nothing needs to be said.
  ///
  /// 1. Ask the Immich app to open the URL directly.
  /// 2. If it doesn't accept URLs, launch it and copy the URL to the
  ///    clipboard (the app remembers its server; the URL helps on first login
  ///    or when switching between the local and the Tailscale address).
  /// 3. If Immich isn't installed, open the web UI in the browser.
  Future<String?> open(String url) async {
    const pkg = AppConstants.immichPackage;
    if (await bridge.openUrlWithApp(pkg, url)) return null;

    if (await bridge.launchApp(pkg)) {
      await Clipboard.setData(ClipboardData(text: url));
      return 'Immich opened. Server URL $url copied to the clipboard in case '
          'the app asks for it.';
    }

    if (await bridge.openUrl(url)) {
      return 'The Immich app is not installed, so the web interface was '
          'opened in your browser.';
    }

    throw AppException(
        'Could not open Immich. Install the Immich app or open $url in a browser.');
  }
}
