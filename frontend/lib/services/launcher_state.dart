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

  // Stats – these track TODAY only (loaded/saved per-day key)
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
  // Date key when the current pomodoro session started (for cross-day splitting)
  String _pomodoroSessionDateKey = '';

  // Pending seconds track time since last commit. These all belong to the current day.
  int _pomodoroPendingFocusSeconds = 0;
  int _pomodoroPendingTaskSeconds = 0;
  bool _pomodoroDirty = false;
  Timer? _pomodoroTimer;

  // New detailed analytics tracking
  List<int> _hourlyStudySeconds = List.filled(24, 0);
  Map<String, int> _taskStudySeconds = {};
  List<Map<String, dynamic>> _pomoSessions = [];

  // Track current session details
  DateTime? _currentSessionStart;
  int? _currentSessionDefinedSeconds;

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

  // NO MORE LOCAL _tasks. We use _plannerService exclusively.

  String? _activeTaskId;
  String? get activeTaskId => _activeTaskId;

  DateTime _lastTaskActivityTime = DateTime.now();

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

    // Once-a-day backend sync
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString('last_sync_date') != today) {
      _syncStatsToBackend();
      // Handle midnight shift: reset local study/distract seconds
      _studySeconds = 0;
      _distractedSeconds = 0;
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
        case 'onPomodoroTick':
          _pomodoroSecondsRemaining = call.arguments['secondsRemaining'] ?? 0;
          final bool isBreakVal = call.arguments['isBreak'] ?? false;
          _isBreak = isBreakVal;
          // Each tick = 1 second of focus time. Track as pending.
          if (_isPomodoroActive && !_isBreak) {
            _pomodoroPendingFocusSeconds += 1;
            _pomodoroPendingTaskSeconds += 1;
            _pomodoroDirty = true;

            // Increment hourly bucket
            final hour = DateTime.now().hour;
            _hourlyStudySeconds[hour] += 1;
          }
          notifyListeners();
          break;
        case 'onPomodoroStateChanged':
          final String status = call.arguments['status'] ?? "STOPPED";
          final int seconds = call.arguments['secondsRemaining'] ?? 0;
          final bool isBreakVal = call.arguments['isBreak'] ?? false;
          final String task = call.arguments['taskName'] ?? "";

          if (status == "STOPPED") {
            final double sessionDuration = _pomodoroTotalDurationSeconds
                .toDouble();
            final bool wasBreak = _isBreak;

            await _commitPomodoroProgress(sync: true);

            if (!wasBreak) {
              _incrementActiveTaskPomodoro();
              // Logic Check: Pomodoro finished
              if (_autoStartBreak) {
                // Wait briefly then start break
                Future.delayed(const Duration(milliseconds: 500), () {
                  startBreak();
                });
              } else if (_autoStartNextPomodoro) {
                // Skip break, start next pomodoro
                Future.delayed(const Duration(milliseconds: 500), () {
                  startPomodoro();
                });
              }
            } else {
              // Break finished
              if (_autoStartNextPomodoro) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  startPomodoro();
                });
              }
            }

            _isPomodoroActive = false;
            _pomodoroTotalDurationSeconds = _customDurationSeconds;
            _pomodoroSessionDateKey = '';

            // Play alert sound if enabled
            if (_soundEnabled) {
              _playAlertSound();
            }
          } else if (status == "BREAK") {
            if (!_isBreak && isBreakVal) {
              await _commitPomodoroProgress(sync: true);
              _incrementActiveTaskPomodoro();
            }
            _isPomodoroActive = true;
            _isBreak = isBreakVal;
            _pomodoroSecondsRemaining = seconds;
            _pomodoroTotalDurationSeconds = 5 * 60;
          } else {
            // FOCUSING / any other status
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

              if (_currentSessionStart == null) {
                _currentSessionStart = DateTime.now();
                _currentSessionDefinedSeconds = _pomodoroTotalDurationSeconds;
              }
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

    final sessionJson = prefs.getString('pomo_sessions_$todayStr');
    if (sessionJson != null) {
      try {
        _pomoSessions = List<Map<String, dynamic>>.from(
          jsonDecode(sessionJson),
        );
      } catch (_) {
        _pomoSessions = [];
      }
    } else {
      _pomoSessions = [];
    }

    _lastGoal = prefs.getString('last_goal') ?? '';

    _timerMode = prefs.getString('timer_mode') ?? 'countdown';
    _customDurationSeconds = prefs.getInt('custom_duration_seconds') ?? 25 * 60;
    _isFullScreen = prefs.getBool('timer_fullscreen') ?? false;

    _doubleTapLockScreen = prefs.getBool('double_tap_lock_screen') ?? false;
    _doubleTapOpenDrawer = prefs.getBool('double_tap_open_drawer') ?? false;

    _autoStartNextPomodoro = prefs.getBool('pomo_auto_start_next') ?? false;
    _autoStartBreak = prefs.getBool('pomo_auto_start_break') ?? false;
    _vibrationEnabled = prefs.getBool('pomo_vibration') ?? true;
    _soundEnabled = prefs.getBool('pomo_sound') ?? true;

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

  Future<void> _commitPomodoroProgress({bool sync = false}) async {
    if (_pomodoroPendingFocusSeconds <= 0) {
      if (sync && (await ApiService.getToken()) != null) {
        await _syncStatsToBackend();
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final todayStr = _todayKey();

    // CRITICAL FIX: Before adding pending seconds to _studySeconds, ensure
    // _studySeconds belongs to TODAY. If it was loaded from a previous day
    // (e.g., pomodoro crossed midnight), save it to its original day first,
    // then reload today's value.
    // We track which date _studySeconds was last loaded for by checking
    // the stored value against today's key. If _studySeconds was not yet
    // saved/loaded for today, save it out to the old key first.
    // Compare today's stored value vs _studySeconds to detect day drift.
    final todayStored = prefs.getInt('study_seconds_$todayStr') ?? 0;
    if (todayStored != _studySeconds && _studySeconds > 0) {
      // _studySeconds does NOT match today's stored value. This means
      // _studySeconds still has yesterday's (or an earlier day's) value.
      // The pending seconds we're about to commit are from TODAY (the
      // current tick time). We need to:
      // 1. Save _studySeconds to whatever day it belonged to (we find it
      //    by scanning back a few days to find a match)
      // 2. Reload today's value into _studySeconds
      // 3. Add pending (today's time) to today's _studySeconds

      // Try to find which day _studySeconds matches in storage (last 3 days)
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

      // If we can't match, just save _studySeconds to yesterday to be safe
      if (!foundDay) {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final yesterdayKey =
            '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
        await prefs.setInt('study_seconds_$yesterdayKey', _studySeconds);
      }

      // Now reload today's stats
      _studySeconds = todayStored;
    }

    // Now _studySeconds definitely belongs to today. Add pending (today's time).
    _studySeconds += _pomodoroPendingFocusSeconds;
    final taskSeconds = _pomodoroPendingTaskSeconds;

    if (_currentSessionStart != null && taskSeconds > 0) {
      final now = DateTime.now();
      _pomoSessions.add({
        'startTime': _currentSessionStart!.toIso8601String(),
        'endTime': now.toIso8601String(),
        'definedSeconds':
            _currentSessionDefinedSeconds ?? _pomodoroTotalDurationSeconds,
        'actualSeconds': taskSeconds,
        'taskId': _activeTaskId,
        'title': _lastGoal,
        'isBreak': _isBreak,
      });
      _currentSessionStart = null;
      _currentSessionDefinedSeconds = null;
    }

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
    await prefs.setString(
      'hourly_seconds_$todayStr',
      jsonEncode(_hourlyStudySeconds),
    );
    await prefs.setString(
      'task_seconds_$todayStr',
      jsonEncode(_taskStudySeconds),
    );
    await prefs.setString('pomo_sessions_$todayStr', jsonEncode(_pomoSessions));
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

          _pomoSessions.add({
            'startTime': _exitTime!.toIso8601String(),
            'endTime': DateTime.now().toIso8601String(),
            'definedSeconds': elapsed,
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
          sessions: _pomoSessions,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_sync_date', today);

        await fetchUserProfile();
        await updateAIHeadline();
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
    _pomodoroPendingFocusSeconds = 0;
    _pomodoroPendingTaskSeconds = 0;
    _pomodoroDirty = false;
    _pomodoroSessionDateKey = _todayKey();

    // NOTE: No startMonitoring() call — we intentionally removed the native
    // app-blocking hard lock. Pomodoro is a soft focus timer only; it does
    // NOT forcefully block apps on the native side.

    await _channel.invokeMethod('startPomodoro', {
      'taskName': _lastGoal.isNotEmpty ? _lastGoal : "Focus Session",
      'durationSeconds': _customDurationSeconds,
      'isBreak': false,
      'timerMode': _timerMode,
      'autoStartBreak': _autoStartBreak,
      'autoStartNextPomodoro': _autoStartNextPomodoro,
      'soundEnabled': _soundEnabled,
      'vibrationEnabled': _vibrationEnabled,
    });

    await ApiService.updateStatus('Focusing (Pomodoro) ⚡', true);
    await _saveTimerPreferences();
    notifyListeners();
  }

  void startBreak() async {
    _isPomodoroActive = true;
    _isBreak = true;
    _pomodoroSecondsRemaining = 5 * 60; // Standard 5 min break
    _pomodoroTotalDurationSeconds = 5 * 60;

    await _channel.invokeMethod('startPomodoro', {
      'taskName': "Break Time",
      'durationSeconds': 5 * 60,
      'isBreak': true,
      'timerMode': 'countdown',
      'soundEnabled': _soundEnabled,
      'vibrationEnabled': _vibrationEnabled,
    });

    notifyListeners();
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  void _playAlertSound() async {
    try {
      await _audioPlayer.play(AssetSource('alert.mp3'));
      Future.delayed(const Duration(seconds: 3), () {
        _audioPlayer.stop();
      });
    } catch (e) {
      debugPrint("Error playing alert sound: $e");
    }
  }

  void stopPomodoro({bool manual = false}) async {
    _isPomodoroActive = false;

    if (manual) {
      _autoStartNextPomodoro = false;
      _autoStartBreak = false;
      await _saveTimerPreferences();
    }
    // Note: No stopMonitoring() call needed here because startPomodoro()
    // no longer starts native monitoring (hard lock was removed).
    await _channel.invokeMethod('stopPomodoro');

    await ApiService.updateStatus('Idle', false);

    await _commitPomodoroProgress(sync: true);
    _pomodoroSessionDateKey = '';
    notifyListeners();
  }

  /// Pause the pomodoro timer without committing progress or stopping monitoring.
  /// Saves remaining seconds so resume can pick up from where it left off.
  void pausePomodoro() async {
    if (!_isPomodoroActive) return;

    // Save remaining seconds before stopping native timer
    final savedSeconds = _pomodoroSecondsRemaining;
    final savedDuration = _pomodoroTotalDurationSeconds;

    await _channel.invokeMethod('stopPomodoro');

    // Keep isPomodoroActive true, just mark as not running
    _pomodoroSecondsRemaining = savedSeconds;
    _pomodoroTotalDurationSeconds = savedDuration;
    notifyListeners();
  }

  /// Resume a paused pomodoro timer from where it left off
  void resumePomodoro() async {
    if (_isPomodoroActive) return; // already running

    final hasPermission = await checkUsagePermission();
    if (!hasPermission) {
      await toggleUsagePermission();
      return;
    }

    _isPomodoroActive = true;
    _isBreak = false;

    await _channel.invokeMethod('startPomodoro', {
      'taskName': _lastGoal.isNotEmpty ? _lastGoal : "Focus Session",
      'durationSeconds': _pomodoroSecondsRemaining,
      'isBreak': false,
      'timerMode': _timerMode,
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

  Future<void> setAutoStartNextPomodoro(bool val) async {
    _autoStartNextPomodoro = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pomo_auto_start_next', val);
    notifyListeners();
  }

  Future<void> setAutoStartBreak(bool val) async {
    _autoStartBreak = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pomo_auto_start_break', val);
    notifyListeners();
  }

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
    // Map TimeBlockTask to the old Map format for compatibility with existing UI
    return _plannerService!.tasks
        .map(
          (t) => {
            'id': t.id,
            'title': t.title,
            'isDone': t.isCompleted,
            'focusSeconds': t.focusSeconds,
            'completedPomodoroCount': t.completedPomodoros,
            'estimatedPomodoros': t.estimatedPomodoros,
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
        'completedPomodoroCount': t.completedPomodoros,
        'estimatedPomodoros': t.estimatedPomodoros,
        'isRecurring': t.isRecurring,
      };
    } catch (_) {
      return null;
    }
  }

  void _attributeSecondsToTask(String? taskId, int seconds) {
    if (taskId == null || seconds <= 0 || _plannerService == null) return;
    _plannerService!.addFocusSeconds(taskId, seconds);

    // Also track for today's specific analytics record
    _taskStudySeconds[taskId] = (_taskStudySeconds[taskId] ?? 0) + seconds;
  }

  void _incrementActiveTaskPomodoro() {
    if (_activeTaskId == null || _plannerService == null) return;
    _plannerService!.incrementPomodoro(_activeTaskId!);
  }

  Future<void> addTask(
    String title, {
    bool isRecurring = false,
    int estimatedPomodoros = 1,
  }) async {
    if (_plannerService == null) return;
    final task = TimeBlockTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      startTime: DateTime.now(),
      estimatedPomodoros: estimatedPomodoros,
      isRecurring: isRecurring,
      recurringDays: isRecurring ? [1, 2, 3, 4, 5, 6, 7] : [],
    );
    await _plannerService!.addTask(task);
  }

  Future<void> updateTaskEstimatedPomodoros(String taskId, int count) async {
    if (_plannerService == null) return;
    final idx = _plannerService!.tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final updated = _plannerService!.tasks[idx].copyWith(
        estimatedPomodoros: count.clamp(1, 99),
      );
      await _plannerService!.updateTask(updated);
    }
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
    if (_isPomodoroActive && !_isBreak) {
      // Attribute any pending focus time to the current task before switching
      final pending = _pomodoroPendingTaskSeconds;
      if (pending > 0) {
        _attributeSecondsToTask(_activeTaskId, pending);
        _studySeconds += pending;
        _pomodoroPendingFocusSeconds = 0;
        _pomodoroPendingTaskSeconds = 0;
        _saveLocalStats();
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

    if (_isPomodoroActive) {
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

  /// Public method for manual sync (pull-to-refresh)
  Future<void> syncStats() async {
    await _syncStatsToBackend();
    notifyListeners();
  }
}
