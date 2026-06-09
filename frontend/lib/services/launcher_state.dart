import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'blocker_service.dart';
import 'offline_sync_service.dart';

class LauncherState extends ChangeNotifier {
  static const _channel = MethodChannel('com.dixit.monophone/launcher');

  // Timer mode: 'countdown' or 'countup'
  String _timerMode = 'countdown';
  String get timerMode => _timerMode;

  // Custom duration in seconds (user-defined, default 25 min)
  int _customDurationSeconds = 25 * 60;
  int get customDurationSeconds => _customDurationSeconds;

  // Is fullscreen mode enabled
  bool _isFullScreen = false;
  bool get isFullScreen => _isFullScreen;

  // App lists
  List<Map<String, String>> _allApps = [];
  List<Map<String, String>> get allApps => _allApps;

  Set<String> _studyApps = {};
  Set<String> _distractionApps = {};

  Set<String> get studyApps => _studyApps;
  Set<String> get distractionApps => _distractionApps;

  // Stats
  int _studySeconds = 0;
  int _distractedSeconds = 0;
  int get distractedSeconds => _distractedSeconds;

  String _lastGoal = '';
  String get lastGoal => _lastGoal;

  String _aiHeadline = 'Close distractions. Protect your attention.';
  String get aiHeadline => _aiHeadline;

  Map<String, int> _weeklyStudyData = {};
  Map<String, int> get weeklyStudyData => _weeklyStudyData;

  // Pomodoro
  bool _isPomodoroActive = false;
  bool _isBreak = false;

  /// COUNTDOWN: seconds remaining (counts down to 0)
  /// COUNTUP:   seconds elapsed (counts up from 0)
  int _pomodoroSecondsRemaining = 25 * 60;
  int _pomodoroTotalDurationSeconds = 25 * 60;
  int _pomodoroAccountedSeconds = 0;
  int _pomodoroPendingFocusSeconds = 0;
  int _pomodoroPendingTaskSeconds = 0;
  bool _pomodoroDirty = false;
  Timer? _pomodoroTimer;

  bool get isPomodoroActive => _isPomodoroActive;
  bool get isBreak => _isBreak;

  /// Returns the displayed time value:
  /// - countdown: remaining seconds
  /// - countup:   elapsed seconds
  int get pomodoroSecondsRemaining => _pomodoroSecondsRemaining;

  /// Returns the actual elapsed focus seconds accounting for mode
  int get pomodoroElapsedSeconds {
    if (!_isPomodoroActive) return 0;
    if (_timerMode == 'countup') return _pomodoroSecondsRemaining;
    return _pomodoroTotalDurationSeconds - _pomodoroSecondsRemaining;
  }

  int get studySeconds => _studySeconds + _pomodoroPendingFocusSeconds;

  // Study Tasks State
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> get tasks => _tasks;

  String? _activeTaskId;
  String? get activeTaskId => _activeTaskId;

  DateTime _lastTaskActivityTime = DateTime.now();

  Map<String, dynamic>? get activeTask => _activeTaskId != null
      ? _tasks.firstWhere(
          (t) => t['id'] == _activeTaskId,
          orElse: () => <String, dynamic>{},
        )
      : null;

  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _lastLaunchedPackage;
  DateTime? _exitTime;

  bool _doubleTapLockScreen = false;
  bool get doubleTapLockScreen => _doubleTapLockScreen;

  bool _doubleTapOpenDrawer = false;
  bool get doubleTapOpenDrawer => _doubleTapOpenDrawer;

  bool _isDefaultLauncher = false;
  bool _skipDefaultLauncher = false;
  bool get isDefaultLauncher => _isDefaultLauncher || _skipDefaultLauncher;

  LauncherState() {
    _init();
  }

  Future<void> _init() async {
    await refreshAppsList();
    await _loadLocalStats();
    _initMethodChannel();
  }

  // ── Timer mode / duration / fullscreen setters ──
  void setTimerMode(String mode) {
    _timerMode = mode;
    notifyListeners();
  }

  void setCustomDuration(int seconds) {
    _customDurationSeconds = seconds;
    notifyListeners();
  }

  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  void setFullScreen(bool val) {
    _isFullScreen = val;
    notifyListeners();
  }

  void _initMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPomodoroTick':
          _pomodoroSecondsRemaining = call.arguments['secondsRemaining'] ?? 0;
          final bool isBreakVal = call.arguments['isBreak'] ?? false;
          _isBreak = isBreakVal;
          // Each tick = 1 second of focus time, increment directly
          if (_isPomodoroActive && !_isBreak) {
            _pomodoroPendingFocusSeconds += 1;
            _pomodoroPendingTaskSeconds += 1;
            _pomodoroDirty = true;
          }
          notifyListeners();
          break;
        case 'onPomodoroStateChanged':
          final String status = call.arguments['status'] ?? "STOPPED";
          final int seconds = call.arguments['secondsRemaining'] ?? 0;
          final bool isBreakVal = call.arguments['isBreak'] ?? false;
          final String task = call.arguments['taskName'] ?? "";
          final int elapsed = call.arguments['elapsedSeconds'] ?? 0;

