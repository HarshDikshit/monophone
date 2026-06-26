import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defines all available widget types for the left panel
enum PanelWidgetType {
  clock,
  scratchpad,
  analytics,
  taskBlocks,    // Replaces barChart - shows plan day tasks with play/pause/stop
  taskBreakdown,
  quickActions,
  motivation,
  systemInfo,
  androidAppWidget, // Hosted third-party Android AppWidget
}

extension PanelWidgetTypeExtension on PanelWidgetType {
  String get displayName {
    switch (this) {
      case PanelWidgetType.clock:
        return 'CLOCK';
      case PanelWidgetType.scratchpad:
        return 'THOUGHT DUMP';
      case PanelWidgetType.analytics:
        return 'STUDY ANALYTICS';
      case PanelWidgetType.taskBlocks:
        return 'TASK BLOCKS';
      case PanelWidgetType.taskBreakdown:
        return 'TASK BREAKDOWN';
      case PanelWidgetType.quickActions:
        return 'QUICK ACTIONS';
      case PanelWidgetType.motivation:
        return 'MOTIVATIONAL QUOTE';
      case PanelWidgetType.systemInfo:
        return 'SYSTEM INFO';
      case PanelWidgetType.androidAppWidget:
        return 'ANDROID APP WIDGET';
    }
  }

  IconData get icon {
    switch (this) {
      case PanelWidgetType.clock:
        return Icons.access_time;
      case PanelWidgetType.scratchpad:
        return Icons.edit_note;
      case PanelWidgetType.analytics:
        return Icons.analytics;
      case PanelWidgetType.taskBlocks:
        return Icons.list_alt;
      case PanelWidgetType.taskBreakdown:
        return Icons.task_alt;
      case PanelWidgetType.quickActions:
        return Icons.flash_on;
      case PanelWidgetType.motivation:
        return Icons.psychology;
      case PanelWidgetType.systemInfo:
        return Icons.memory;
      case PanelWidgetType.androidAppWidget:
        return Icons.widgets;
    }
  }

  String get description {
    switch (this) {
      case PanelWidgetType.clock:
        return 'Live time and date display';
      case PanelWidgetType.scratchpad:
        return 'Free-form text notes that persist';
      case PanelWidgetType.analytics:
        return 'Focus, distracted & ratio stats';
      case PanelWidgetType.taskBlocks:
        return 'Plan day tasks with play/pause/stop controls & live focus time';
      case PanelWidgetType.taskBreakdown:
        return 'Time distribution by task';
      case PanelWidgetType.quickActions:
        return 'One-tap launcher quick actions';
      case PanelWidgetType.motivation:
        return 'Daily motivational quote card';
      case PanelWidgetType.systemInfo:
        return 'Device & app version info';
      case PanelWidgetType.androidAppWidget:
        return 'Embed real Android widgets from other apps';
    }
  }
}

/// A single widget instance in the panel
class WidgetPanelEntry {
  final String id;
  PanelWidgetType type;
  int order;
  Map<String, dynamic> config;

  WidgetPanelEntry({
    required this.id,
    required this.type,
    required this.order,
    this.config = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'order': order,
    'config': config,
  };

  factory WidgetPanelEntry.fromJson(Map<String, dynamic> json) =>
      WidgetPanelEntry(
        id: json['id'] as String,
        type: PanelWidgetType.values.firstWhere((e) => e.name == json['type']),
        order: json['order'] as int,
        config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
      );
}

/// Manages the widget panel entries with persistence
class WidgetPanelService extends ChangeNotifier {
  static const _storageKey = 'widget_panel_entries';
  static const _channel = MethodChannel('com.dixit.monophone/launcher');

  List<WidgetPanelEntry> _entries = [];
  List<WidgetPanelEntry> get entries => List.unmodifiable(_entries);

  bool _isEditing = false;
  bool get isEditing => _isEditing;

  /// Available Android AppWidget providers (from native side)
  List<Map<String, dynamic>> _availableWidgetProviders = [];
  List<Map<String, dynamic>> get availableWidgetProviders =>
      _availableWidgetProviders;

