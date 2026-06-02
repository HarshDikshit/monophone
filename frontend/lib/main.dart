import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/auth_screen.dart';
import 'screens/launcher_home.dart';
import 'screens/parent_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/social_screen.dart';
import 'services/api_service.dart';
import 'services/launcher_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
      initialRoute: '/',
      routes: {
        '/': (context) => const TokenCheckScreen(),
        '/auth': (context) => const AuthScreen(),
        '/home': (context) => const LauncherHome(),
        '/pomodoro': (context) => const PomodoroScreen(),
        '/social': (context) => const SocialScreen(),
        '/parent': (context) => const ParentScreen(),
      },
    );
  }
}

class TokenCheckScreen extends StatefulWidget {
  const TokenCheckScreen({super.key});

  @override
  State<TokenCheckScreen> createState() => _TokenCheckScreenState();
}

class _TokenCheckScreenState extends State<TokenCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  Future<void> _checkToken() async {
    final token = await ApiService.getToken();
    if (!mounted) return;

    if (token != null) {
      // Warm up user data
      try {
        final state = Provider.of<LauncherState>(context, listen: false);
        await state.fetchUserProfile();
        await state.updateAIHeadline();
      } catch (_) {
        // Token might be expired, log out just in case
        await ApiService.logout();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/auth');
          return;
        }
      }
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'LOADING...',
          style: TextStyle(
            color: Colors.white,
            letterSpacing: 4.0,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
