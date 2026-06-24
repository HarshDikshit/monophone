import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'api_service.dart';
import 'blocker_service.dart';
import 'offline_sync_service.dart';
import 'task_planner_service.dart';
import '../widgets/battery_dialog.dart';

class LauncherState extends ChangeNotifier {
  static const _channel = MethodChannel('com.dixit.monophone/launcher');

  /// Global navigator key for showing dialogs from services without context.
  /// Set this in the MaterialApp constructor.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

  // Stats – these track TODAY only (loaded/saved per-day key)
  int _studySeconds = 0;
  int _distractedSeconds = 0;
  int get distractedSeconds => _distractedSeconds;

  String _lastGoal = '';
  String get lastGoal => _lastGoal;

  String _aiHeadline = 'Close distractions. Protect your attention.';
  String get aiHeadline => _aiHeadline;

  // Battery Optimization State
  bool _isBatteryOptimizationIgnored = true;
  bool _showBatteryPrompt = false;
  bool get isBatteryOptimizationIgnored => _isBatteryOptimizationIgnored;
  bool get showBatteryPrompt => _showBatteryPrompt;

  Map<String, int> _weeklyStudyData = {};
  Map<String, int> get weeklyStudyData => _weeklyStudyData;

  // Focus Timer
  bool _isFocusActive = false;
  bool _isPaused = false;
  bool get isPaused => _isPaused;
  bool _isManuallyStopped = false;

  /// Seconds elapsed (counts up from 0)
  int _focusElapsedSeconds = 0;

  // Pending seconds track time since last commit.
  int _focusPendingSeconds = 0;
  int _focusTickCounter = 0; // for periodic commits
  bool _focusDirty = false;
  String _lastCommitedDay = '';

  // New detailed analytics tracking
  List<int> _hourlyStudySeconds = List.filled(24, 0);
  Map<String, int> _taskStudySeconds = {};
  List<Map<String, dynamic>> _focusSessions = [];

  // Track current session details
  DateTime? _currentSessionStart;

  bool get isFocusActive => _isFocusActive;

  int get focusElapsedSeconds => _focusElapsedSeconds;

  int get studySeconds => _studySeconds + _focusPendingSeconds;

  String get focusElapsedSecondsFormatted {
    final m = _focusElapsedSeconds ~/ 60;
    final s = _focusElapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // Legacy aliases for Pomodoro backward compatibility
  bool get isPomodoroActive => _isFocusActive;
  bool get isBreak => false;
  int get pomodoroSecondsRemaining =>
      0; // Not applicable for count-up stopwatch

  // NO MORE LOCAL _tasks. We use _plannerService exclusively.

  String? _activeTaskId;
  String? get activeTaskId => _activeTaskId;

  DateTime _lastTaskActivityTime = DateTime.now();

  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool get isParent => _userProfile?['role'] == 'parent';
  List<dynamic> _linkedStudents = [];
  List<dynamic> get linkedStudents => _linkedStudents;

  String? _lastLaunchedPackage;
  DateTime? _exitTime;

  bool _doubleTapLockScreen = false;
  bool get doubleTapLockScreen => _doubleTapLockScreen;

  bool _doubleTapOpenDrawer = false;
  bool get doubleTapOpenDrawer => _doubleTapOpenDrawer;

  // Throttling timestamps
  DateTime? _lastPermissionCheck;
  DateTime? _lastSyncTime;
  DateTime? _lastProfileFetch;

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
    checkBatteryOptimizationStatus();

    // Once-a-day backend sync
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString('last_sync_date') != today) {
      _syncStatsToBackend();
    }

    _lastCommitedDay = prefs.getString('last_commited_day') ?? today;
    if (_lastCommitedDay != today) {
      // Midnight shift happened!
      _studySeconds = 0;
      _distractedSeconds = 0;
      _hourlyStudySeconds = List.filled(24, 0);
      _taskStudySeconds = {};
      _focusSessions = [];
      _lastCommitedDay = today;
      await prefs.setString('last_commited_day', today);
      _saveLocalStats();
    }
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
        case 'onFocusTick':
          _focusElapsedSeconds = call.arguments['elapsedSeconds'] ?? 0;

