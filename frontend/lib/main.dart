import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/analytics_screen.dart';
import 'screens/launcher_home.dart';
import 'screens/parent_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/social_screen.dart';
import 'screens/focustube_blocker_screen.dart';
import 'screens/day_planner_screen.dart';
import 'services/blocker_service.dart';
import 'services/launcher_state.dart';
import 'services/offline_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hide status bar on home screen & swipe panels (immersiveSticky lets users
  // swipe down to temporarily reveal the status bar for notifications).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Lock app to portrait mode regardless of device orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Pre-load FocusTube blocker rules so the launcher can intercept blocked apps
  // immediately on first tap, without waiting for FocusTubeBlockerScreen to open.
  await BlockerService.instance.load();

  // Start offline sync service - periodically syncs queued data
  OfflineSyncService.instance.startPeriodicSync();

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
      builder: (context, child) {
        return ListenableBuilder(
          listenable: BlockerService.instance,
          builder: (context, _) {
            final mono = BlockerService.instance.monochromeModeEnabled;
            return ColorFiltered(
              colorFilter: mono
                  ? const ColorFilter.matrix(<double>[
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ])
                  : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: child!,
            );
          },
        );
      },
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
      initialRoute: '/home',
      routes: {
        '/home': (context) => const LauncherHome(),
        '/pomodoro': (context) => const PomodoroScreen(),
        '/analytics': (context) => const AnalyticsScreen(),
        '/social': (context) => const SocialScreen(),
        '/parent': (context) => const ParentScreen(),
        '/blocker': (context) => const FocusTubeBlockerScreen(),
        '/planner': (context) => const DayPlannerScreen(),
      },
    );
  }
}
