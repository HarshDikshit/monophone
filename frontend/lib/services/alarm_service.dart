import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'task_planner_service.dart';

/// Real-time alarm service that checks every second if any task's
/// start time matches the current system time, and plays an alert sound.
class AlarmService extends ChangeNotifier {
  Timer? _timer;
  final AudioPlayer _player = AudioPlayer();
  final Set<String> _triggeredTaskIds = {};

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  TaskPlannerService? _planner;

  /// IDs of tasks that have been triggered today (for alarm cooldown).
  /// Persisted across timer restarts so each task only alarms once per day.
  final Set<String> _todayTriggered = {};

  void attach(TaskPlannerService planner) {
    _planner = planner;
    startMonitoring();
  }

  void detach() {
    stopMonitoring();
    _planner = null;
  }

  /// Start the periodic time-checker.
  void startMonitoring() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _checkTime());
  }

  /// Stop the periodic time-checker.
  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  /// Clear triggered alarms for a new day.
  void resetDay() {
    _todayTriggered.clear();
    _triggeredTaskIds.clear();
  }

  void _checkTime() {
    final planner = _planner;
    if (planner == null) return;

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Get all tasks scheduled for today
    final todayTasks = planner.tasksForDate(now);

    for (final task in todayTasks) {
      if (!task.isAlarmEnabled) continue;
      if (task.isCompleted) continue;

      // Match exact hour and minute (ignore seconds)
      if (task.startTime.hour == now.hour &&
          task.startTime.minute == now.minute) {
        // Create a unique key for this task + day to avoid re-triggering
        final key = '${task.id}_$todayStr';
        if (!_todayTriggered.contains(key)) {
          _todayTriggered.add(key);
          _playAlarm(task);
        }
      }
    }
  }

  Future<void> _playAlarm(TimeBlockTask task) async {
    if (_isPlaying) return;
    _isPlaying = true;
    notifyListeners();

    try {
      // Play the alarm sound in a loop for up to 30 seconds
      await _player.setSource(AssetSource('alert.mp3'));
      await _player.setVolume(1.0);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.resume();

      // Automatically stop after 30 seconds
      Future.delayed(const Duration(seconds: 30), () {
        _stopAlarm();
      });

      debugPrint('🔔 ALARM triggered for task: ${task.title}');
    } catch (e) {
      debugPrint('Failed to play alarm sound: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  void _stopAlarm() {
    _player.stop();
    _isPlaying = false;
    notifyListeners();
  }

  /// Manually stop the currently-playing alarm.
  void stopAlarmManually() {
    _stopAlarm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }
}