          if (_isFocusActive && !_isPaused) {
            _checkMidnightReset();
            _focusPendingSeconds += 1;
            _focusDirty = true;

            // Increment hourly bucket
            final hour = DateTime.now().hour;
            _hourlyStudySeconds[hour] += 1;

            // Real-time task attribution: immediately assign each second to the
            // active task so that task.focusSeconds stays continuously updated.
            // This ensures the day planner UI, analytics screen, and all task
            // analytics reflect the focus time in realtime (every 1 second).
            if (_activeTaskId != null) {
              _attributeSecondsToTask(_activeTaskId, 1, persist: false);
            }

            // Periodic commit every 60 seconds to prevent data loss
            _focusTickCounter++;
            if (_focusTickCounter >= 60) {
              _focusTickCounter = 0;
              _commitFocusProgress(sync: true);
            }
          }
          notifyListeners();
          break;
        case 'onFocusStateChanged':
          final String status = call.arguments['status'] ?? "STOPPED";
          final int elapsed = call.arguments['elapsedSeconds'] ?? 0;
          final String task = call.arguments['taskName'] ?? "";

          if (status == "STOPPED") {
            if (_isPaused) {
              _isFocusActive = true;
              notifyListeners();
              break;
            }

            await _commitFocusProgress(sync: true);

            final bool wasManualStop = call.arguments['manual'] ?? false;
            if (wasManualStop) {
              _isManuallyStopped = true;
            }

            _isFocusActive = false;
            _isPaused = false;
            _isManuallyStopped = false;
            _focusElapsedSeconds = 0;
          } else {
            // RUNNING
            _isFocusActive = true;
            _focusElapsedSeconds = elapsed;
            if (_activeTaskId == null && task.isNotEmpty) {
              _lastGoal = task;
              _activeTaskId = call.arguments['taskId'];
            }
          }

