import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'task_planner_service.dart';
import 'launcher_state.dart';

/// A unified task bridge that synchronizes task data between:
///   - Focus engine (LauncherState._tasks)
///   - Day Planner engine (TaskPlannerService._tasks)
///
/// This ensures tasks created in either screen are visible in both.
class UnifiedTaskService extends ChangeNotifier {
  static const _bridgeStorageKey = 'unified_task_bridge';
  static UnifiedTaskService? _instance;

  /// Bridge tasks: enriched copies that carry both planner and focus fields.
  List<Map<String, dynamic>> _bridgeTasks = [];
  List<Map<String, dynamic>> get bridgeTasks => List.unmodifiable(_bridgeTasks);

  bool _isInitialized = false;

  LauncherState? _launcherState;
  TaskPlannerService? _plannerService;

  static UnifiedTaskService get instance {
    _instance ??= UnifiedTaskService._();
    return _instance!;
  }

  UnifiedTaskService._();

  void attach(LauncherState launcher, TaskPlannerService planner) {
    _launcherState = launcher;
    _plannerService = planner;
    if (!_isInitialized) {
      _isInitialized = true;
      launcher.addListener(_onAnyChange);
      planner.addListener(_onAnyChange);
      _syncFromSources();
    }
  }

  void _onAnyChange() {
    _syncFromSources();
  }

  Future<void> _syncFromSources() async {
    final launcherTasks = _launcherState?.tasks ?? [];
    final plannerTasks = _plannerService?.tasks ?? [];

    // Map bridge tasks by id
    final bridgeMap = <String, Map<String, dynamic>>{};
    for (final t in _bridgeTasks) {
      bridgeMap[t['id'] as String] = Map<String, dynamic>.from(t);
    }

    // Sync launcher tasks → bridge
    for (final lt in launcherTasks) {
      final id = lt['id'] as String;
      if (bridgeMap.containsKey(id)) {
        bridgeMap[id]!.addAll(Map<String, dynamic>.from(lt));
      } else {
        // Check if a planner task with same id exists
        final plannerMatch = plannerTasks.where((p) => p.id == id).isNotEmpty;
        final merged = Map<String, dynamic>.from(lt);
        if (plannerMatch) {
          final pt = plannerTasks.firstWhere((p) => p.id == id);
          merged['durationMinutes'] = pt.durationMinutes;
          merged['startTime'] = pt.startTime.toIso8601String();
          merged['tag'] = pt.tag.name;
        } else {
          merged['durationMinutes'] = lt['durationMinutes'] ?? 60;
        }
        bridgeMap[id] = merged;
      }
    }

    // Sync planner tasks → bridge
    for (final pt in plannerTasks) {
      final id = pt.id;
      if (bridgeMap.containsKey(id)) {
        bridgeMap[id]!['title'] = pt.title;
        bridgeMap[id]!['description'] = pt.description;
        bridgeMap[id]!['durationMinutes'] = pt.durationMinutes;
        bridgeMap[id]!['startTime'] = pt.startTime.toIso8601String();
        bridgeMap[id]!['tag'] = pt.tag.name;
        bridgeMap[id]!['isRecurring'] = pt.isRecurring;
        bridgeMap[id]!['isCompleted'] = pt.isCompleted;
        bridgeMap[id]!['focusSeconds'] =
            (bridgeMap[id]!['focusSeconds'] ?? 0) + pt.focusSeconds;
      } else {
        // Check if launcher has it
        final launcherMatch = launcherTasks
            .where((l) => l['id'] == id)
            .isNotEmpty;
        if (!launcherMatch) {
          bridgeMap[id] = {
            'id': id,
            'title': pt.title,
            'description': pt.description,
            'durationMinutes': pt.durationMinutes,
            'startTime': pt.startTime.toIso8601String(),
            'tag': pt.tag.name,
            'isRecurring': pt.isRecurring,
            'isCompleted': pt.isCompleted,
            'focusSeconds': pt.focusSeconds,
            'isDone': pt.isCompleted,
            'createdAt': DateTime.now().toIso8601String(),
          };
        }
      }
    }

    _bridgeTasks = bridgeMap.values.toList();
    notifyListeners();
  }

  /// Add a task to BOTH sources
  Future<void> createTask({
    required String title,
    String description = '',
    bool isRecurring = false,
    int durationMinutes = 60,
    DateTime? startTime,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    final st = startTime ?? now;

    // Add to LauncherState
    await _launcherState?.addTask(
      title,
      isRecurring: isRecurring,
      durationMinutes: durationMinutes,
    );

    // Add to TaskPlannerService (planner side)
    final plannerTask = TimeBlockTask(
      id: id,
      title: title,
      description: description,
      startTime: st,
      durationMinutes: durationMinutes,
      isRecurring: isRecurring,
    );
    await _plannerService?.addTask(plannerTask);

    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bridgeStorageKey, jsonEncode(_bridgeTasks));
  }

  @override
  void dispose() {
    _launcherState?.removeListener(_onAnyChange);
    _plannerService?.removeListener(_onAnyChange);
    super.dispose();
  }
}
