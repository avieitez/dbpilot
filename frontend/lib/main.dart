import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_assets.dart';
import 'firebase_options.dart';
import 'presentation/screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/plan_access_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
  final _authService = AuthService();
  late final AnimationController _dotsController;
  AppUserSession? _session;
  bool _ready = false;
  bool _signingIn = false;
  bool _showInitialPaywall = false;
  String? _signInError;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final startedAt = DateTime.now();
    AppUserSession? session;
    try {
      session = await _authService.currentSession();
      if (session != null && !session.hasVerifiedEmail) {
        await _authService.signOut();
        session = null;
      }
    } catch (_) {
      session = null;
    }

    final elapsed = DateTime.now().difference(startedAt);
    const minimumSplashDuration = Duration(seconds: 3);
    if (elapsed < minimumSplashDuration) {
      await Future<void>.delayed(minimumSplashDuration - elapsed);
    }
    if (!mounted) return;

    final showPaywall = await _shouldShowInitialPaywall(session);
    PlanAccessService.instance.updateSession(session);
    _dotsController.stop();
    setState(() {
      _session = session;
      _showInitialPaywall = showPaywall;
      _ready = true;
    });
  }

  Future<bool> _shouldShowInitialPaywall(AppUserSession? session) async {
    if (session == null || session.plan == SubscriptionPlan.pro) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('onboarding.paywallShown.${session.uid}') ?? false);
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _signInError = null;
    });

    try {
      final session = await _authService.signInWithGoogle();
      if (!mounted) return;
      if (session == null) {
        setState(() => _signInError = 'Google sign-in was cancelled.');
        return;
      }
      if (!session.hasVerifiedEmail) {
        await _authService.signOut();
        if (!mounted) return;
        setState(() {
          _signInError = 'A verified Google email is required.';
        });
        return;
      }

      final showPaywall = await _shouldShowInitialPaywall(session);
      if (!mounted) return;
      PlanAccessService.instance.updateSession(session);
      setState(() {
        _session = session;
        _showInitialPaywall = showPaywall;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signInError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _handleSignedOut() {
    PlanAccessService.instance.updateSession(null);
    setState(() {
      _session = null;
      _showInitialPaywall = false;
      _signInError = null;
    });
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
      child: !_ready
          ? _StartupScreen(controller: _dotsController)
          : _session == null
              ? _SignInScreen(
                  busy: _signingIn,
                  error: _signInError,
                  onSignIn: _signIn,
                )
              : HomeScreen(
                  initialSession: _session!,
                  showInitialPaywall: _showInitialPaywall,
                  onSignedOut: _handleSignedOut,
                ),
    );
  }
}

class _SignInScreen extends StatelessWidget {
  const _SignInScreen({
    required this.busy,
    required this.error,
    required this.onSignIn,
  });

  final bool busy;
  final String? error;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(AppAssets.appIcon, width: 84, height: 84),
                  const SizedBox(height: 22),
                  const Text(
                    'Welcome to DBPilot',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sign in with Google to verify your email and keep your plan connected to your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: busy ? null : onSignIn,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user_outlined,
                          size: 16, color: Colors.white54),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Authentication is required to use DBPilot.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
