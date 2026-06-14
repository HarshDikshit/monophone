import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tags for task categorization
enum TaskTag { focus, work, general, nonFocus }

extension TaskTagExtension on TaskTag {
  String get displayName {
    switch (this) {
      case TaskTag.focus:
        return 'FOCUS';
      case TaskTag.work:
        return 'WORK';
      case TaskTag.general:
        return 'GENERAL';
      case TaskTag.nonFocus:
        return 'NON-FOCUS';
    }
  }

  Color get color {
    switch (this) {
      case TaskTag.focus:
        return Colors.white;
      case TaskTag.work:
        return const Color(0xFF64B5F6);
      case TaskTag.general:
        return const Color(0xFF81C784);
      case TaskTag.nonFocus:
        return const Color(0xFFE57373);
    }
  }

  IconData get icon {
    switch (this) {
      case TaskTag.focus:
        return Icons.psychology;
      case TaskTag.work:
        return Icons.work;
      case TaskTag.general:
        return Icons.circle;
      case TaskTag.nonFocus:
        return Icons.block;
    }
  }
}

/// A single scheduled task/time block
class TimeBlockTask {
  String id;
  String title;
  String description;
  TaskTag tag;
  DateTime startTime;
  int durationMinutes;
  int estimatedPomodoros;
  bool isRecurring;
  List<int> recurringDays; // days of week (1=Mon..7=Sun)
  bool isCompleted;
  bool isAlarmEnabled;
  int focusSeconds;
  int completedPomodoros;

  DateTime get endTime => startTime.add(Duration(minutes: durationMinutes));
  String get timeSlotString =>
      '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'
      ' - ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

  TimeBlockTask({
    required this.id,
    required this.title,
    this.description = '',
    this.tag = TaskTag.general,
    required this.startTime,
    this.durationMinutes = 60,
    this.estimatedPomodoros = 2,
    this.isRecurring = false,
    this.recurringDays = const [],
    this.isCompleted = false,
    this.isAlarmEnabled = true,
    this.focusSeconds = 0,
    this.completedPomodoros = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'tag': tag.name,
    'startTime': startTime.toIso8601String(),
    'durationMinutes': durationMinutes,
    'estimatedPomodoros': estimatedPomodoros,
    'isRecurring': isRecurring,
    'recurringDays': recurringDays,
    'isCompleted': isCompleted,
    'isAlarmEnabled': isAlarmEnabled,
    'focusSeconds': focusSeconds,
    'completedPomodoros': completedPomodoros,
  };

  factory TimeBlockTask.fromJson(Map<String, dynamic> json) => TimeBlockTask(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    tag: TaskTag.values.firstWhere(
      (e) => e.name == json['tag'],
      orElse: () => TaskTag.general,
    ),
    startTime: DateTime.parse(json['startTime'] as String),
    durationMinutes: json['durationMinutes'] as int? ?? 60,
    estimatedPomodoros: json['estimatedPomodoros'] as int? ?? 2,
    isRecurring: json['isRecurring'] as bool? ?? false,
    recurringDays: List<int>.from(json['recurringDays'] as List? ?? []),
    isCompleted: json['isCompleted'] as bool? ?? false,
    isAlarmEnabled: json['isAlarmEnabled'] as bool? ?? true,
    focusSeconds: json['focusSeconds'] as int? ?? 0,
    completedPomodoros: json['completedPomodoros'] as int? ?? 0,
  );

  TimeBlockTask copyWith({
    String? id,
    String? title,
    String? description,
    TaskTag? tag,
    DateTime? startTime,
    int? durationMinutes,
    int? estimatedPomodoros,
    bool? isRecurring,
    List<int>? recurringDays,
    bool? isCompleted,
    bool? isAlarmEnabled,
    int? focusSeconds,
    int? completedPomodoros,
  }) => TimeBlockTask(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    tag: tag ?? this.tag,
    startTime: startTime ?? this.startTime,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    estimatedPomodoros: estimatedPomodoros ?? this.estimatedPomodoros,
    isRecurring: isRecurring ?? this.isRecurring,
    recurringDays: recurringDays ?? this.recurringDays,
    isCompleted: isCompleted ?? this.isCompleted,
    isAlarmEnabled: isAlarmEnabled ?? this.isAlarmEnabled,
    focusSeconds: focusSeconds ?? this.focusSeconds,
    completedPomodoros: completedPomodoros ?? this.completedPomodoros,
  );
}

/// Manages time-block tasks with persistence, reminders, and recurrence
class TaskPlannerService extends ChangeNotifier {
  static const _storageKey = 'time_block_tasks';
  static const _pomodoroDurationKey = 'planner_pomodoro_duration';
  static const _channel = MethodChannel('com.dixit.monophone/launcher');

  List<TimeBlockTask> _tasks = [];
  List<TimeBlockTask> get tasks => List.unmodifiable(_tasks);

  int _pomodoroDuration = 25;
  int get pomodoroDuration => _pomodoroDuration;