  /// Returns types NOT already added to the panel
  List<PanelWidgetType> get availableWidgetTypes {
    final added = _entries.map((e) => e.type).toSet();
    return PanelWidgetType.values.where((t) => !added.contains(t)).toList();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _entries = list
            .map((e) => WidgetPanelEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        _entries.sort((a, b) => a.order.compareTo(b.order));
      } catch (_) {
        _entries = _defaultEntries();
      }
    } else {
      _entries = _defaultEntries();
    }
    notifyListeners();
  }

  /// Fetch available Android AppWidget providers from native side
  Future<void> loadAppWidgetProviders() async {
    try {
      final result = await _channel.invokeMethod('getAvailableWidgetProviders');
      if (result is List) {
        _availableWidgetProviders = result
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load widget providers: $e');
    }
  }

  /// Bind and add an Android AppWidget to the panel
  Future<bool> bindAppWidget(String providerName) async {
    try {
      final result = await _channel.invokeMethod('bindAppWidget', {
        'providerName': providerName,
      });
      if (result is Map) {
        final appWidgetId = result['appWidgetId'] as int?;
        if (appWidgetId != null && appWidgetId > 0) {
          // Add to entries
          final maxOrder = _entries.isEmpty
              ? 0
              : _entries.map((e) => e.order).reduce((a, b) => a > b ? a : b);
          _entries.add(
            WidgetPanelEntry(
              id: 'appwidget_$appWidgetId',
              type: PanelWidgetType.androidAppWidget,
              order: maxOrder + 1,
              config: {
                'appWidgetId': appWidgetId,
                'providerName': providerName,
                'label': result['label'] ?? 'Widget',
              },
            ),
          );
          await _persist();
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Failed to bind widget: $e');
      return false;
    }
  }

  /// Remove an Android AppWidget from the panel and native host
  Future<void> removeAppWidget(int appWidgetId) async {
    try {
      await _channel.invokeMethod('removeAppWidget', {
        'appWidgetId': appWidgetId,
      });
    } catch (e) {
      debugPrint('Failed to remove widget: $e');
    }
  }

  /// Start/stop widget host listener
  Future<void> startWidgetHost() async {
    try {
      await _channel.invokeMethod('startWidgetHost');
    } catch (_) {}
  }

  Future<void> stopWidgetHost() async {
    try {
      await _channel.invokeMethod('stopWidgetHost');
    } catch (_) {}
  }

  List<WidgetPanelEntry> _defaultEntries() {
    return [
      WidgetPanelEntry(
        id: 'default_scratchpad',
        type: PanelWidgetType.scratchpad,
        order: 0,
      ),
      WidgetPanelEntry(
        id: 'default_analytics',
        type: PanelWidgetType.analytics,
        order: 1,
      ),
      WidgetPanelEntry(
        id: 'default_taskblocks',
        type: PanelWidgetType.taskBlocks,
        order: 2,
      ),
      WidgetPanelEntry(
        id: 'default_motivation',
        type: PanelWidgetType.motivation,
        order: 3,
      ),
    ];
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }

  Future<void> addWidget(PanelWidgetType type) async {
    if (_entries.any((e) => e.type == type)) return;
    final maxOrder = _entries.isEmpty
        ? 0
        : _entries.map((e) => e.order).reduce((a, b) => a > b ? a : b);
    _entries.add(
      WidgetPanelEntry(
        id: 'widget_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        order: maxOrder + 1,
      ),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> removeWidget(String id) async {
    // Check if it's an app widget - clean up native side
    final entry = _entries.firstWhere(
      (e) => e.id == id,
      orElse: () =>
          WidgetPanelEntry(id: '', type: PanelWidgetType.clock, order: -1),
    );
    if (entry.id.isNotEmpty && entry.type == PanelWidgetType.androidAppWidget) {
      final appWidgetId = entry.config['appWidgetId'] as int?;
      if (appWidgetId != null) {
        await removeAppWidget(appWidgetId);
      }
    }
    _entries.removeWhere((e) => e.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> reorderWidget(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final entry = _entries.removeAt(oldIndex);
    _entries.insert(newIndex, entry);
    for (int i = 0; i < _entries.length; i++) {
      _entries[i].order = i;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> updateConfig(String id, Map<String, dynamic> config) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    _entries[idx].config = config;
    await _persist();
    notifyListeners();
  }

  void toggleEditing() {
    _isEditing = !_isEditing;
    notifyListeners();
  }

  void setEditing(bool value) {
    _isEditing = value;
    notifyListeners();
  }
}