          if (_currentSessionStart == null && _isFocusActive) {
            _currentSessionStart = DateTime.now();
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

    // If loaded day is different from today, RESET local counts
    final todayStr = _todayKey();
    final storedDay = prefs.getString('last_commited_day') ?? todayStr;

    _studySeconds = prefs.getInt('study_seconds_$todayStr') ?? 0;
    _distractedSeconds = prefs.getInt('distracted_seconds_$todayStr') ?? 0;

    // Load detailed stats
    final hourlyJson = prefs.getString('hourly_seconds_$todayStr');
    if (hourlyJson != null) {
      try {
        _hourlyStudySeconds = List<int>.from(jsonDecode(hourlyJson));
      } catch (_) {
        _hourlyStudySeconds = List.filled(24, 0);
      }
    } else {
      _hourlyStudySeconds = List.filled(24, 0);
    }

    final taskJson = prefs.getString('task_seconds_$todayStr');
    if (taskJson != null) {
      try {
        _taskStudySeconds = Map<String, int>.from(jsonDecode(taskJson));
      } catch (_) {
        _taskStudySeconds = {};
      }
    } else {
      _taskStudySeconds = {};
    }

    final sessionJson = prefs.getString('focus_sessions_$todayStr');
    if (sessionJson != null) {
      try {
        _focusSessions = List<Map<String, dynamic>>.from(
          jsonDecode(sessionJson),
        );
      } catch (_) {
        _focusSessions = [];
      }
    } else {
      _focusSessions = [];
    }

    _lastGoal = prefs.getString('last_goal') ?? '';

    _timerMode = prefs.getString('timer_mode') ?? 'countdown';
    _customDurationSeconds = prefs.getInt('custom_duration_seconds') ?? 25 * 60;
    _isFullScreen = prefs.getBool('timer_fullscreen') ?? false;

    _doubleTapLockScreen = prefs.getBool('double_tap_lock_screen') ?? false;
    _doubleTapOpenDrawer = prefs.getBool('double_tap_open_drawer') ?? false;

    _vibrationEnabled = prefs.getBool('pomo_vibration') ?? true;
    _soundEnabled = prefs.getBool('pomo_sound') ?? true;

    await loadWeeklyData();
    notifyListeners();

    try {
      final Map<dynamic, dynamic>? nativeState = await _channel.invokeMethod(
        'getFocusState',
      );
      if (nativeState != null) {
        _isFocusActive = true;
        _focusElapsedSeconds = nativeState['elapsedSeconds'] ?? 0;
        _lastGoal = nativeState['taskName'] ?? _lastGoal;
        _activeTaskId = nativeState['taskId'] ?? _activeTaskId;
      }
    } catch (_) {}

    await checkDefaultLauncher();

    // Try to fetch user profile silently (works offline - uses cache)
    await fetchUserProfile();
    await updateAIHeadline();

    // Kill any persistent native monitoring and blocking from a prior session.
    // This ensures the app does NOT silently block apps like Instagram
    // even if a pomodoro was previously running (hidden hard lock).
    try {
      await _channel.invokeMethod('stopMonitoring');
      await _channel.invokeMethod('stopDailyMonitoring');
      await _channel.invokeMethod('configureBlockingRules', {
        'blockedPackages': <String>[],
        'dailyLimits': <String, int>{},
        'blockFirstShort': false,
        'restrictedKeywords': <String>[],
        'emergencyUseMaxCounts': <String, int>{},
      });
      await toggleVpn(false);
      await toggleSystemGrayscale(false);
    } catch (e) {
      debugPrint("Error clearing native blocker on startup: $e");
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

  void _checkMidnightReset() async {
    final today = _todayKey();
    if (_lastCommitedDay != today && _lastCommitedDay.isNotEmpty) {
      debugPrint(
        "Midnight transition detected! Committing old day: $_lastCommitedDay",
      );
      // 1. Commit whatever was pending for the OLD day
      await _commitFocusProgress(sync: true);

      // 2. Reset everything for the NEW day
      _studySeconds = 0;
      _distractedSeconds = 0;
      _hourlyStudySeconds = List.filled(24, 0);
      _taskStudySeconds = {};
      _focusSessions = [];
      _lastCommitedDay = today;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_commited_day', today);
      await _saveLocalStats();
      notifyListeners();
    }
  }

  Future<void> _commitFocusProgress({bool sync = false}) async {
    if (_focusPendingSeconds <= 0) {
      if (sync && (await ApiService.getToken()) != null) {
        await _syncStatsToBackend();
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final todayStr = _todayKey();

    final todayStored = prefs.getInt('study_seconds_$todayStr') ?? 0;
    if (todayStored != _studySeconds && _studySeconds > 0) {
      bool foundDay = false;
      for (int d = 1; d <= 3; d++) {
        final past = DateTime.now().subtract(Duration(days: d));
        final pastKey =
            '${past.year}-${past.month.toString().padLeft(2, '0')}-${past.day.toString().padLeft(2, '0')}';
        final pastVal = prefs.getInt('study_seconds_$pastKey') ?? 0;
        if (pastVal == _studySeconds) {
          foundDay = true;
          break;
        }
      }

      if (!foundDay) {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final yesterdayKey =
            '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
        await prefs.setInt('study_seconds_$yesterdayKey', _studySeconds);
      }

      _studySeconds = todayStored;
    }

    _studySeconds += _focusPendingSeconds;
    final taskSeconds = _focusPendingSeconds;

    if (_currentSessionStart != null && taskSeconds > 0) {
      final now = DateTime.now();
      _focusSessions.add({
        'startTime': _currentSessionStart!.toIso8601String(),
        'endTime': now.toIso8601String(),
        'actualSeconds': taskSeconds,
        'taskId': _activeTaskId,
        'title': _lastGoal,
      });

      if (_isFocusActive) {
        _currentSessionStart = now;
      } else {
        _currentSessionStart = null;
      }
    }

    _focusPendingSeconds = 0;
    _focusDirty = true;

    if (_activeTaskId != null && taskSeconds > 0) {
      _attributeSecondsToTask(_activeTaskId, taskSeconds);
    }

    await _saveLocalStats();
    if (sync) {
      await _syncStatsToBackend();
    }
    _focusDirty = false;
  }

  Future<void> _saveLocalStats() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _todayKey();
    await prefs.setInt('study_seconds_$todayStr', _studySeconds);
    await prefs.setInt('distracted_seconds_$todayStr', _distractedSeconds);
    await prefs.setString(
      'hourly_seconds_$todayStr',
      jsonEncode(_hourlyStudySeconds),
    );
    await prefs.setString(
      'task_seconds_$todayStr',
      jsonEncode(_taskStudySeconds),
    );
    await prefs.setString(
      'focus_sessions_$todayStr',
      jsonEncode(_focusSessions),
    );
    await prefs.setString('last_goal', _lastGoal);
    await prefs.setString('last_commited_day', _lastCommitedDay);
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
      if (_isFocusActive && _distractionApps.contains(packageName)) {
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
    final now = DateTime.now();

    // Throttle native checks to at most once every 5 minutes
    // OR if permissions were previously missing (to auto-detect grant)
    final bool shouldCheckNative =
        _lastPermissionCheck == null ||
        now.difference(_lastPermissionCheck!).inMinutes >= 5 ||
        !_isDefaultLauncher; // Always check if not default yet

    if (shouldCheckNative) {
      debugPrint("Performance: Running throttled native permission checks");
      await _channel.invokeMethod('hasUsageAccessPermission');
      await checkDefaultLauncher();
      _lastPermissionCheck = now;
    } else {
      debugPrint("Performance: Throttling native permission checks");
    }

    // ALWAYS stop distraction timer on resume to ensure state consistency
    await stopDistractionTimer();

    if (_exitTime != null && _lastLaunchedPackage != null) {
      final now = DateTime.now();
      final elapsed = now.difference(_exitTime!).inSeconds;
      if (elapsed <= 0) {
        _lastLaunchedPackage = null;
        _exitTime = null;
        return;
      }

      // Check if the day has crossed since the user left the launcher.
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

          // Bucketing for handleResume
          final hour = DateTime.now().hour;
          _hourlyStudySeconds[hour] += elapsed;

          _focusSessions.add({
            'startTime': _exitTime!.toIso8601String(),
            'endTime': DateTime.now().toIso8601String(),
            'actualSeconds': elapsed,
            'taskId': _activeTaskId,
            'title': _activeTaskId != null
                ? (_plannerService?.getTaskById(_activeTaskId!)?.title ??
                      'Task')
                : (_studyApps.contains(_lastLaunchedPackage)
                      ? (_allApps.firstWhere(
                              (a) => a['packageName'] == _lastLaunchedPackage,
                              orElse: () => const {},
                            )['name'] ??
                            'App')
                      : "Focus"),
            'isBreak': false,
          });
        } else if (_distractionApps.contains(_lastLaunchedPackage)) {
          _distractedSeconds += elapsed;
        } else {
          if (_isFocusActive) {
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
        } else if (_isFocusActive) {
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
          _isFocusActive ? 'Focusing ⚡' : 'Idle',
          _isFocusActive,
        );
      } catch (_) {
        await OfflineSyncService.instance.queueStatusUpdate(
          _isFocusActive ? 'Focusing ⚡' : 'Idle',
          _isFocusActive,
        );
      }

      // Throttle backend sync to at most once every 10 minutes
      // unless significant time was spent (handled by syncStatsToBackend internally or here)
      final bool significantActivity = elapsed > 60;
      final bool shouldSync =
          _lastSyncTime == null ||
          now.difference(_lastSyncTime!).inMinutes >= 10 ||
          significantActivity;

      if (shouldSync) {
        debugPrint(
          "Performance: Syncing stats to backend (activity: $elapsed sec)",
        );
        await _syncStatsToBackend();
      } else {
        debugPrint("Performance: Throttling backend sync");
      }
      notifyListeners();
    }
  }

  Future<void> syncStats() async {
    await _syncStatsToBackend();
  }

  Future<void> _syncStatsToBackend() async {
    final today = _todayKey();
    final token = await ApiService.getToken();
    if (token != null) {
      try {
        await ApiService.syncActivity(
          today,
          _studySeconds,
          _distractedSeconds,
          hourly: _hourlyStudySeconds,
          taskAnalytics: _taskStudySeconds.entries.map((e) {
            final task = _plannerService?.getTaskById(e.key);
            return {
              'taskId': e.key,
              'title': task?.title ?? 'Task',
              'seconds': e.value,
            };
          }).toList(),
          sessions: _focusSessions,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_sync_date', today);
        _lastSyncTime = DateTime.now();

        // Throttle profile fetch and AI headlines to once an hour
        final bool shouldFetchProfile =
            _lastProfileFetch == null ||
            _lastSyncTime!.difference(_lastProfileFetch!).inHours >= 1;

        if (shouldFetchProfile) {
          debugPrint("Performance: Fetching profile and AI headline");
          await fetchUserProfile();
          await updateAIHeadline();
          _lastProfileFetch = _lastSyncTime;
        }
      } catch (e) {
        debugPrint("Failed to sync stats to backend: $e");
        await OfflineSyncService.instance.queueActivitySync(
          today,
          _studySeconds,
          _distractedSeconds,
        );
      }
    }
  }

  Future<void> setTargetGoal(String goal) async {
    _lastGoal = goal;
    await OfflineSyncService.instance.cacheGoal(goal);
    notifyListeners();

    try {
      await ApiService.updateGoal(goal);
      await updateAIHeadline();
    } catch (_) {
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
        await OfflineSyncService.instance.cacheGoal(_lastGoal);
      }

      if (isParent) {
        await fetchLinkedStudents();
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
      _userProfile = await OfflineSyncService.instance.getCachedProfile();
      final cachedGoal = await OfflineSyncService.instance.getCachedGoal();
      if (cachedGoal.isNotEmpty) {
        _lastGoal = cachedGoal;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchLinkedStudents() async {
    try {
      final students = await ApiService.getLinkedStudents();
      _linkedStudents = students;
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching linked students: $e");
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

  void startFocusTimer() async {
    if (_isFocusActive) return;

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

    // Demand battery unrestricted mode via a sweet, clear dialog.
    // The user must manually set it or explicitly choose to continue without it.
    final batteryOk = await BatteryOptimizationDialog.showIfNeeded();
    
    if (!batteryOk) {
      // User chose "Continue anyway" - allow them to proceed
    }
    
    await checkBatteryOptimizationStatus();
    if (!_isBatteryOptimizationIgnored) {
      _showBatteryPrompt = true;
      notifyListeners();
      return;
    }

    _isFocusActive = true;
    _isManuallyStopped = false;

    _focusElapsedSeconds = 0;
    _focusPendingSeconds = 0;
    _focusDirty = false;

    await _channel.invokeMethod('startFocusTimer', {
      'taskName': _lastGoal.isNotEmpty ? _lastGoal : "Focus Session",
      'taskId': _activeTaskId,
      'soundEnabled': _soundEnabled,
      'vibrationEnabled': _vibrationEnabled,
    });

    await ApiService.updateStatus('Focusing ⚡', true);
    await _saveTimerPreferences();
    notifyListeners();
  }

  void stopFocusTimer({bool manual = false}) async {
    _isFocusActive = false;
    _isPaused = false;
    _isManuallyStopped = manual;

    await _channel.invokeMethod('stopFocusTimer');
    await ApiService.updateStatus('Idle', false);
    await _commitFocusProgress(sync: true);
    notifyListeners();
  }

  void pauseFocusTimer() async {
    if (!_isFocusActive) return;

    _isPaused = true;
    await _channel.invokeMethod('stopFocusTimer');
    notifyListeners();
  }

  void resumeFocusTimer() async {
    if (!_isPaused) return;

    final hasPermission = await checkUsagePermission();
    if (!hasPermission) {
      await toggleUsagePermission();
      return;
    }

    _isPaused = false;

    await _channel.invokeMethod('startFocusTimer', {
      'taskName': _lastGoal.isNotEmpty ? _lastGoal : "Focus Session",
      'taskId': _activeTaskId,
      'elapsedSeconds': _focusElapsedSeconds,
    });

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

  /// Skip the default launcher requirement. Saves to SharedPreferences so the
  /// user won't be prompted again on subsequent launches.
  Future<void> skipDefaultLauncher() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('launcher_skip_default', true);
    _skipDefaultLauncher = true;
    notifyListeners();
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
    required Map<String, bool> allowOneShort,
    required Set<String> restrictedKeywords,
    Map<String, int>? emergencyUseMaxCounts,
    List<String> shortsBlockEnabledPackages = const [],
  }) async {
    try {
      await _channel.invokeMethod('configureBlockingRules', {
        'blockedPackages': blockedPackages.toList(),
        'dailyLimits': dailyLimits,
        'allowOneShort': allowOneShort,
        'restrictedKeywords': restrictedKeywords.toList(),
        'emergencyUseMaxCounts': emergencyUseMaxCounts ?? <String, int>{},
        'shortsBlockEnabledPackages': shortsBlockEnabledPackages,
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
    _userProfile = await OfflineSyncService.instance.getCachedProfile();
    final goal = await OfflineSyncService.instance.getCachedGoal();
    if (goal.isNotEmpty) _lastGoal = goal;

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

  // Optional reference to TaskPlannerService for syncing pomodoro counts
  TaskPlannerService? _plannerService;
  TaskPlannerService? get planner => _plannerService;
  void attachPlanner(TaskPlannerService planner) {
    _plannerService = planner;
  }

  // ── Pomodoro Settings ──
  bool _autoStartNextPomodoro = false;
  bool _autoStartBreak = false;
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;

  bool get autoStartNextPomodoro => _autoStartNextPomodoro;
  bool get autoStartBreak => _autoStartBreak;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get soundEnabled => _soundEnabled;

  Future<void> setVibrationEnabled(bool val) async {
    _vibrationEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pomo_vibration', val);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool val) async {
    _soundEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pomo_sound', val);
    notifyListeners();
  }

  // --- Task Engine ---
  List<Map<String, dynamic>> get tasks {
    if (_plannerService == null) return [];
    return _plannerService!.tasks
        .map(
          (t) => {
            'id': t.id,
            'title': t.title,
            'isDone': t.isCompleted,
            'focusSeconds': t.focusSeconds,
            'isRecurring': t.isRecurring,
          },
        )
        .toList();
  }

  Map<String, dynamic>? get activeTask {
    if (_activeTaskId == null || _plannerService == null) return null;
    try {
      final t = _plannerService!.tasks.firstWhere(
        (element) => element.id == _activeTaskId,
      );
      return {
        'id': t.id,
        'title': t.title,
        'isDone': t.isCompleted,
        'focusSeconds': t.focusSeconds,
        'isRecurring': t.isRecurring,
      };
    } catch (_) {
      return null;
    }
  }

  void _attributeSecondsToTask(String? taskId, int seconds, {bool persist = true}) {
    if (taskId == null || seconds <= 0 || _plannerService == null) return;
    _plannerService!.addFocusSeconds(taskId, seconds, persist: persist);

    // Also track for today's specific analytics record
    _taskStudySeconds[taskId] = (_taskStudySeconds[taskId] ?? 0) + seconds;
  }

  Future<void> addTask(
    String title, {
    bool isRecurring = false,
    int durationMinutes = 60,
  }) async {
    if (_plannerService == null) return;
    final task = TimeBlockTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      startTime: DateTime.now(),
      durationMinutes: durationMinutes,
      isRecurring: isRecurring,
      recurringDays: isRecurring ? [1, 2, 3, 4, 5, 6, 7] : [],
    );
    await _plannerService!.addTask(task);
  }

  Future<void> deleteTask(String taskId) async {
    if (_plannerService == null) return;
    await _plannerService!.removeTask(taskId);
    if (_activeTaskId == taskId) _activeTaskId = null;
  }

  Future<void> toggleTaskComplete(String taskId) async {
    if (_plannerService == null) return;
    await _plannerService!.toggleComplete(taskId);
    await _syncStatsToBackend();
  }

  Future<void> toggleTaskRecurring(String taskId) async {
    if (_plannerService == null) return;
    final idx = _plannerService!.tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final t = _plannerService!.tasks[idx];
      final updated = t.copyWith(
        isRecurring: !t.isRecurring,
        recurringDays: !t.isRecurring ? [1, 2, 3, 4, 5, 6, 7] : [],
      );
      await _plannerService!.updateTask(updated);
    }
  }

  Future<void> modifyTask(String taskId, String newTitle) async {
    if (_plannerService == null) return;
    final idx = _plannerService!.tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final updated = _plannerService!.tasks[idx].copyWith(title: newTitle);
      await _plannerService!.updateTask(updated);
    }
  }

  void setActiveTask(String? taskId) {
    _activeTaskId = taskId;
    _lastTaskActivityTime = DateTime.now();
    notifyListeners();
  }

  void switchActiveTask(String? newTaskId, {String? taskName}) {
    if (_isFocusActive) {
      // Force immediate commit of ALL pending focus time to the current task
      // before switching. This ensures precise per-task tracking even when
      // the user rapidly switches between tasks.
      final pending = _focusPendingSeconds;
      if (pending > 0) {
        _attributeSecondsToTask(_activeTaskId, pending);
        _studySeconds += pending;
        _focusPendingSeconds = 0;
        _saveLocalStats();
      }
      // Also commit any elapsed seconds from the native timer that haven't
      // been accounted for yet (the onFocusTick may have missed a tick)
      if (_focusElapsedSeconds > 0) {
        final unaccounted =
            _focusElapsedSeconds - _focusPendingSeconds - _studySeconds;
        if (unaccounted > 0) {
          _attributeSecondsToTask(_activeTaskId, unaccounted);
          _studySeconds += unaccounted;
          _saveLocalStats();
        }
      }
    }
    _activeTaskId = newTaskId;
    _lastTaskActivityTime = DateTime.now();

    // Always set _lastGoal regardless of pomodoro state so that
    // when startPomodoro() is called later it has the correct task name.
    String newTaskName = "Focus Session";
    if (taskName != null) {
      newTaskName = taskName;
    } else if (newTaskId != null && _plannerService != null) {
      try {
        newTaskName = _plannerService!.tasks
            .firstWhere((t) => t.id == newTaskId)
            .title;
      } catch (_) {}
    }
    _lastGoal = newTaskName;
    _saveLocalStats();

    if (_isFocusActive) {
      // Update native overlay task name and refresh its UI
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
    required bool blockYoutubeShorts,
    required bool blockInstagramReels,
    required bool allowOneYoutubeShort,
    required bool allowOneInstagramReel,
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
      blockYoutubeShorts: blockYoutubeShorts,
      blockInstagramReels: blockInstagramReels,
      allowOneYoutubeShort: allowOneYoutubeShort,
      allowOneInstagramReel: allowOneInstagramReel,
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
    final allowOneShortMap = <String, bool>{};

    if (blockYoutubeShorts) {
      for (final app in _allApps) {
        final name = (app['name'] ?? '').toLowerCase().trim();
        if (name.contains('youtube')) {
          blockedPackageNames.add(app['packageName']!);
          allowOneShortMap[app['packageName']!] = allowOneYoutubeShort;
        }
      }
    }
    if (blockInstagramReels) {
      for (final app in _allApps) {
        final name = (app['name'] ?? '').toLowerCase().trim();
        if (name.contains('instagram')) {
          blockedPackageNames.add(app['packageName']!);
          allowOneShortMap[app['packageName']!] = allowOneInstagramReel;
        }
      }
    }

    // Fallback for tiktok/facebook if any block is enabled (legacy support)
    if (blockYoutubeShorts || blockInstagramReels) {
      for (final app in _allApps) {
        final name = (app['name'] ?? '').toLowerCase().trim();
        if (name.contains('tiktok') || name.contains('facebook')) {
          blockedPackageNames.add(app['packageName']!);
          allowOneShortMap[app['packageName']!] =
              false; // default to block completely
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

    // Build list of packages for Reels/Shorts blocker specifically
    final shortsBlockEnabledPackages = <String>[];
    if (blockYoutubeShorts) {
      for (final app in _allApps) {
        if ((app['name'] ?? '').toLowerCase().contains('youtube')) {
          shortsBlockEnabledPackages.add(app['packageName']!);
        }
      }
    }
    if (blockInstagramReels) {
      for (final app in _allApps) {
        if ((app['name'] ?? '').toLowerCase().contains('instagram')) {
          shortsBlockEnabledPackages.add(app['packageName']!);
        }
      }
    }

    await configureBlockingRules(
      blockedPackages: blockedPackageNames,
      dailyLimits: dailyLimitsMap,
      allowOneShort: allowOneShortMap,
      restrictedKeywords: restrictedKeywords.toSet(),
      emergencyUseMaxCounts: emergencyUseMaxMap,
      shortsBlockEnabledPackages: shortsBlockEnabledPackages,
    );

    // Restart daily monitoring to apply new limits
    await stopDailyMonitoring();
    await startDailyMonitoring();

    await toggleVpn(vpnContentFilterEnabled);
    await toggleSystemGrayscale(monochromeModeEnabled);
    notifyListeners();
  }

  // ── Battery Optimization ──

  Future<void> checkBatteryOptimizationStatus() async {
    try {
      final ignored =
          await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored') ??
          true;
      _isBatteryOptimizationIgnored = ignored;
      if (!ignored) {
        _showBatteryPrompt = true;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      _showBatteryPrompt = false;
      notifyListeners();
      // Check again after a delay
      Future.delayed(
        const Duration(seconds: 5),
        checkBatteryOptimizationStatus,
      );
    } catch (_) {}
  }

  void dismissBatteryPrompt() {
    _showBatteryPrompt = false;
    notifyListeners();
  }

  // ── Permissions ──

  Future<bool> hasUsageAccessPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccessPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestUsageAccessPermission() async {
    try {
      await _channel.invokeMethod('requestUsageAccessPermission');
    } catch (_) {}
  }

  Future<bool> hasWriteSecureSettingsPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'hasWriteSecureSettingsPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ── Accessibility Service ──

  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isAccessibilityServiceEnabled',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }
}
