import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/analytics_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/launcher_home.dart';
import 'screens/parent_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/social_screen.dart';
import 'screens/focustube_blocker_screen.dart';
import 'services/api_service.dart';
import 'services/blocker_service.dart';
import 'services/launcher_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Pre-load FocusTube blocker rules so the launcher can intercept blocked apps
  // immediately on first tap, without waiting for FocusTubeBlockerScreen to open.
  await BlockerService.instance.load();

  runApp(
    ChangeNotifierProvider(
      create: (_) => LauncherState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.white,
        fontFamily: 'monospace',
        textTheme: const TextTheme(
          displaySmall: TextStyle(color: Colors.white, fontFamily: 'monospace'),
          titleMedium: TextStyle(color: Colors.white, fontFamily: 'monospace'),
          bodyLarge: TextStyle(color: Colors.white70, fontFamily: 'monospace'),
          bodyMedium: TextStyle(color: Colors.white60, fontFamily: 'monospace'),
          bodySmall: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.white,
          selectionColor: Colors.white24,
          selectionHandleColor: Colors.white,
        ),
      ),
      // Use home as initial route — no Loading screen flash
      initialRoute: '/home',
      routes: {
        '/home': (context) =>
            const _AuthGate(), // Gate that checks auth silently
        '/auth': (context) => const AuthScreen(),
        '/pomodoro': (context) => const PomodoroScreen(),
        '/analytics': (context) => const AnalyticsScreen(),
        '/social': (context) => const SocialScreen(),
        '/parent': (context) => const ParentScreen(),
        '/blocker': (context) => const FocusTubeBlockerScreen(),
      },
    );
  }
}

/// Silently checks auth in initState. If not logged in, replaces with auth screen.
/// Shows LauncherHome immediately and does auth check in background to avoid
/// any "Loading..." flash on home button press.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _authChecked = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(Duration.zero); // Let frame render first
    final token = await ApiService.getToken();
    if (!mounted) return;

    setState(() => _authChecked = true);

    if (token == null) {
      Navigator.pushReplacementNamed(context, '/auth');
      return;
    }

    // Warm up user data in background (no loading screen)
    try {
      final state = Provider.of<LauncherState>(context, listen: false);
      await state.fetchUserProfile();
      await state.updateAIHeadline();
    } catch (_) {
      // Token expired
      await ApiService.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/auth');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LauncherHome();
  }
}
