import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/constants/app_assets.dart';
import 'presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const DBPilotApp());
}

class DBPilotApp extends StatelessWidget {
  const DBPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DBPilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2D8CFF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotsController;
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    unawaited(_showHomeAfterDelay());
  }

  Future<void> _showHomeAfterDelay() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    _dotsController.stop();
    setState(() => _showHome = true);
  }

  @override
  void dispose() {
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showHome
          ? const HomeScreen()
          : _StartupScreen(controller: _dotsController),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppAssets.appIcon,
                  width: 104,
                  height: 104,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Connect to your databases',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF536276),
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'your way,',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF05080D),
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const Text(
                  'anytime, anywhere.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF05080D),
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 60),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final activeIndex =
                        (controller.value * 3).floor().clamp(0, 2).toInt();
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (index) => _StartupDot(active: activeIndex == index),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupDot extends StatelessWidget {
  const _StartupDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: active ? 9 : 8,
      height: active ? 9 : 8,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFBFE0FF) : const Color(0xFFE0E5EA),
        shape: BoxShape.circle,
      ),
    );
  }
}