  /// Get task by ID
  TimeBlockTask? getTaskById(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get tasks for a specific date
  List<TimeBlockTask> tasksForDate(DateTime date) {
    final dateStart = DateTime(date.year, date.month, date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));
    final weekday = date.weekday; // 1=Mon..7=Sun

    return _tasks.where((task) {
      // Check if task starts on this date
      if (task.startTime.isAfter(dateStart) &&
          task.startTime.isBefore(dateEnd)) {
        return true;
      }
      // Check recurring tasks
      if (task.isRecurring && task.recurringDays.contains(weekday)) {
        return true;
      }
      return false;
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Get all tasks for a month view (30 days from start)
  Map<DateTime, List<TimeBlockTask>> tasksForMonth(DateTime start) {
    final result = <DateTime, List<TimeBlockTask>>{};
    for (int i = 0; i < 30; i++) {
      final day = start.add(Duration(days: i));
      final dayTasks = tasksForDate(day);
      if (dayTasks.isNotEmpty || i < 7) {
        result[DateTime(day.year, day.month, day.day)] = dayTasks;
      }
    }
    return result;
  }

  /// Get upcoming tasks that are starting within the next [minutes] minutes
  List<TimeBlockTask> upcomingTasks(int withinMinutes) {
    final now = DateTime.now();
    final threshold = now.add(Duration(minutes: withinMinutes));
    return _tasks.where((task) {
      if (task.isCompleted) return false;
      // Check today's tasks starting soon
      if (task.startTime.isAfter(now) && task.startTime.isBefore(threshold)) {
        return true;
      }
      // Recurring check
      if (task.isRecurring && task.recurringDays.contains(now.weekday)) {
        final todayTask = DateTime(
          now.year,
          now.month,
          now.day,
          task.startTime.hour,
          task.startTime.minute,
        );
        return todayTask.isAfter(now) && todayTask.isBefore(threshold);
      }
      return false;
    }).toList();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _pomodoroDuration = prefs.getInt(_pomodoroDurationKey) ?? 25;
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _tasks = list
            .map((e) => TimeBlockTask.fromJson(e as Map<String, dynamic>))
            .toList();
        _tasks.sort((a, b) => a.startTime.compareTo(b.startTime));
      } catch (_) {
        _tasks = [];
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_tasks.map((t) => t.toJson()).toList()),
    );
    await prefs.setInt(_pomodoroDurationKey, _pomodoroDuration);
  }

  Future<void> addTask(TimeBlockTask task) async {
    _tasks.add(task);
    _tasks.sort((a, b) => a.startTime.compareTo(b.startTime));
    await _persist();
    notifyListeners();
  }

  Future<void> updateTask(TimeBlockTask task) async {
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      _tasks[idx] = task;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> removeTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> toggleComplete(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _tasks[idx].isCompleted = !_tasks[idx].isCompleted;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> addFocusSeconds(String id, int seconds) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _tasks[idx].focusSeconds += seconds;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> incrementPomodoro(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _tasks[idx].completedPomodoros += 1;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> setPomodoroDuration(int minutes) async {
    _pomodoroDuration = minutes.clamp(5, 120);
    await _persist();
    notifyListeners();
  }

  Future<void> scheduleReminders(List<TimeBlockTask> tasks) async {
    for (final task in tasks) {
      final reminderTime = task.startTime.subtract(const Duration(minutes: 5));
      if (reminderTime.isAfter(DateTime.now())) {
        try {
          await _channel.invokeMethod('scheduleNotification', {
            'id': task.id.hashCode,
            'title': task.title,
            'body':
                'Starting in 5 minutes: ${task.title} (${task.tag.displayName})',
            'scheduledAt': reminderTime.millisecondsSinceEpoch,
            'playSound': true,
          });
        } catch (_) {}
      }
    }
  }

  /// Generate recurring tasks for next 30 days
  List<TimeBlockTask> generateRecurringInstances(String rootTaskId) {
    final rootTask = _tasks.firstWhere(
      (t) => t.id == rootTaskId,
      orElse: () => _tasks.first,
    );
    if (!rootTask.isRecurring) return [];

    final instances = <TimeBlockTask>[];
    final now = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final date = now.add(Duration(days: i));
      if (rootTask.recurringDays.contains(date.weekday)) {
        final instanceStart = DateTime(
          date.year,
          date.month,
          date.day,
          rootTask.startTime.hour,
          rootTask.startTime.minute,
        );
        if (instanceStart.isAfter(now)) {
          instances.add(
            rootTask.copyWith(
              id: '${rootTask.id}_${date.toIso8601String().substring(0, 10)}',
              startTime: instanceStart,
              isRecurring: false,
            ),
          );
        }
      }
    }
    return instances;
  }

  /// Start planning mode - clears completed non-recurring tasks from yesterday
  Future<void> startNewDay() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    _tasks.removeWhere(
      (t) => !t.isRecurring && t.isCompleted && t.startTime.isBefore(yesterday),
    );
    await _persist();
    notifyListeners();
  }
}
