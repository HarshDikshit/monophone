import 'dart:async';
import 'dart:io' show Process;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/launcher_state.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../services/blocker_service.dart';
import '../widgets/update_dialog.dart';
import '../widgets/panel_widgets/widget_panel.dart';
import '../widgets/lego_uncle/lego_uncle.dart';

class LauncherHome extends StatefulWidget {
  const LauncherHome({super.key});

  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome>
    with WidgetsBindingObserver {
  final _goalController = TextEditingController();
  bool _isEditingGoal = false;

  String _searchQuery = '';

  // Swipe Gestures & Overlays
  String _activeOverlay = 'none'; // 'none', 'app_drawer', 'thought_dump'
  String _drawerSearchQuery = '';

  // Analytics
  String _analyticsTab = 'WEEKLY';
  int _selectedBarIndex = -1;
  final GlobalKey _analyticsShareKey = GlobalKey();

  // Time and Date ticker
  late Timer _clockTimer;
  String _timeString = '';
  String _dateString = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateClock();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = Provider.of<LauncherState>(context, listen: false);
      _goalController.text = state.lastGoal;

      // Check for app updates
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _goalController.dispose();
    super.dispose();
  }

  // App Lifecycle monitoring to catch user return and log duration
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<LauncherState>(context, listen: false).handleResume();
    }
  }

  void _updateClock() {
    final now = DateTime.now();

    // Time format: 15:34
    final hour = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');

    // Date format: Sunday, May 31
    final weekdayList = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final monthList = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr =
        '${weekdayList[now.weekday % 7]}, ${monthList[now.month - 1]} ${now.day}';

    setState(() {
      _timeString = '$hour:$min';
      _dateString = dateStr.toUpperCase();
    });
  }

  // Check for available app updates
  Future<void> _checkForUpdates() async {
    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (updateInfo != null && mounted) {
        final currentVersion = await UpdateService.getCurrentVersion();
        await showUpdateDialog(
          context,
          currentVersion: currentVersion,
          latestVersion: updateInfo['latestVersion'] as String,
          isCriticalUpdate: updateInfo['isCriticalUpdate'] as bool,
          downloadUrl: updateInfo['downloadUrl'] as String,
          onLater: () {
            // User dismissed non-critical update, app continues normally
          },
        );
      }
    } catch (e) {
      // Silently fail - update check should not interrupt user experience
      debugPrint('Update check error: $e');
    }
  }

  // Share Analytics as Screenshot
  Future<void> _shareAnalyticsScreenshot() async {
    try {
      // Find the RepaintBoundary
      final RenderRepaintBoundary? boundary =
          _analyticsShareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) {
        _showShareError();
        return;
      }

      // Capture the widget as image
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        _showShareError();
        return;
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Share using share_plus
      await Share.shareXFiles(
        [
          XFile.fromData(
            pngBytes,
            mimeType: 'image/png',
            name: 'study_analytics.png',
          ),
        ],
        text:
            'My Study Analytics 📊\n'
            'Focus: ${_formatDurationForShare()}\n'
            'Goal: ${Provider.of<LauncherState>(context, listen: false).lastGoal}',
        subject: 'Study Analytics - Minimalist Launcher',
      );
    } catch (e) {
      debugPrint('Screenshot share error: $e');
      _showShareError();
    }
  }

  void _showShareError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Failed to share screenshot. Try again.',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
      ),
    );
  }

  // Helper for better share text
  String _formatDurationForShare() {
    final state = Provider.of<LauncherState>(context, listen: false);
    int studySec = 0;
    int distractedSec = 0;

    if (_analyticsTab == 'TODAY') {
      studySec = state.studySeconds;
      distractedSec = state.distractedSeconds;
    } else if (_analyticsTab == 'WEEKLY') {
      studySec = state.weeklyStudyData.values.fold(0, (sum, val) => sum + val);
      distractedSec = state.weeklyDistractedData.values.fold(
        0,
        (sum, val) => sum + val,
      );
    } else {
      studySec = state.monthlyStudySeconds;
      distractedSec = state.monthlyDistractedSeconds;
    }

    final focus = _formatDuration(studySec);
    final ratio = _calculateRatio(studySec, distractedSec);
    return '$focus Focus • $ratio';
  }
  // Countdown dialog for distraction block and allocation limit

  void _triggerBreathModal(String packageName, String appName) {
    int count = 5;
    Timer? countdownTimer;
    bool isCancelled = false;
    bool isTimeAllocationState = false;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black, // Full screen black background
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation1, animation2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Start the timer once inside dialog
            if (!isTimeAllocationState) {
              countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (
                timer,
              ) {
                if (count > 1) {
                  setDialogState(() {
                    count--;
                  });
                } else {
                  timer.cancel();
                  if (!isCancelled) {
                    setDialogState(() {
                      isTimeAllocationState = true;
                    });
                  }
                }
              });
            }

            return Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: !isTimeAllocationState
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BREATHE.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        letterSpacing: 4,
                                        fontWeight: FontWeight.w100,
                                        fontFamily: 'monospace',
                                      ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Take a deep breath. Do you really need to open $appName right now?',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                    height: 1.6,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                            Center(
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 100,
                                  fontWeight: FontWeight.w100,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                isCancelled = true;
                                countdownTimer?.cancel();
                                Navigator.pop(context); // Close dialog
                              },
                              child: Container(
                                height: 55,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white),
                                ),
                                child: const Center(
                                  child: Text(
                                    'GO BACK TO FOCUS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LIMIT ACCESS.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        letterSpacing: 4,
                                        fontWeight: FontWeight.w100,
                                        fontFamily: 'monospace',
                                      ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Choose a hard time limit for looking at $appName. When expired, you will be automatically returned to focus.',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                    height: 1.6,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                _buildLimitBtn(context, '5 MINUTES', () async {
                                  Navigator.pop(context);
                                  final state = Provider.of<LauncherState>(
                                    context,
                                    listen: false,
                                  );
                                  await state.startDistractionTimer(
                                    packageName,
                                    5,
                                  );
                                  await state.launchApp(packageName);
                                }),
                                const SizedBox(height: 12),
                                _buildLimitBtn(context, '10 MINUTES', () async {
                                  Navigator.pop(context);
                                  final state = Provider.of<LauncherState>(
                                    context,
                                    listen: false,
                                  );
                                  await state.startDistractionTimer(
                                    packageName,
                                    10,
                                  );
                                  await state.launchApp(packageName);
                                }),
                                const SizedBox(height: 12),
                                _buildLimitBtn(context, '20 MINUTES', () async {
                                  Navigator.pop(context);
                                  final state = Provider.of<LauncherState>(
                                    context,
                                    listen: false,
                                  );
                                  await state.startDistractionTimer(
                                    packageName,
                                    20,
                                  );
                                  await state.launchApp(packageName);
                                }),
                              ],
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context); // Close dialog
                              },
                              child: Container(
                                height: 55,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white),
                                ),
                                child: const Center(
                                  child: Text(
                                    'ABORT AND FOCUS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLimitBtn(
    BuildContext context,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  // Intercept application launch logic
  void _onAppTap(LauncherState state, Map<String, String> app) {
    final packageName = app['packageName'] ?? '';
    final appName = app['name'] ?? 'App';

    // Pomodoro Hard Lock Intercept
    if (state.isPomodoroActive &&
        !state.isBreak &&
        state.distractionApps.contains(packageName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black,
          shape: Border.all(color: Colors.white24),
          content: const Text(
            'LAUNCH LOCKED: POMODORO IN PROGRESS',
            style: TextStyle(
              color: Colors.red,
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ),
      );
      return;
    }

    // Launch immediately - native DailyUsageMonitorService enforces limits
    state.launchApp(packageName);
  }

  /// Show a simple redirect confirmation before launching a distraction app.
  /// This replaces the old multi-step breath + time allocation dialog.
  void _showDistractionRedirectModal(
    String appName,
    String packageName,
    LauncherState state,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      Text(
                        'DISTRACTION',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w100,
                              fontFamily: 'monospace',
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'You are about to open $appName. '
                        'This app is classified as a distraction. '
                        'Are you sure you want to proceed?',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          height: 1.6,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          state.launchApp(packageName);
                        },
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white30),
                          ),
                          child: const Center(
                            child: Text(
                              'OPEN ANYWAY',
                              style: TextStyle(
                                color: Colors.white38,
                                letterSpacing: 2,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          height: 55,
                          color: Colors.white,
                          child: const Center(
                            child: Text(
                              'GO BACK',
                              style: TextStyle(
                                color: Colors.black,
                                letterSpacing: 2,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FocusTube Regain-Focus overlay shown when a blocked app is tapped
  // ---------------------------------------------------------------------------
  void _showFocusTubeBlockOverlay(
    String appName,
    String packageName,
    BlockerService blocker,
  ) {
    final allowedChannels = blocker.allowedChannels;
    final isStrict = blocker.isStrictMode;
    final motivationalQuotes = [
      'Deep work is the superpower of the 21st century. Stay focused.',
      'A distracted mind is a defeated mind. Reclaim your focus.',
      'Disconnect to reconnect. Your future self is waiting.',
      'Focus on your North Star. Short-term distractions yield long-term regrets.',
      'Concentrate all your thoughts upon the work at hand.',
    ];
    final quote =
        motivationalQuotes[DateTime.now().millisecondsSinceEpoch %
            motivationalQuotes.length];

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ────────────────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isStrict ? 'STRICT BLOCK' : 'FOCUS BLOCK',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'ACCESS BLOCKED',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w100,
                              fontFamily: 'monospace',
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$appName has been marked as unproductive.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          height: 1.6,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),

                  // ── Motivational quote ─────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Colors.redAccent, width: 2),
                      ),
                    ),
                    child: Text(
                      '"$quote"',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.6,
                      ),
                    ),
                  ),

                  // ── Study channels list ────────────────────────────────────
                  if (allowedChannels.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'REGAIN FOCUS — WATCH INSTEAD:',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...allowedChannels
                            .take(5)
                            .map(
                              (ch) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.greenAccent,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      ch,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),

                  // ── Actions ────────────────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // In strict mode: only show "Go Back" — no bypass allowed
                      if (!isStrict)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                // Allow opening despite the block (bypass)
                                final st = Provider.of<LauncherState>(
                                  context,
                                  listen: false,
                                );
                                st.launchApp(packageName);
                              },
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: const Center(
                                  child: Text(
                                    'OPEN ANYWAY (BYPASS)',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      letterSpacing: 2,
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),

                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          height: 55,
                          decoration: const BoxDecoration(color: Colors.white),
                          child: const Center(
                            child: Text(
                              'STAY FOCUSED',
                              style: TextStyle(
                                color: Colors.black,
                                letterSpacing: 2,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSettingsModal(LauncherState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const Border(top: BorderSide(color: Colors.white24, width: 1)),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'LAUNCHER SETTINGS',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Default launcher toggle/button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'DEFAULT LAUNCHER',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        state.isDefaultLauncher
                            ? const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : GestureDetector(
                                onTap: () async {
                                  await state.requestDefaultLauncher();
                                  setModalState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white30),
                                  ),
                                  child: const Text(
                                    'SET DEFAULT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Double tap Lock Screen toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DOUBLE-TAP TO LOCK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Requires Accessibility Service',
                                style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: state.doubleTapLockScreen,
                          activeColor: Colors.white,
                          activeTrackColor: Colors.white60,
                          inactiveThumbColor: Colors.grey[800],
                          inactiveTrackColor: Colors.white10,
                          onChanged: (val) async {
                            if (val) {
                              final hasPermission = await state
                                  .checkAccessibilityPermission();
                              if (!hasPermission) {
                                Navigator.pop(context);
                                _showAccessibilityPrompt();
                                return;
                              }
                            }
                            await state.toggleDoubleTapLockScreen();
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Double tap Open App Screen toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'DOUBLE-TAP TO OPEN DRAWER',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        Switch(
                          value: state.doubleTapOpenDrawer,
                          activeColor: Colors.white,
                          activeTrackColor: Colors.white60,
                          inactiveThumbColor: Colors.grey[800],
                          inactiveTrackColor: Colors.white10,
                          onChanged: (val) async {
                            if (val && state.doubleTapLockScreen) {
                              await state.toggleDoubleTapLockScreen();
                            }
                            await state.toggleDoubleTapOpenDrawer();
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Permissions status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'OVERLAY PERMISSION',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        FutureBuilder<bool>(
                          future: state.checkOverlayPermission(),
                          builder: (context, snapshot) {
                            final hasPermission = snapshot.data ?? false;
                            return hasPermission
                                ? const Text(
                                    'GRANTED',
                                    style: TextStyle(
                                      color: Colors.white30,
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: () async {
                                      await state.requestOverlayPermission();
                                      Navigator.pop(context);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white30,
                                        ),
                                      ),
                                      child: const Text(
                                        'GRANT',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  );
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Classify Apps
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'CLASSIFY APPS',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _showAppClassificationSheet(state);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white30),
                            ),
                            child: const Text(
                              'OPEN',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAccessibilityPrompt() {
    showDialog(
      context: context,
      builder: (context) {
        final state = Provider.of<LauncherState>(context, listen: false);
        return AlertDialog(
          backgroundColor: Colors.black,
          shape: Border.all(color: Colors.white24),
          title: const Text(
            'ACCESSIBILITY SERVICE REQUIRED',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'To programmatically lock your screen via double-tap, please enable the Minimalist Study Launcher Accessibility Service in your system settings.',
            style: TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: Colors.white30,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await state.requestAccessibilityPermission();
              },
              child: const Text(
                'OPEN SETTINGS',
                style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAppClassificationSheet(LauncherState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const Border(top: BorderSide(color: Colors.white24, width: 1)),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CLASSIFY APPLICATIONS',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: state,
                      builder: (context, _) {
                        return _buildAppClassificationList(state);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _calculateRatio(int study, int distracted) {
    if (study + distracted == 0) return '0%';
    final pct = (study / (study + distracted) * 100).toStringAsFixed(0);
    return '$pct%';
  }

  Widget _buildAnalyticsTabBtn(String label) {
    final isActive = _analyticsTab == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _analyticsTab = label;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            border: Border.all(color: Colors.white24),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.black : Colors.white,
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsGrid(LauncherState state) {
    int studySec = 0;
    int distractedSec = 0;

    if (_analyticsTab == 'TODAY') {
      studySec = state.studySeconds;
      distractedSec = state.distractedSeconds;
    } else if (_analyticsTab == 'WEEKLY') {
      studySec = state.weeklyStudyData.values.fold(0, (sum, val) => sum + val);
      distractedSec = state.weeklyDistractedData.values.fold(
        0,
        (sum, val) => sum + val,
      );
    } else {
      // MONTHLY
      studySec = state.monthlyStudySeconds;
      distractedSec = state.monthlyDistractedSeconds;
    }

    final focusStr = _formatDuration(studySec);
    final distractStr = _formatDuration(distractedSec);
    final ratioStr = _calculateRatio(studySec, distractedSec);

    return Row(
      children: [
        _buildStatCard('FOCUS', focusStr),
        const SizedBox(width: 8),
        _buildStatCard('DISTRACTED', distractStr),
        const SizedBox(width: 8),
        _buildStatCard('RATIO', ratioStr),
      ],
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white10),
          color: Colors.white.withOpacity(0.01),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white30,
                fontSize: 8,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart(LauncherState state) {
    final data = state.weeklyStudyData;
    if (data.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: const Text(
          'NO DATA AVAILABLE',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    final keys = data.keys.toList();
    final values = data.values.toList();
    final maxMins = values
        .map((sec) => sec / 60.0)
        .fold<double>(0.0, (maxVal, val) => val > maxVal ? val : maxVal);

    final weekdayList = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        if (_selectedBarIndex != -1 && _selectedBarIndex < keys.length)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              '${keys[_selectedBarIndex]}: ${_formatDuration(values[_selectedBarIndex])}',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              'TAP A BAR TO VIEW DETAILS',
              style: TextStyle(
                color: Colors.white24,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
          ),
        Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(keys.length, (index) {
              final dateStr = keys[index];
              final sec = values[index];
              final mins = sec / 60.0;

              DateTime? dateObj;
              try {
                dateObj = DateTime.parse(dateStr);
              } catch (_) {}
              final dayLetter = dateObj != null
                  ? weekdayList[dateObj.weekday % 7]
                  : '?';

              final double heightPct = maxMins > 0 ? (mins / maxMins) : 0.0;
              final isSelected = _selectedBarIndex == index;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedBarIndex = isSelected ? -1 : index;
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: heightPct.clamp(0.02, 1.0),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white30,
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dayLetter,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white30,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskTimeBreakdown(LauncherState state) {
    final tasks = state.tasks;
    if (tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: const Text(
          'NO TASKS DEFINED',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    final sortedTasks = List<Map<String, dynamic>>.from(tasks)
      ..sort(
        (a, b) => (b['focusSeconds'] ?? 0).compareTo(a['focusSeconds'] ?? 0),
      );

    final totalTaskSeconds = sortedTasks.fold<int>(
      0,
      (sum, t) => sum + ((t['focusSeconds'] as int?) ?? 0),
    );

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedTasks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = sortedTasks[index];
        final title = (task['title'] as String? ?? 'Untitled').toUpperCase();
        final focusSec = (task['focusSeconds'] as int?) ?? 0;
        final poms =
            (task['completedPomodoroCount'] as int?) ??
            (task['pomodoroCount'] as int?) ??
            0;
        final estPoms = (task['estimatedPomodoros'] as int?) ?? 0;
        final isRecurring = task['isRecurring'] == true;

        final durationStr = _formatDuration(focusSec);
        final double pct = totalTaskSeconds > 0
            ? (focusSec / totalTaskSeconds)
            : 0.0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white10),
            color: Colors.white.withOpacity(0.01),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    children: [
                      if (isRecurring)
                        const Padding(
                          padding: EdgeInsets.only(right: 6.0),
                          child: Icon(
                            Icons.autorenew,
                            color: Colors.white30,
                            size: 12,
                          ),
                        ),
                      if (poms > 0 || estPoms > 0)
                        Text(
                          estPoms > 0 ? '$poms/$estPoms 🍅  ' : '$poms 🍅  ',
                          style: TextStyle(
                            color: poms >= estPoms && estPoms > 0
                                ? Colors.greenAccent.withOpacity(0.8)
                                : Colors.white70,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      Text(
                        durationStr,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final state = Provider.of<LauncherState>(context);

    if (!state.isDefaultLauncher) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 48.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      Text(
                        'DEFAULT LAUNCHER REQUIRED',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'To block distractions and successfully track your studies, this app must be selected as your default Home application.',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                  const Center(
                    child: Text(
                      '⚡',
                      style: TextStyle(fontSize: 64, color: Colors.white24),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await state.requestDefaultLauncher();
                        },
                        child: Container(
                          height: 55,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.white),
                          ),
                          child: const Center(
                            child: Text(
                              'SELECT LAUNCHER',
                              style: TextStyle(
                                color: Colors.black,
                                letterSpacing: 2,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Tap to choose Minimalist Launcher in system settings',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Filter apps based on view and search query (Strict mode: Study apps list only)
    List<Map<String, String>> filteredApps = state.allApps
        .where((app) => state.studyApps.contains(app['packageName']))
        .toList();

    if (_searchQuery.isNotEmpty) {
      filteredApps = filteredApps
          .where(
            (app) =>
                app['name']!.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 200) {
            // Swipe right (left to right) -> opens drawer or closes thought dump
            if (_activeOverlay == 'none') {
              setState(() {
                _activeOverlay = 'app_drawer';
              });
            } else if (_activeOverlay == 'thought_dump') {
              setState(() {
                _activeOverlay = 'none';
              });
            }
          } else if (velocity < -200) {
            // Swipe left (right to left) -> opens thought dump or closes drawer
            if (_activeOverlay == 'none') {
              setState(() {
                _activeOverlay = 'thought_dump';
              });
            } else if (_activeOverlay == 'app_drawer') {
              setState(() {
                _activeOverlay = 'none';
              });
            }
          }
        },
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -300) {
            // Swipe up (bottom to top) -> opens pomodoro timer
            Navigator.pushNamed(context, '/pomodoro');
          }
        },
        child: Stack(
          children: [
            // Layer 1: Main Home Workspace
            GestureDetector(
              onDoubleTap: () async {
                if (state.doubleTapLockScreen) {
                  final isAccessibilityEnabled = await state
                      .checkAccessibilityPermission();
                  if (isAccessibilityEnabled) {
                    await state.lockScreen();
                  } else {
                    _showAccessibilityPrompt();
                  }
                } else if (state.doubleTapOpenDrawer) {
                  setState(() {
                    _activeOverlay = 'app_drawer';
                  });
                }
              },
              child: Container(
                color: Colors.black, // Ensures full screen touch area
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24.0,
                      16.0,
                      24.0,
                      16.0 + bottomInset + 72.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Goal / North Star Editor
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: _isEditingGoal
                                  ? TextField(
                                      controller: _goalController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                      ),
                                      cursorColor: Colors.white,
                                      decoration: const InputDecoration(
                                        hintText: 'NORTH STAR GOAL',
                                        hintStyle: TextStyle(
                                          color: Colors.white24,
                                        ),
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: (value) async {
                                        setState(() {
                                          _isEditingGoal = false;
                                        });
                                        await state.setTargetGoal(value.trim());
                                      },
                                    )
                                  : GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _isEditingGoal = true;
                                        });
                                      },
                                      child: Text(
                                        state.lastGoal.isEmpty
                                            ? 'TAP TO DEFINE GOAL'
                                            : state.lastGoal.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          letterSpacing: 1.5,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                            ),
                            IconButton(
                              icon: Icon(
                                _isEditingGoal ? Icons.check : Icons.edit,
                                color: Colors.white30,
                                size: 18,
                              ),
                              onPressed: () async {
                                if (_isEditingGoal) {
                                  await state.setTargetGoal(
                                    _goalController.text.trim(),
                                  );
                                }
                                setState(() {
                                  _isEditingGoal = !_isEditingGoal;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 2. Large Minimal Clock & Lego Uncle
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _timeString,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.w100,
                                      letterSpacing: 2,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  Text(
                                    _dateString,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 10,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const LegoUncle(),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 3. AI Behavioral Headline
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Colors.white38, width: 2),
                            ),
                          ),
                          child: Text(
                            state.aiHeadline,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 4. Launcher Screen Action Center (Navigation Drawer row)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildQuickActionBtn('PLAN DAY', () {
                                Navigator.pushNamed(context, '/planner');
                              }),
                              _buildQuickActionBtn('POMODORO', () {
                                Navigator.pushNamed(context, '/pomodoro');
                              }),
                              _buildQuickActionBtn('SOCIAL LOOP', () {
                                Navigator.pushNamed(context, '/social');
                              }),
                              _buildQuickActionBtn('PARENTS', () {
                                Navigator.pushNamed(context, '/parent');
                              }),
                              _buildQuickActionBtn('BLOCKER', () {
                                Navigator.pushNamed(context, '/blocker');
                              }),
                              _buildQuickActionBtn('ANALYTICS', () {
                                Navigator.pushNamed(context, '/analytics');
                              }),
                              _buildQuickActionBtn('SETTINGS', () {
                                _showSettingsModal(state);
                              }),
                              _buildQuickActionBtn('LOGOUT', () async {
                                await ApiService.logout();
                                if (context.mounted) {
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/auth',
                                  );
                                }
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Search bar / Filter Apps
                        TextField(
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            hintText: 'SEARCH APPS...',
                            hintStyle: TextStyle(
                              color: Colors.grey[800],
                              letterSpacing: 1.5,
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.white24,
                              size: 18,
                            ),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white10),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white54),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // 5. Apps list Center
                        Expanded(
                          child: filteredApps.isEmpty
                              ? Center(
                                  child: Text(
                                    'NO STUDY APPS SELECTED',
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filteredApps.length,
                                  itemBuilder: (context, index) {
                                    final app = filteredApps[index];
                                    final isDistraction = state.distractionApps
                                        .contains(app['packageName']);
                                    final isStudy = state.studyApps.contains(
                                      app['packageName'],
                                    );

                                    return GestureDetector(
                                      onTap: () => _onAppTap(state, app),
                                      onLongPress: () =>
                                          _showAppLongPressDialog(state, app),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14.0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              app['name']!.toUpperCase(),
                                              style: TextStyle(
                                                color: isDistraction
                                                    ? Colors.grey[750]
                                                    : (isStudy
                                                          ? Colors.white
                                                          : Colors.grey[400]),
                                                fontFamily: 'monospace',
                                                fontSize: 14,
                                                fontWeight: isStudy
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            if (isStudy)
                                              const Text(
                                                '⚡',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white24,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              left: 24,
              bottom: 24 + bottomInset,
              child: _buildFloatingActionButton(
                icon: Icons.phone,
                tooltip: 'Open phone',
                onTap: _openPhoneApp,
              ),
            ),
            Positioned(
              right: 24,
              bottom: 24 + bottomInset,
              child: _buildFloatingActionButton(
                icon: Icons.message,
                tooltip: 'Open messages',
                onTap: _openMessageApp,
              ),
            ),
            // Layer 2: App Drawer Overlay (Slides in from Left)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              left: _activeOverlay == 'app_drawer' ? 0 : -screenWidth,
              top: 0,
              bottom: 0,
              width: screenWidth,
              child: _buildAppDrawerOverlay(state),
            ),

            // Layer 3: Widget Panel Overlay (Slides in from Right, left-swipe access)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              right: _activeOverlay == 'thought_dump' ? 0 : -screenWidth,
              top: 0,
              bottom: 0,
              width: screenWidth,
              child: WidgetPanel(
                onClose: () {
                  setState(() {
                    _activeOverlay = 'none';
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn(String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
            color: Colors.white.withOpacity(0.06),
          ),
          child: Center(child: Icon(icon, color: Colors.white, size: 24)),
        ),
      ),
    );
  }

  Widget _buildCornerActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
              color: Colors.white.withOpacity(0.03),
            ),
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 1,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPhoneApp() async {
    final uri = Uri(scheme: 'tel', path: '');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open phone app.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
        ),
      );
    }
  }

  Future<void> _openMessageApp() async {
    final uri = Uri(scheme: 'sms', path: '');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open messaging app.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
        ),
      );
    }
  }

  void _showAppLongPressDialog(LauncherState state, Map<String, String> app) {
    final pkg = app['packageName'] ?? '';
    final name = app['name'] ?? '';
    final isStudy = state.studyApps.contains(pkg);
    final isDistraction = state.distractionApps.contains(pkg);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 20),
            // Open App Info in System Settings
            GestureDetector(
              onTap: () async {
                state.openAppSettings(pkg);
                Navigator.pop(ctx);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'APP INFO',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Mark as Study
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                state.toggleAppCategory(pkg, 'study');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isStudy ? Icons.check_circle : Icons.circle_outlined,
                      color: isStudy ? Colors.white : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'MARK AS STUDY',
                      style: TextStyle(
                        color: isStudy ? Colors.white : Colors.grey[400],
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Mark as Distraction
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                state.toggleAppCategory(pkg, 'distraction');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isDistraction ? Icons.block : Icons.circle_outlined,
                      color: isDistraction ? Colors.redAccent : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'MARK AS DISTRACTION',
                      style: TextStyle(
                        color: isDistraction
                            ? Colors.redAccent
                            : Colors.grey[400],
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppDrawerOverlay(LauncherState state) {
    List<Map<String, String>> drawerApps = state.allApps;
    if (_drawerSearchQuery.isNotEmpty) {
      drawerApps = drawerApps
          .where(
            (app) => app['name']!.toLowerCase().contains(
              _drawerSearchQuery.toLowerCase(),
            ),
          )
          .toList();
    }

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'APP DRAWER',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () {
                      setState(() {
                        _activeOverlay = 'none';
                        _drawerSearchQuery = '';
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'SEARCH DEVICE APPS...',
                  hintStyle: TextStyle(
                    color: Colors.grey[800],
                    letterSpacing: 1.5,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white24,
                    size: 18,
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _drawerSearchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: drawerApps.isEmpty
                    ? const Center(
                        child: Text(
                          'NO APPS FOUND',
                          style: TextStyle(
                            color: Colors.white24,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: drawerApps.length,
                        itemBuilder: (context, index) {
                          final app = drawerApps[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _activeOverlay = 'none';
                                _drawerSearchQuery = '';
                              });
                              _onAppTap(state, app);
                            },
                            onLongPress: () {
                              setState(() {
                                _activeOverlay = 'none';
                                _drawerSearchQuery = '';
                              });
                              _showAppLongPressDialog(state, app);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14.0,
                                horizontal: 0,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.white10),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      app['name']!.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                        letterSpacing: 1,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white24,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Center(
                child: Text(
                  'SWIPE LEFT TO RETURN',
                  style: TextStyle(
                    color: Colors.white12,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Note: _buildThoughtDumpOverlay and bug report methods have been replaced
  // by the WidgetPanel component in widget_panel.dart.
  // The old scratchpad, analytics, chart and task breakdown are now
  // available as optional widgets users can add/remove/reorder.

  Widget _buildAppClassificationList(LauncherState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'TAP COLUMN TEXT TO TOGGLE APP STATUS',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 10,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: state.allApps.length,
            separatorBuilder: (context, index) =>
                const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final app = state.allApps[index];
              final pkg = app['packageName'] ?? '';
              final isStudy = state.studyApps.contains(pkg);
              final isDistraction = state.distractionApps.contains(pkg);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        app['name']!.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => state.toggleAppCategory(pkg, 'study'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            color: isStudy ? Colors.white : Colors.transparent,
                            child: Text(
                              'STUDY',
                              style: TextStyle(
                                color: isStudy
                                    ? Colors.black
                                    : Colors.grey[650],
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () =>
                              state.toggleAppCategory(pkg, 'distraction'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            color: isDistraction
                                ? Colors.white
                                : Colors.transparent,
                            child: Text(
                              'DISTRACT',
                              style: TextStyle(
                                color: isDistraction
                                    ? Colors.black
                                    : Colors.grey[650],
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
