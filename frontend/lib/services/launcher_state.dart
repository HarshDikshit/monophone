import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class LauncherState extends ChangeNotifier {
  static const _channel = MethodChannel('com.dixit.monophone/launcher');

  // App lists
  List<Map<String, String>> _allApps = [];
  List<Map<String, String>> get allApps => _allApps;

  Set<String> _studyApps = {}; // Packages marked for Study
  Set<String> _distractionApps = {}; // Packages marked for Distraction

  Set<String> get studyApps => _studyApps;
  Set<String> get distractionApps => _distractionApps;

  // Stats
  int _studySeconds = 0;
  int _distractedSeconds = 0;
  int get studySeconds => _studySeconds;
  int get distractedSeconds => _distractedSeconds;

  String _lastGoal = '';
  String get lastGoal => _lastGoal;

  String _aiHeadline = 'Close distractions. Protect your attention.';
  String get aiHeadline => _aiHeadline;

  // Weekly chart data (past 7 days, keyed by 'YYYY-MM-DD')
  Map<String, int> _weeklyStudyData = {};
  Map<String, int> get weeklyStudyData => _weeklyStudyData;

  // Pomodoro
  bool _isPomodoroActive = false;
  bool _isBreak = false;
  int _pomodoroSecondsRemaining = 25 * 60;
  int _pomodoroAccountedSeconds =
      0; // Tracks seconds already logged during a running timer
  Timer? _pomodoroTimer;

  bool get isPomodoroActive => _isPomodoroActive;
  bool get isBreak => _isBreak;
  int get pomodoroSecondsRemaining => _pomodoroSecondsRemaining;

  // Study Tasks State (Focus To-Do)
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

  // Auth User
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Tracking launcher exit/resume
  String? _lastLaunchedPackage;
  DateTime? _exitTime;

  // Settings
  bool _doubleTapLockScreen = false;
  bool get doubleTapLockScreen => _doubleTapLockScreen;

  bool _doubleTapOpenDrawer = false;
  bool get doubleTapOpenDrawer => _doubleTapOpenDrawer;

  bool _isDefaultLauncher = false;
  bool get isDefaultLauncher => _isDefaultLauncher;

  LauncherState() {
    _loadLocalStats();
    refreshAppsList();
    _initMethodChannel();
  }

  void _initMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPomodoroTick':
          _pomodoroSecondsRemaining = call.arguments['secondsRemaining'] ?? 0;
          final bool isBreakVal = call.arguments['isBreak'] ?? false;
          _isBreak = isBreakVal;
          notifyListeners();
          break;
        case 'onPomodoroStateChanged':
          final String status = call.arguments['status'] ?? "STOPPED";
          final int seconds = call.arguments['secondsRemaining'] ?? 0;
          final bool isBreakVal = call.arguments['isBreak'] ?? false;
          final String task = call.arguments['taskName'] ?? "";
          final int elapsed = call.arguments['elapsedSeconds'] ?? 0;

          if (status == "STOPPED") {
            _isPomodoroActive = false;
            final newlyElapsed = elapsed - _pomodoroAccountedSeconds;
            if (newlyElapsed > 0) {
              _attributeSecondsToTask(_activeTaskId, newlyElapsed);
              _studySeconds += newlyElapsed;
              await _saveLocalStats();
              await _syncStatsToBackend();
            }
            _pomodoroAccountedSeconds = 0;
          } else if (status == "BREAK") {
            if (!_isBreak && isBreakVal) {
              _incrementActiveTaskPomodoro();
              final newlyElapsed = elapsed - _pomodoroAccountedSeconds;
              if (newlyElapsed > 0) {
                _attributeSecondsToTask(_activeTaskId, newlyElapsed);
                _studySeconds += newlyElapsed;
              }
              _pomodoroAccountedSeconds = 0; // reset for break or next cycle
              await _saveLocalStats();
              await _syncStatsToBackend();
            }
            _isPomodoroActive = true;
            _isBreak = isBreakVal;
            _pomodoroSecondsRemaining = seconds;
          } else {
            _isPomodoroActive = true;
            _isBreak = isBreakVal;
            _pomodoroSecondsRemaining = seconds;
            if (task.isNotEmpty) {
              _lastGoal = task;
            }
            _lastTaskActivityTime = DateTime.now();
          }
          notifyListeners();
          break;
        case 'onDefaultLauncherChanged':
          _isDefaultLauncher = call.arguments == true;
          notifyListeners();
          break;
      }
    });
  }

  // Load local preferences and stats
  Future<void> _loadLocalStats() async {
    final prefs = await SharedPreferences.getInstance();

    // Categorizations
    _studyApps = (prefs.getStringList('study_packages') ?? []).toSet();
    _distractionApps = (prefs.getStringList('distraction_packages') ?? [])
        .toSet();

    // Stats for today (keyed by date)
    final todayStr = _todayKey();
    _studySeconds = prefs.getInt('study_seconds_$todayStr') ?? 0;
    _distractedSeconds = prefs.getInt('distracted_seconds_$todayStr') ?? 0;
    _lastGoal = prefs.getString('last_goal') ?? '';

    // Load double tap settings
    _doubleTapLockScreen = prefs.getBool('double_tap_lock_screen') ?? false;
    _doubleTapOpenDrawer = prefs.getBool('double_tap_open_drawer') ?? false;

    await _loadTasks();
    await loadWeeklyData();
    notifyListeners();

    // Sync with running native Pomodoro service if any
    try {
      final Map<dynamic, dynamic>? nativeState = await _channel.invokeMethod(
        'getPomodoroState',
      );
      if (nativeState != null) {
        _isPomodoroActive = true;
        _pomodoroSecondsRemaining = nativeState['secondsRemaining'] ?? 0;
        _isBreak = nativeState['isBreak'] ?? false;
        _lastGoal = nativeState['taskName'] ?? _lastGoal;
      }
    } catch (_) {}

    await checkDefaultLauncher();

    // Initial fetch of profile and AI motivator if token exists
    final token = await ApiService.getToken();
    if (token != null) {
      await fetchUserProfile();
      await updateAIHeadline();
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Save stats
  Future<void> _saveLocalStats() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _todayKey();
    await prefs.setInt('study_seconds_$todayStr', _studySeconds);
    await prefs.setInt('distracted_seconds_$todayStr', _distractedSeconds);
    await prefs.setString('last_goal', _lastGoal);
    await loadWeeklyData();
  }

  // Set/Get apps from Native MethodChannel
  Future<void> refreshAppsList() async {
    try {
      final List<dynamic>? apps = await _channel.invokeMethod(
        'getInstalledApps',
      );
      if (apps != null) {
        _allApps = apps.map((app) => Map<String, String>.from(app)).toList();

        // Auto-categorise uncategorised apps as permitted/neutral if they are not distraction/study
        notifyListeners();
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to get apps: ${e.message}");
    }
  }

  // App Categorization
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

  // Launch App through native bridge
  Future<bool> launchApp(String packageName) async {
    try {
      // Check if blocked by Pomodoro
      if (_isPomodoroActive &&
          !_isBreak &&
          _distractionApps.contains(packageName)) {
        // App is blocked
        return false;
      }

      // Track exit
      _lastLaunchedPackage = packageName;
      _exitTime = DateTime.now();

      // Update real-time status to backend
      final appName = _allApps.firstWhere(
        (element) => element['packageName'] == packageName,
        orElse: () => {'name': 'App'},
      )['name'];
      final isStudy = _studyApps.contains(packageName);
      await ApiService.updateStatus(
        isStudy ? 'Studying ($appName)' : 'Using $appName 🛑',
        isStudy,
      );

      await _channel.invokeMethod('launchApp', {'packageName': packageName});
      return true;
    } on PlatformException catch (e) {
      debugPrint("Failed to launch app: ${e.message}");
      return false;
    }
  }

  // Lifecycle resume callback (to track study/distraction duration on return)
  Future<void> handleResume() async {
    // Check permission
    await _channel.invokeMethod('hasUsageAccessPermission');

    // Stop distraction timer service if active
    await stopDistractionTimer();
    await checkDefaultLauncher();

    if (_exitTime != null && _lastLaunchedPackage != null) {
      final now = DateTime.now();
      final elapsed = now.difference(_exitTime!).inSeconds;

      if (_studyApps.contains(_lastLaunchedPackage)) {
        _studySeconds += elapsed;
        _attributeSecondsToTask(_activeTaskId, elapsed);
      } else if (_distractionApps.contains(_lastLaunchedPackage)) {
        _distractedSeconds += elapsed;
      } else {
        // Neutral apps do not contribute to stats, or can count as study if in Pomodoro
        if (_isPomodoroActive && !_isBreak) {
          _studySeconds += elapsed;
          _attributeSecondsToTask(_activeTaskId, elapsed);
        }
      }

      await _saveLocalStats();

      // Reset
      _lastLaunchedPackage = null;
      _exitTime = null;

      // Update status back to Idle
      await ApiService.updateStatus(
        _isPomodoroActive && !_isBreak ? 'Focusing ⚡' : 'Idle',
        _isPomodoroActive && !_isBreak,
      );

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
        await fetchUserProfile(); // Update global score
        await updateAIHeadline();
      } catch (_) {}
    }
  }

  // Set Target Goal
  Future<void> setTargetGoal(String goal) async {
    _lastGoal = goal;
    await _saveLocalStats();
    notifyListeners();

    final token = await ApiService.getToken();
    if (token != null) {
      await ApiService.updateGoal(goal);
      await updateAIHeadline();
    }
  }

  // Fetch User Profile
  Future<void> fetchUserProfile() async {
    try {
      _isLoading = true;
      notifyListeners();

      final profile = await ApiService.getProfile();
      _userProfile = profile;
      if (profile['targetGoal'] != null &&
          profile['targetGoal'].toString().isNotEmpty) {
        _lastGoal = profile['targetGoal'];
        await _saveLocalStats();
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update AI Headline rolling text
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
    _pomodoroSecondsRemaining = 25 * 60;
    _pomodoroAccountedSeconds = 0;

    // Enable hard lock monitor service on Android
    await _channel.invokeMethod('startMonitoring', {
      'blockedApps': _distractionApps.toList(),
    });

    // Start native Pomodoro service
    await _channel.invokeMethod('startPomodoro', {
      'taskName': _lastGoal.isNotEmpty ? _lastGoal : "Focus Session",
      'durationSeconds': 25 * 60,
      'isBreak': false,
    });

    await ApiService.updateStatus('Focusing (Pomodoro) ⚡', true);
    notifyListeners();
  }

  void stopPomodoro() async {
    _isPomodoroActive = false;

    // Disable monitoring service
    await _channel.invokeMethod('stopMonitoring');
    // Stop native Pomodoro service
    await _channel.invokeMethod('stopPomodoro');

    await ApiService.updateStatus('Idle', false);

    // Sync activity with database
    final token = await ApiService.getToken();
    if (token != null) {
      await ApiService.syncActivity(
        _todayKey(),
        _studySeconds,
        _distractedSeconds,
      );
    }

    await _saveLocalStats();
    notifyListeners();
  }

  // --- Double-Tap Actions and Settings ---
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
      notifyListeners();
    } catch (_) {}
  }

  Future<void> requestDefaultLauncher() async {
    try {
      await _channel.invokeMethod('requestDefaultLauncher');
      // Don't eagerly check here — the result arrives via onDefaultLauncherChanged
      // callback (RoleManager path) or the next handleResume call (Settings path).
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

  // --- Distraction App Allocation Timer ---
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

  // --- Weekly Study Chart Data ---
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

    // Monthly calculation (past 30 days)
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
    // Reset recurring tasks at the start of each new day, and auto-archive completed non-recurring tasks
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
        _activeTaskId = null; // Unset active if it was deleted
      }
      await prefs.setString('tasks_last_reset', todayStr);
      await _saveTasks();
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('focus_tasks', jsonEncode(_tasks));
    // Immediately notify listeners so analytics panels re-render
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
    // notifyListeners() called by _saveTasks()
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
    // notifyListeners() called by _saveTasks()
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
      // Calculate how many seconds have elapsed since we last accounted for time
      int currentElapsed = (25 * 60) - _pomodoroSecondsRemaining;
      int newlyElapsed = currentElapsed - _pomodoroAccountedSeconds;
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
}
