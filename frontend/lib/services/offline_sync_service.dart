import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Queues data locally when offline and auto-syncs when connectivity is restored.
/// Uses SharedPreferences as the local queue (lightweight Redis-like storage).
class OfflineSyncService {
  static const _queueKey = 'offline_sync_queue';
  static const _lastSyncKey = 'last_offline_sync';
  static const _cachedProfileKey = 'cached_user_profile';
  static const _cachedGoalKey = 'cached_goal';

  static OfflineSyncService? _instance;
  static OfflineSyncService get instance =>
      _instance ??= OfflineSyncService._();
  OfflineSyncService._();

  Timer? _syncTimer;

  /// Start periodic sync attempts (call once at app startup)
  void startPeriodicSync({Duration interval = const Duration(minutes: 2)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) => processQueue());
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Queue an activity sync for later
  Future<void> queueActivitySync(
    String date,
    int studySeconds,
    int distractedSeconds,
  ) async {
    await _enqueue({
      'type': 'sync_activity',
      'date': date,
      'studySeconds': studySeconds,
      'distractedSeconds': distractedSeconds,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Queue a goal update for later
  Future<void> queueGoalUpdate(String goal) async {
    await _enqueue({
      'type': 'update_goal',
      'goal': goal,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Queue a status update for later
  Future<void> queueStatusUpdate(String activity, bool isStudying) async {
    await _enqueue({
      'type': 'update_status',
      'activity': activity,
      'isStudying': isStudying,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Cache user profile locally for offline display
  Future<void> cacheUserProfile(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedProfileKey, jsonEncode(profile));
  }

  /// Get cached user profile
  Future<Map<String, dynamic>?> getCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedProfileKey);
    if (raw != null) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {}
    }
    return null;
  }

  /// Cache goal locally
  Future<void> cacheGoal(String goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedGoalKey, goal);
  }

  /// Get cached goal
  Future<String> getCachedGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cachedGoalKey) ?? '';
  }

  /// Process the offline queue - tries to sync everything to backend
  Future<int> processQueue() async {
    final token = await ApiService.getToken();
    if (token == null) return 0; // Not logged in, can't sync

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return 0;

    try {
      final queue = List<Map<String, dynamic>>.from(jsonDecode(raw));
      if (queue.isEmpty) return 0;

      int synced = 0;
      final remaining = <Map<String, dynamic>>[];

      for (final item in queue) {
        try {
          final type = item['type'] as String?;
          bool success = false;

          if (type == 'sync_activity') {
            await ApiService.syncActivity(
              item['date'] as String,
              item['studySeconds'] as int,
              item['distractedSeconds'] as int,
            );
            success = true;
          } else if (type == 'update_goal') {
            await ApiService.updateGoal(item['goal'] as String);
            success = true;
          } else if (type == 'update_status') {
            await ApiService.updateStatus(
              item['activity'] as String,
              item['isStudying'] as bool,
            );
            success = true;
          }

          if (success) {
            synced++;
          } else {
            remaining.add(item);
          }
        } catch (_) {
          remaining.add(item);
        }
      }

      await prefs.setString(_queueKey, jsonEncode(remaining));
      if (synced > 0) {
        await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
      }
      return synced;
    } catch (_) {
      return 0;
    }
  }

  /// Check if there are pending items in the queue
  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      return List<dynamic>.from(jsonDecode(raw)).length;
    } catch (_) {
      return 0;
    }
  }

  /// Get last sync time
  Future<DateTime?> lastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    if (raw != null) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  Future<void> _enqueue(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    final queue = raw != null
        ? List<Map<String, dynamic>>.from(jsonDecode(raw))
        : <Map<String, dynamic>>[];
    queue.add(item);
    // Keep max 500 queue items to avoid storage bloat
    if (queue.length > 500) {
      queue.removeRange(0, queue.length - 500);
    }
    await prefs.setString(_queueKey, jsonEncode(queue));
  }
}