          if (status == "STOPPED") {
            await _commitPomodoroProgress(sync: true);
            _isPomodoroActive = false;
            _pomodoroAccountedSeconds = 0;
            _pomodoroTotalDurationSeconds = _customDurationSeconds;
          } else if (status == "BREAK") {
            if (!_isBreak && isBreakVal) {
              await _commitPomodoroProgress(sync: true);
              _incrementActiveTaskPomodoro();
            }
            _isPomodoroActive = true;
            _isBreak = isBreakVal;
            _pomodoroSecondsRemaining = seconds;
            _pomodoroAccountedSeconds = 0;
            _pomodoroTotalDurationSeconds = 5 * 60;
          } else {
            _isPomodoroActive = true;
            _isBreak = isBreakVal;
            _pomodoroSecondsRemaining = seconds;
            if (task.isNotEmpty) {
              _lastGoal = task;
            }
            _lastTaskActivityTime = DateTime.now();
            if (!_isBreak) {
              _pomodoroTotalDurationSeconds = _pomodoroTotalDurationSeconds > 0
                  ? _pomodoroTotalDurationSeconds
                  : _customDurationSeconds;
              _accountPomodoroElapsed(elapsed);
            }
          }
          notifyListeners();
          break;
        case 'onDefaultLauncherChanged':
          _isDefaultLauncher = call.arguments == true;
          notifyListeners();
          break;
        case 'onBlockTriggered':
          {
            final args = call.arguments is Map
                ? Map<String, dynamic>.from(call.arguments)
                : <String, dynamic>{};
            debugPrint(
              "Block triggered: ${args['packageName']} — ${args['reason']}",
            );
            notifyListeners();
          }
          break;
        case 'onEmergencyUseStarted':
          {
            final args = call.arguments is Map
                ? Map<String, dynamic>.from(call.arguments)
                : <String, dynamic>{};
            debugPrint("Emergency use started: ${args['packageName']}");
            notifyListeners();
          }
          break;
        case 'onEmergencyUseExpired':
          {
            final args = call.arguments is Map
                ? Map<String, dynamic>.from(call.arguments)
                : <String, dynamic>{};
            debugPrint(
              "Emergency use expired: ${args['packageName']} — re-locking",
            );
            notifyListeners();
          }
          break;
        case 'onEmergencyUseTick':
          notifyListeners();
          break;
      }
    });
  }

  Future<void> _loadLocalStats() async {
    final prefs = await SharedPreferences.getInstance();

    _studyApps = (prefs.getStringList('study_packages') ?? []).toSet();
    _distractionApps = (prefs.getStringList('distraction_packages') ?? [])
        .toSet();

    final todayStr = _todayKey();
    _studySeconds = prefs.getInt('study_seconds_$todayStr') ?? 0;
    _distractedSeconds = prefs.getInt('distracted_seconds_$todayStr') ?? 0;
    _lastGoal = prefs.getString('last_goal') ?? '';

    _timerMode = prefs.getString('timer_mode') ?? 'countdown';
    _customDurationSeconds = prefs.getInt('custom_duration_seconds') ?? 25 * 60;
    _isFullScreen = prefs.getBool('timer_fullscreen') ?? false;

    _doubleTapLockScreen = prefs.getBool('double_tap_lock_screen') ?? false;
    _doubleTapOpenDrawer = prefs.getBool('double_tap_open_drawer') ?? false;

    await _loadTasks();
    await loadWeeklyData();
    notifyListeners();

    try {
      final Map<dynamic, dynamic>? nativeState = await _channel.invokeMethod(
        'getPomodoroState',
      );
      if (nativeState != null) {
        _isPomodoroActive = true;
        _pomodoroSecondsRemaining = nativeState['secondsRemaining'] ?? 0;
        _isBreak = nativeState['isBreak'] ?? false;
        _lastGoal = nativeState['taskName'] ?? _lastGoal;
        _timerMode = nativeState['timerMode'] ?? _timerMode;
      }
    } catch (_) {}

    await checkDefaultLauncher();

    // Try to fetch user profile silently (works offline - uses cache)
    await fetchUserProfile();
    await updateAIHeadline();

    // Initialize blocker configs and start monitoring programmatically on startup
    try {
      final blocker = BlockerService.instance;
      final blockedPackageNames = <String>{};
      for (final app in blocker.unproductiveAppNames) {
        final match = _allApps.firstWhere(
          (element) =>
              (element['name'] ?? '').toLowerCase().trim() ==
              app.toLowerCase().trim(),
          orElse: () => <String, String>{},
        );
        if (match.isNotEmpty && match['packageName'] != null) {
          blockedPackageNames.add(match['packageName']!);
        }
      }
      if (blocker.blockReelsShorts) {
        for (final app in _allApps) {
          final name = (app['name'] ?? '').toLowerCase().trim();
          if (name.contains('instagram') ||
              name.contains('youtube') ||
              name.contains('tiktok') ||
              name.contains('facebook') ||
              name.contains('reels') ||
              name.contains('shorts')) {
            blockedPackageNames.add(app['packageName']!);
          }
        }
      }

      final dailyLimitsMap = <String, int>{};
      blocker.dailyLimits.forEach((appName, minutes) {
        final match = _allApps.firstWhere(
          (element) =>
              (element['name'] ?? '').toLowerCase().trim() ==
              appName.toLowerCase().trim(),
          orElse: () => <String, String>{},
        );
        if (match.isNotEmpty && match['packageName'] != null) {
          dailyLimitsMap[match['packageName']!] = minutes;
          blockedPackageNames.add(match['packageName']!);
        }
      });

      // Build emergency use max count map by package name
      final emergencyUseMaxMap = <String, int>{};
      blocker.emergencyUseCounts.forEach((appName, count) {
        final match = _allApps.firstWhere(
          (element) =>
              (element['name'] ?? '').toLowerCase().trim() ==
              appName.toLowerCase().trim(),
          orElse: () => <String, String>{},
        );
        if (match.isNotEmpty && match['packageName'] != null) {
          emergencyUseMaxMap[match['packageName']!] = count;
        }
      });

      await configureBlockingRules(
        blockedPackages: blockedPackageNames,
        dailyLimits: dailyLimitsMap,
        blockFirstShort: blocker.blockReelsShorts,
        restrictedKeywords: blocker.restrictedKeywords.toSet(),
        emergencyUseMaxCounts: emergencyUseMaxMap,
      );

      await startDailyMonitoring();
      await toggleVpn(blocker.vpnContentFilterEnabled);
      await toggleSystemGrayscale(blocker.monochromeModeEnabled);
    } catch (e) {
      debugPrint("Error initializing blocker service on startup: $e");
    }
  }

  Future<void> _saveTimerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timer_mode', _timerMode);
    await prefs.setInt('custom_duration_seconds', _customDurationSeconds);
    await prefs.setBool('timer_fullscreen', _isFullScreen);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _accountPomodoroElapsed(int elapsedSeconds) {
    final newlyElapsed = elapsedSeconds - _pomodoroAccountedSeconds;
    if (newlyElapsed > 0) {
      _pomodoroPendingFocusSeconds += newlyElapsed;
      _pomodoroPendingTaskSeconds += newlyElapsed;
      _pomodoroAccountedSeconds = elapsedSeconds;
      _pomodoroDirty = true;
      notifyListeners();
    }
  }

  Future<void> _commitPomodoroProgress({bool sync = false}) async {
    if (_pomodoroPendingFocusSeconds <= 0) {
      if (sync && (await ApiService.getToken()) != null) {
        await _syncStatsToBackend();
      }
      return;
    }

    _studySeconds += _pomodoroPendingFocusSeconds;
    final taskSeconds = _pomodoroPendingTaskSeconds;
    _pomodoroPendingFocusSeconds = 0;
    _pomodoroPendingTaskSeconds = 0;
    _pomodoroDirty = true;

    if (_activeTaskId != null && taskSeconds > 0) {
      _attributeSecondsToTask(_activeTaskId, taskSeconds);
    }

    await _saveLocalStats();
    if (sync) {
      await _syncStatsToBackend();
    }
    _pomodoroDirty = false;
  }

  Future<void> _saveLocalStats() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _todayKey();
    await prefs.setInt('study_seconds_$todayStr', _studySeconds);
    await prefs.setInt('distracted_seconds_$todayStr', _distractedSeconds);
    await prefs.setString('last_goal', _lastGoal);
    await loadWeeklyData();
  }

  Future<void> refreshAppsList() async {
    try {
      final List<dynamic>? apps = await _channel.invokeMethod(
        'getInstalledApps',
      );
      if (apps != null) {
        _allApps = apps.map((app) => Map<String, String>.from(app)).toList();
        notifyListeners();
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to get apps: ${e.message}");
    }
  }

  Future<void> toggleAppCategory(String packageName, String category) async {
    final prefs = await SharedPreferences.getInstance();

    if (category == 'study') {
      if (_studyApps.contains(packageName)) {
        _studyApps.remove(packageName);
      } else {
        _studyApps.add(packageName);
        _distractionApps.remove(packageName);
      }
    } else if (category == 'distraction') {
      if (_distractionApps.contains(packageName)) {
        _distractionApps.remove(packageName);
      } else {
        _distractionApps.add(packageName);
        _studyApps.remove(packageName);
      }
    }

    await prefs.setStringList('study_packages', _studyApps.toList());
    await prefs.setStringList(
      'distraction_packages',
      _distractionApps.toList(),
    );
    notifyListeners();
  }

  Future<bool> launchApp(String packageName) async {
    try {
      if (_isPomodoroActive &&
          !_isBreak &&
          _distractionApps.contains(packageName)) {
        return false;
      }

      _lastLaunchedPackage = packageName;
      _exitTime = DateTime.now();

      final appName = _allApps.firstWhere(
        (element) => element['packageName'] == packageName,
        orElse: () => {'name': 'App'},
      )['name'];
      final isStudy = _studyApps.contains(packageName);

      // Fire-and-forget: queue status update, don't block app launch
      _queueStatusUpdateAsync(isStudy, appName, packageName);

      // Launch app immediately without waiting for network
      await _channel.invokeMethod('launchApp', {'packageName': packageName});
      return true;
    } on PlatformException catch (e) {
      debugPrint("Failed to launch app: ${e.message}");
      return false;
    }
  }

  /// Fire-and-forget: queues status update without blocking app launch
  void _queueStatusUpdateAsync(
    bool isStudy,
    String? appName,
    String packageName,
  ) {
    final name = appName ?? 'App';
    ApiService.updateStatus(
      isStudy ? 'Studying ($name)' : 'Using $name 🛑',
      isStudy,
    ).then((_) {}).catchError((_) {
      OfflineSyncService.instance.queueStatusUpdate(
        isStudy ? 'Studying ($appName)' : 'Using $appName 🛑',
        isStudy,
      );
    });
  }

  Future<void> handleResume() async {
    await _channel.invokeMethod('hasUsageAccessPermission');

    await stopDistractionTimer();
    await checkDefaultLauncher();

    if (_exitTime != null && _lastLaunchedPackage != null) {
      final now = DateTime.now();
      final elapsed = now.difference(_exitTime!).inSeconds;
      if (elapsed <= 0) {
        _lastLaunchedPackage = null;
        _exitTime = null;
        return;
      }

      // Check if the day has crossed since the user left the launcher.
      // If so, the elapsed time belongs to yesterday — save it there.
      final exitDay = _exitTime!;
      final sameDay =
          exitDay.year == now.year &&
          exitDay.month == now.month &&
          exitDay.day == now.day;

      if (sameDay) {
        // Same day — add to today's stats
        if (_studyApps.contains(_lastLaunchedPackage)) {
          _studySeconds += elapsed;
          _attributeSecondsToTask(_activeTaskId, elapsed);
        } else if (_distractionApps.contains(_lastLaunchedPackage)) {
          _distractedSeconds += elapsed;
        } else {
          if (_isPomodoroActive && !_isBreak) {
            _studySeconds += elapsed;
            _attributeSecondsToTask(_activeTaskId, elapsed);
          }
        }
        await _saveLocalStats();
      } else {
        // Crossed midnight — save elapsed time to yesterday's storage key
        final yesterdayStr =
            '${exitDay.year}-${exitDay.month.toString().padLeft(2, '0')}-${exitDay.day.toString().padLeft(2, '0')}';
        final prefs = await SharedPreferences.getInstance();
        final prevStudy = prefs.getInt('study_seconds_$yesterdayStr') ?? 0;
        final prevDistracted =
            prefs.getInt('distracted_seconds_$yesterdayStr') ?? 0;

        if (_studyApps.contains(_lastLaunchedPackage)) {
          await prefs.setInt(
            'study_seconds_$yesterdayStr',
            prevStudy + elapsed,
          );
        } else if (_distractionApps.contains(_lastLaunchedPackage)) {
          await prefs.setInt(
            'distracted_seconds_$yesterdayStr',
            prevDistracted + elapsed,
          );
        } else if (_isPomodoroActive && !_isBreak) {
          await prefs.setInt(
            'study_seconds_$yesterdayStr',
            prevStudy + elapsed,
          );
        }

        // Reload today's stats from storage after the cross-day adjustment
        final todayStr = _todayKey();
        _studySeconds = prefs.getInt('study_seconds_$todayStr') ?? 0;
        _distractedSeconds = prefs.getInt('distracted_seconds_$todayStr') ?? 0;
        await loadWeeklyData();
      }

      _lastLaunchedPackage = null;
      _exitTime = null;

      try {
        await ApiService.updateStatus(
          _isPomodoroActive && !_isBreak ? 'Focusing ⚡' : 'Idle',
          _isPomodoroActive && !_isBreak,
        );
      } catch (_) {
        await OfflineSyncService.instance.queueStatusUpdate(
          _isPomodoroActive && !_isBreak ? 'Focusing ⚡' : 'Idle',
          _isPomodoroActive && !_isBreak,
        );
      }

      await _syncStatsToBackend();
      notifyListeners();
    }
  }

  Future<void> _syncStatsToBackend() async {
    final token = await ApiService.getToken();
    if (token != null) {
      try {
        await ApiService.syncActivity(
          _todayKey(),
          _studySeconds,
          _distractedSeconds,
        );
        await fetchUserProfile();
        await updateAIHeadline();
      } catch (_) {
        // Offline: queue for later sync
        await OfflineSyncService.instance.queueActivitySync(
          _todayKey(),
          _studySeconds,
          _distractedSeconds,
        );
      }
    }
  }

  Future<void> setTargetGoal(String goal) async {
    _lastGoal = goal;
    await _saveLocalStats();
    await OfflineSyncService.instance.cacheGoal(goal);
    notifyListeners();

    final token = await ApiService.getToken();
    if (token != null) {
      try {
        await ApiService.updateGoal(goal);
        await updateAIHeadline();
      } catch (_) {
        await OfflineSyncService.instance.queueGoalUpdate(goal);
      }
    } else {
      await OfflineSyncService.instance.queueGoalUpdate(goal);
    }
  }

  Future<void> fetchUserProfile() async {
    try {
      _isLoading = true;
      notifyListeners();

      final profile = await ApiService.getProfile();
      _userProfile = profile;
      await OfflineSyncService.instance.cacheUserProfile(profile);
      if (profile['targetGoal'] != null &&
          profile['targetGoal'].toString().isNotEmpty) {
        _lastGoal = profile['targetGoal'];
        await _saveLocalStats();
        await OfflineSyncService.instance.cacheGoal(_lastGoal);
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
      // Offline: try to use cached profile
      if (_userProfile == null) {
        final cached = await OfflineSyncService.instance.getCachedProfile();
        if (cached != null) {
          _userProfile = cached;
          final cachedGoal = await OfflineSyncService.instance.getCachedGoal();
          if (cachedGoal.isNotEmpty) {
            _lastGoal = cachedGoal;
            await _saveLocalStats();
          }
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateAIHeadline() async {
    try {
      final text = await ApiService.getAIBehaviorGuide(
        _studySeconds,
        _distractedSeconds,
        _lastGoal,
      );
      _aiHeadline = text;
      notifyListeners();
    } catch (_) {}
  }

  // ----------------------------------------------------
  // POMODORO LOGIC
  // ----------------------------------------------------

  Future<void> toggleUsagePermission() async {
    await _channel.invokeMethod('requestUsageAccessPermission');
  }

  Future<bool> checkUsagePermission() async {
    final bool res = await _channel.invokeMethod('hasUsageAccessPermission');
    return res;
  }

  Future<bool> checkNotificationPermission() async {
    try {
      final bool res = await _channel.invokeMethod('hasNotificationPermission');
      return res;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  void startPomodoro() async {
    if (_isPomodoroActive) return;

    final hasPermission = await checkUsagePermission();
    if (!hasPermission) {
      await toggleUsagePermission();
      return;
    }

    final hasNotificationPermission = await checkNotificationPermission();
    if (!hasNotificationPermission) {
      await requestNotificationPermission();
      return;
    }

    final hasOverlay = await checkOverlayPermission();
    if (!hasOverlay) {
      await requestOverlayPermission();
      return;
    }

    _isPomodoroActive = true;
    _isBreak = false;

    // COUNTDOWN: secondsRemaining starts at duration, counts down
    // COUNTUP:   secondsRemaining starts at 0, counts up (elapsed)
    _pomodoroSecondsRemaining = _timerMode == 'countdown'
        ? _customDurationSeconds
        : 0;
    _pomodoroTotalDurationSeconds = _customDurationSeconds;
    _pomodoroAccountedSeconds = 0;
    _pomodoroPendingFocusSeconds = 0;
    _pomodoroPendingTaskSeconds = 0;
    _pomodoroDirty = false;

    final focusTubeBlockedNames = BlockerService.instance.unproductiveAppNames
        .map((name) => name.toLowerCase().trim())
        .toSet();
    final focusTubePackages = _allApps
        .where(
          (app) => focusTubeBlockedNames.contains(
            (app['name'] ?? '').toLowerCase().trim(),
          ),
        )
        .map((app) => app['packageName'] ?? '')
        .where((pkg) => pkg.isNotEmpty)
        .toSet();

    final blockReels = BlockerService.instance.blockReelsShorts;
    final reelsPackages = _allApps
        .where((app) {
          if (!blockReels) return false;
          final name = (app['name'] ?? '').toLowerCase().trim();
          return name.contains('instagram') ||
              name.contains('youtube') ||
              name.contains('tiktok') ||
              name.contains('facebook') ||
              name.contains('reels') ||
              name.contains('shorts');
        })
        .map((app) => app['packageName'] ?? '')
        .where((pkg) => pkg.isNotEmpty)
        .toSet();

    final allBlockedPackages = {
      ..._distractionApps,
      ...focusTubePackages,
      ...reelsPackages,
    };
    await _channel.invokeMethod('startMonitoring', {
      'blockedApps': allBlockedPackages.toList(),
    });

    await _channel.invokeMethod('startPomodoro', {
      'taskName': _lastGoal.isNotEmpty ? _lastGoal : "Focus Session",
      'durationSeconds': _customDurationSeconds,
      'isBreak': false,
      'timerMode': _timerMode,
    });

    await ApiService.updateStatus('Focusing (Pomodoro) ⚡', true);

    await _saveTimerPreferences();

    notifyListeners();
  }

  void stopPomodoro() async {
    _isPomodoroActive = false;

    await _channel.invokeMethod('stopMonitoring');
    await _channel.invokeMethod('stopPomodoro');

    await ApiService.updateStatus('Idle', false);

    await _commitPomodoroProgress(sync: true);
    notifyListeners();
  }

  /// Check all required permissions at once, returns map of permission name -> granted status
  Future<Map<String, bool>> checkAllPermissions() async {
    final result = <String, bool>{};
    result['usageStats'] = await checkUsagePermission();
    result['overlay'] = await checkOverlayPermission();
    result['notification'] = await checkNotificationPermission();
    result['accessibility'] = await checkAccessibilityPermission();
    result['defaultLauncher'] = isDefaultLauncher;
    try {
      result['notificationListener'] = await hasNotificationAccess();
    } catch (_) {
      result['notificationListener'] = false;
    }
    return result;
  }

  /// Request a specific permission by name
  Future<void> requestPermissionByName(String name) async {
    switch (name) {
      case 'usageStats':
        await toggleUsagePermission();
        break;
      case 'overlay':
        await requestOverlayPermission();
        break;
      case 'notification':
        await requestNotificationPermission();
        break;
      case 'accessibility':
        await requestAccessibilityPermission();
        break;
      case 'defaultLauncher':
        await requestDefaultLauncher();
        break;
      case 'notificationListener':
        await requestNotificationAccess();
        break;
    }
  }

  // --- Double-Tap Actions ---
  Future<void> toggleDoubleTapLockScreen() async {
    _doubleTapLockScreen = !_doubleTapLockScreen;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('double_tap_lock_screen', _doubleTapLockScreen);
    notifyListeners();
  }

  Future<void> toggleDoubleTapOpenDrawer() async {
    _doubleTapOpenDrawer = !_doubleTapOpenDrawer;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('double_tap_open_drawer', _doubleTapOpenDrawer);
    notifyListeners();
  }

  Future<void> checkDefaultLauncher() async {
    try {
      _isDefaultLauncher = await _channel.invokeMethod('isDefaultLauncher');
      final prefs = await SharedPreferences.getInstance();
      _skipDefaultLauncher = prefs.getBool('launcher_skip_default') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> requestDefaultLauncher() async {
    try {
      await _channel.invokeMethod('requestDefaultLauncher');
    } catch (_) {}
  }

  Future<bool> checkAccessibilityPermission() async {
    try {
      final bool res = await _channel.invokeMethod(
        'isAccessibilityServiceEnabled',
      );
      return res;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<bool> checkOverlayPermission() async {
    try {
      final bool res = await _channel.invokeMethod('hasOverlayPermission');
      return res;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<void> lockScreen() async {
    try {
      await _channel.invokeMethod('lockScreen');
    } catch (_) {}
  }

  Future<void> openAppSettings(String packageName) async {
    try {
      await _channel.invokeMethod('openAppSettings', {
        'packageName': packageName,
      });
    } catch (_) {}
  }

  Future<void> startDistractionTimer(
    String packageName,
    int durationMinutes,
  ) async {
    try {
      await _channel.invokeMethod('startDistractionTimer', {
        'packageName': packageName,
        'durationSeconds': durationMinutes * 60,
      });
    } catch (e) {
      debugPrint("Failed to start distraction timer: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DEEP-FOCUS BLOCKER SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> configureBlockingRules({
    required Set<String> blockedPackages,
    required Map<String, int> dailyLimits,
    required bool blockFirstShort,
    required Set<String> restrictedKeywords,
    Map<String, int>? emergencyUseMaxCounts,
  }) async {
    try {
      await _channel.invokeMethod('configureBlockingRules', {
        'blockedPackages': blockedPackages.toList(),
        'dailyLimits': dailyLimits,
        'blockFirstShort': blockFirstShort,
        'restrictedKeywords': restrictedKeywords.toList(),
        'emergencyUseMaxCounts': emergencyUseMaxCounts ?? <String, int>{},
      });
    } catch (e) {
      debugPrint("Failed to configure blocking rules: $e");
    }
  }

  Future<void> startDailyMonitoring() async {
    try {
      await _channel.invokeMethod('startDailyMonitoring');
    } catch (e) {
      debugPrint("Failed to start daily monitoring: $e");
    }
  }

  Future<void> stopDailyMonitoring() async {
    try {
      await _channel.invokeMethod('stopDailyMonitoring');
    } catch (e) {
      debugPrint("Failed to stop daily monitoring: $e");
    }
  }

  Future<void> startAppMonitoring(List<String> blockedPackages) async {
    try {
      await _channel.invokeMethod('startMonitoring', {
        'blockedApps': blockedPackages,
      });
    } catch (e) {
      debugPrint("Failed to start app monitoring: $e");
    }
  }

  Future<void> stopAppMonitoring() async {
    try {
      await _channel.invokeMethod('stopMonitoring');
    } catch (e) {
      debugPrint("Failed to stop app monitoring: $e");
    }
  }

  Future<void> triggerEmergencyUse(String packageName) async {
    try {
      await _channel.invokeMethod('triggerEmergencyUse', {
        'packageName': packageName,
      });
    } catch (e) {
      debugPrint("Failed to trigger emergency use: $e");
    }
  }

  Future<Map<String, int>> getUsageReport() async {
    try {
      final result = await _channel.invokeMethod('getUsageReport');
      if (result is Map) {
        return Map<String, int>.from(result);
      }
    } catch (e) {
      debugPrint("Failed to get usage report: $e");
    }
    return {};
  }

  Future<bool> isBlockerOverlayShowing() async {
    try {
      return await _channel.invokeMethod('isBlockerOverlayShowing') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> stopDistractionTimer() async {
    try {
      await _channel.invokeMethod('stopDistractionTimer');
    } catch (e) {
      debugPrint("Failed to stop distraction timer: $e");
    }
  }

  Map<String, int> _weeklyDistractedData = {};
  Map<String, int> get weeklyDistractedData => _weeklyDistractedData;

  int _monthlyStudySeconds = 0;
  int _monthlyDistractedSeconds = 0;

  int get monthlyStudySeconds => _monthlyStudySeconds;
  int get monthlyDistractedSeconds => _monthlyDistractedSeconds;

  Future<void> loadWeeklyData() async {
    final prefs = await SharedPreferences.getInstance();
    final studyResult = <String, int>{};
    final distractedResult = <String, int>{};
    for (int i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      studyResult[key] = prefs.getInt('study_seconds_$key') ?? 0;
      distractedResult[key] = prefs.getInt('distracted_seconds_$key') ?? 0;
    }
    _weeklyStudyData = studyResult;
    _weeklyDistractedData = distractedResult;

    int mStudy = 0;
    int mDistract = 0;
    for (int i = 29; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      mStudy += prefs.getInt('study_seconds_$key') ?? 0;
      mDistract += prefs.getInt('distracted_seconds_$key') ?? 0;
    }
    _monthlyStudySeconds = mStudy;
    _monthlyDistractedSeconds = mDistract;

    notifyListeners();
  }

  // --- Task Engine ---
  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('focus_tasks');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _tasks = list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {
        _tasks = [];
      }
    }
    final todayStr = _todayKey();
    final lastReset = prefs.getString('tasks_last_reset') ?? '';
    if (lastReset != todayStr) {
      _tasks.removeWhere(
        (t) => (t['isDone'] == true) && (t['isRecurring'] != true),
      );
      for (final task in _tasks) {
        if (task['isRecurring'] == true) {
          task['isDone'] = false;
        }
      }
      if (_activeTaskId != null &&
          _tasks.indexWhere((t) => t['id'] == _activeTaskId) == -1) {
        _activeTaskId = null;
      }
      await prefs.setString('tasks_last_reset', todayStr);
      await _saveTasks();
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('focus_tasks', jsonEncode(_tasks));
    notifyListeners();
  }

  void _attributeSecondsToTask(String? taskId, int seconds) {
    if (taskId == null || seconds <= 0) return;
    final idx = _tasks.indexWhere((t) => t['id'] == taskId);
    if (idx != -1) {
      _tasks[idx]['focusSeconds'] =
          (_tasks[idx]['focusSeconds'] ?? 0) + seconds;
      _saveTasks();
    }
  }

  void _incrementActiveTaskPomodoro() {
    if (_activeTaskId == null) return;
    final idx = _tasks.indexWhere((t) => t['id'] == _activeTaskId);
    if (idx != -1) {
      _tasks[idx]['completedPomodoroCount'] =
          (_tasks[idx]['completedPomodoroCount'] ??
              _tasks[idx]['pomodoroCount'] ??
              0) +
          1;
      _saveTasks();
    }
  }

  Future<void> addTask(
    String title, {
    bool isRecurring = false,
    int estimatedPomodoros = 1,
  }) async {
    final task = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'isRecurring': isRecurring,
      'isDone': false,
      'focusSeconds': 0,
      'completedPomodoroCount': 0,
      'estimatedPomodoros': estimatedPomodoros,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _tasks.add(task);
    await _saveTasks();
  }

  Future<void> updateTaskEstimatedPomodoros(String taskId, int count) async {
    final idx = _tasks.indexWhere((t) => t['id'] == taskId);
    if (idx != -1) {
      _tasks[idx]['estimatedPomodoros'] = count.clamp(1, 99);
      await _saveTasks();
    }
  }

  Future<void> deleteTask(String taskId) async {
    _tasks.removeWhere((t) => t['id'] == taskId);
    if (_activeTaskId == taskId) _activeTaskId = null;
    await _saveTasks();
  }

  Future<void> toggleTaskComplete(String taskId) async {
    final idx = _tasks.indexWhere((t) => t['id'] == taskId);
    if (idx != -1) {
      _tasks[idx]['isDone'] = !(_tasks[idx]['isDone'] ?? false);
      await _saveTasks();
    }
  }

  Future<void> toggleTaskRecurring(String taskId) async {
    final idx = _tasks.indexWhere((t) => t['id'] == taskId);
    if (idx != -1) {
      _tasks[idx]['isRecurring'] = !(_tasks[idx]['isRecurring'] ?? false);
      await _saveTasks();
    }
  }

  Future<void> modifyTask(String taskId, String newTitle) async {
    final idx = _tasks.indexWhere((t) => t['id'] == taskId);
    if (idx != -1) {
      _tasks[idx]['title'] = newTitle;
      await _saveTasks();
    }
  }

  void setActiveTask(String? taskId) {
    _activeTaskId = taskId;
    _lastTaskActivityTime = DateTime.now();
    notifyListeners();
  }

  void switchActiveTask(String? newTaskId) {
    if (_isPomodoroActive && !_isBreak) {
      final currentElapsed = pomodoroElapsedSeconds;
      final newlyElapsed = currentElapsed - _pomodoroAccountedSeconds;
      if (newlyElapsed > 0) {
        _attributeSecondsToTask(_activeTaskId, newlyElapsed);
        _studySeconds += newlyElapsed;
        _pomodoroAccountedSeconds = currentElapsed;
        _saveLocalStats();
      }
    }
    _activeTaskId = newTaskId;
    _lastTaskActivityTime = DateTime.now();

    if (_isPomodoroActive) {
      final newTaskName = newTaskId != null
          ? _tasks.firstWhere(
              (t) => t['id'] == newTaskId,
              orElse: () => {'title': 'Focus Session'},
            )['title']
          : "Focus Session";
      _lastGoal = newTaskName;
      _saveLocalStats();
      _channel.invokeMethod('updateTaskName', {'taskName': newTaskName});
    }

    notifyListeners();
  }

  // ── Blocker & Native Service Integrations ──

  Future<void> toggleVpn(bool enabled) async {
    try {
      await _channel.invokeMethod('toggleVpn', {'enabled': enabled});
    } catch (e) {
      debugPrint("Failed to toggle VPN: $e");
    }
  }

  Future<bool> hasNotificationAccess() async {
    try {
      return await _channel.invokeMethod('hasNotificationAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestNotificationAccess() async {
    try {
      await _channel.invokeMethod('requestNotificationAccess');
    } catch (e) {
      debugPrint("Failed to request notification access: $e");
    }
  }

  Future<void> toggleSystemGrayscale(bool enabled) async {
    try {
      await _channel.invokeMethod('toggleSystemGrayscale', {
        'enabled': enabled,
      });
    } catch (e) {
      debugPrint("Failed to toggle system grayscale: $e");
    }
  }

  Future<void> updateBlockerSettings({
    required bool isStrictMode,
    required bool blockReelsShorts,
    required String unlockOption,
    DateTime? lockUntilDate,
    required bool vpnContentFilterEnabled,
    required bool monochromeModeEnabled,
    required bool notificationSilenceEnabled,
    required String frictionGateType,
    required List<String> restrictedKeywords,
    required Map<String, int> dailyLimits,
    required List<String> unproductiveAppNames,
    required List<Map<String, String>> channels,
    Map<String, int>? emergencyUseCounts,
  }) async {
    await BlockerService.instance.saveSettings(
      isStrictMode: isStrictMode,
      blockReelsShorts: blockReelsShorts,
      unlockOption: unlockOption,
      lockUntilDate: lockUntilDate,
      vpnContentFilterEnabled: vpnContentFilterEnabled,
      monochromeModeEnabled: monochromeModeEnabled,
      notificationSilenceEnabled: notificationSilenceEnabled,
      frictionGateType: frictionGateType,
      restrictedKeywords: restrictedKeywords,
      dailyLimits: dailyLimits,
      emergencyUseCounts:
          emergencyUseCounts ?? BlockerService.instance.emergencyUseCounts,
      unproductiveAppNames: unproductiveAppNames,
      channels: channels,
    );

    // Re-sync rules with native side
    final blockedPackageNames = <String>{};
    for (final app in unproductiveAppNames) {
      final match = _allApps.firstWhere(
        (element) =>
            (element['name'] ?? '').toLowerCase().trim() ==
            app.toLowerCase().trim(),
        orElse: () => <String, String>{},
      );
      if (match.isNotEmpty && match['packageName'] != null) {
        blockedPackageNames.add(match['packageName']!);
      }
    }
    if (blockReelsShorts) {
      for (final app in _allApps) {
        final name = (app['name'] ?? '').toLowerCase().trim();
        if (name.contains('instagram') ||
            name.contains('youtube') ||
            name.contains('tiktok') ||
            name.contains('facebook') ||
            name.contains('reels') ||
            name.contains('shorts')) {
          blockedPackageNames.add(app['packageName']!);
        }
      }
    }

    final dailyLimitsMap = <String, int>{};
    dailyLimits.forEach((appName, minutes) {
      final match = _allApps.firstWhere(
        (element) =>
            (element['name'] ?? '').toLowerCase().trim() ==
            appName.toLowerCase().trim(),
        orElse: () => <String, String>{},
      );
      if (match.isNotEmpty && match['packageName'] != null) {
        dailyLimitsMap[match['packageName']!] = minutes;
        blockedPackageNames.add(match['packageName']!);
      }
    });

    // Build emergency use max counts by package name
    final emergencyUseMaxMap = <String, int>{};
    (emergencyUseCounts ?? BlockerService.instance.emergencyUseCounts).forEach((
      appName,
      count,
    ) {
      final match = _allApps.firstWhere(
        (element) =>
            (element['name'] ?? '').toLowerCase().trim() ==
            appName.toLowerCase().trim(),
        orElse: () => <String, String>{},
      );
      if (match.isNotEmpty && match['packageName'] != null) {
        emergencyUseMaxMap[match['packageName']!] = count;
      }
    });

    await configureBlockingRules(
      blockedPackages: blockedPackageNames,
      dailyLimits: dailyLimitsMap,
      blockFirstShort: blockReelsShorts,
      restrictedKeywords: restrictedKeywords.toSet(),
      emergencyUseMaxCounts: emergencyUseMaxMap,
    );

    // Restart daily monitoring to apply new limits
    await stopDailyMonitoring();
    await startDailyMonitoring();

    await toggleVpn(vpnContentFilterEnabled);
    await toggleSystemGrayscale(monochromeModeEnabled);
    notifyListeners();
  }
}
