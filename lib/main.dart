import 'package:flutter/material.dart';

import 'constants.dart';
import 'controllers/launcher_controller.dart';
import 'models/server_config.dart';
import 'screens/home_screen.dart';
import 'screens/setup_wizard_screen.dart';
import 'services/config_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ConfigStore.create();
  runApp(ImmichLauncherApp(store: store));
}

class ImmichLauncherApp extends StatefulWidget {
  const ImmichLauncherApp({super.key, required this.store});

  final ConfigStore store;

  @override
  State<ImmichLauncherApp> createState() => _ImmichLauncherAppState();
}

class _ImmichLauncherAppState extends State<ImmichLauncherApp> {
  LauncherController? _controller;

  @override
  void initState() {
    super.initState();
    final config = widget.store.load();
    if (config != null) _controller = _createController(config);
  }

  LauncherController _createController(ServerConfig config) =>
      LauncherController(config: config, store: widget.store);

  void _onSetupComplete(ServerConfig config) {
    setState(() => _controller = _createController(config));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4250AF),
          brightness: brightness,
        ),
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: controller == null
          ? SetupWizardScreen(store: widget.store, onComplete: _onSetupComplete)
          : HomeScreen(controller: controller),
    );
  }
}
