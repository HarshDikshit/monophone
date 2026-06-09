import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service that exposes FocusTube blocker rules to the rest of the app.
class BlockerService extends ChangeNotifier {
  BlockerService._internal();
  static final BlockerService instance = BlockerService._internal();

  // --- State ---
  bool _isStrictMode = false;
  bool _blockReelsShorts = false;
  String _unlockOption = 'text';
  DateTime? _lockUntilDate;
  String _randomChallengeText = '';

  bool _vpnContentFilterEnabled = false;
  bool _monochromeModeEnabled = false;
  bool _notificationSilenceEnabled = false;
  String _frictionGateType = 'countdown';
  List<String> _restrictedKeywords = [];
  Map<String, int> _dailyLimits = {}; // appName -> minutes

  /// Max emergency uses per app per day (user-definable, 1-5)
  Map<String, int> _emergencyUseCounts =
      {}; // appName -> max emergency uses (1-5)

  /// Channel rules: list of {name, type}
  List<Map<String, String>> _channels = [];

  List<String> _unproductiveAppNames = [];

  bool get isStrictMode => _isStrictMode;
  bool get blockReelsShorts => _blockReelsShorts;
  String get unlockOption => _unlockOption;
  DateTime? get lockUntilDate => _lockUntilDate;
  String get randomChallengeText => _randomChallengeText;
  List<Map<String, String>> get channels => List.unmodifiable(_channels);
  List<String> get unproductiveAppNames =>
      List.unmodifiable(_unproductiveAppNames);

  bool get vpnContentFilterEnabled => _vpnContentFilterEnabled;
  bool get monochromeModeEnabled => _monochromeModeEnabled;
  bool get notificationSilenceEnabled => _notificationSilenceEnabled;
  String get frictionGateType => _frictionGateType;
  List<String> get restrictedKeywords => _restrictedKeywords;
  Map<String, int> get dailyLimits => _dailyLimits;
  Map<String, int> get emergencyUseCounts => _emergencyUseCounts;

  /// Get max emergency uses for a specific app (default 3 if not set)
  int getEmergencyUsesForApp(String appName) =>
      _emergencyUseCounts[appName] ?? 3;

  List<String> get allowedChannels => _channels
      .where((c) => c['type'] == 'allowed')
      .map((c) => c['name'] ?? '')
      .where((n) => n.isNotEmpty)
      .toList();

  List<String> get blockedChannels => _channels
      .where((c) => c['type'] == 'blocked')
      .map((c) => c['name'] ?? '')
      .where((n) => n.isNotEmpty)
      .toList();

  bool _loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _isStrictMode = prefs.getBool('focustube_strict_mode') ?? false;
    _blockReelsShorts = prefs.getBool('focustube_block_reels_shorts') ?? false;
    _unlockOption = prefs.getString('focustube_unlock_option') ?? 'text';

    final lockUntilStr = prefs.getString('focustube_lock_until') ?? '';
    _lockUntilDate = lockUntilStr.isNotEmpty
        ? DateTime.tryParse(lockUntilStr)
        : null;

    _randomChallengeText =
        prefs.getString('focustube_challenge_text') ??
        _generateRandomString(100);

    _vpnContentFilterEnabled = prefs.getBool('focustube_vpn_filter') ?? false;
    _monochromeModeEnabled = prefs.getBool('focustube_monochrome') ?? false;
    _notificationSilenceEnabled =
        prefs.getBool('focustube_notification_silence') ?? false;
    _frictionGateType =
        prefs.getString('focustube_friction_gate') ?? 'countdown';
    _restrictedKeywords =
        prefs.getStringList('focustube_restricted_keywords') ??
        ['twitter.com', 'x.com', 'reddit.com', 'facebook.com', 'instagram.com'];

    final dailyLimitsStr = prefs.getString('focustube_daily_limits') ?? '{}';
    try {
      final decoded = jsonDecode(dailyLimitsStr) as Map;
      _dailyLimits = decoded.map(
        (k, v) => MapEntry(k.toString(), int.parse(v.toString())),
      );
    } catch (_) {
      _dailyLimits = {};
    }

    // Load emergency use counts
    final emergencyCountsStr =
        prefs.getString('focustube_emergency_counts') ?? '{}';
    try {
      final decoded = jsonDecode(emergencyCountsStr) as Map;
      _emergencyUseCounts = decoded.map(
        (k, v) => MapEntry(k.toString(), int.parse(v.toString())),
      );
    } catch (_) {
      _emergencyUseCounts = {};
    }

    final channelsJson = prefs.getString('focustube_channels') ?? '';
    if (channelsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(channelsJson) as List;
        _channels = decoded
            .map((item) => Map<String, String>.from(item))
            .toList();
      } catch (_) {
        _channels = _defaultChannels();
      }
    } else {
      _channels = _defaultChannels();
    }

    _unproductiveAppNames =
        prefs.getStringList('focustube_blocked_apps') ??
        ['Instagram', 'TikTok', 'Facebook'];

    _loaded = true;
    notifyListeners();
  }

  bool isAppBlockedByName(String appName) {
    if (!_loaded) return false;
    final nameLower = appName.toLowerCase().trim();
    return _unproductiveAppNames.any(
      (blocked) => blocked.toLowerCase().trim() == nameLower,
    );
  }

  bool isReelsBlockedByName(String appName) {
    if (!_loaded || !_blockReelsShorts) return false;
    final n = appName.toLowerCase().trim();
    return n.contains('reels') ||
        n.contains('shorts') ||
        n.contains('instagram') ||
        n.contains('youtube') ||
        n.contains('tiktok') ||
        n.contains('facebook');
  }

  bool isChannelBlocked(String channelName) {
    if (!_loaded) return false;
    final nameLower = channelName.toLowerCase().trim();
    final match = _channels.firstWhere(
      (c) => (c['name'] ?? '').toLowerCase().trim() == nameLower,
      orElse: () => {},
    );
    if (match.isNotEmpty) return match['type'] == 'blocked';
    return false;
  }

  Future<void> saveSettings({
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
    required Map<String, int> emergencyUseCounts,
    required List<String> unproductiveAppNames,
    required List<Map<String, String>> channels,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _isStrictMode = isStrictMode;
    _blockReelsShorts = blockReelsShorts;
    _unlockOption = unlockOption;
    _lockUntilDate = lockUntilDate;
    _vpnContentFilterEnabled = vpnContentFilterEnabled;
    _monochromeModeEnabled = monochromeModeEnabled;
    _notificationSilenceEnabled = notificationSilenceEnabled;
    _frictionGateType = frictionGateType;
    _restrictedKeywords = restrictedKeywords;
    _dailyLimits = dailyLimits;
    _emergencyUseCounts = emergencyUseCounts;
    _unproductiveAppNames = unproductiveAppNames;
    _channels = channels;

    await prefs.setBool('focustube_strict_mode', _isStrictMode);
    await prefs.setBool('focustube_block_reels_shorts', _blockReelsShorts);
    await prefs.setString('focustube_unlock_option', _unlockOption);
    await prefs.setString(
      'focustube_lock_until',
      _lockUntilDate?.toIso8601String() ?? '',
    );
    await prefs.setBool('focustube_vpn_filter', _vpnContentFilterEnabled);
    await prefs.setBool('focustube_monochrome', _monochromeModeEnabled);
    await prefs.setBool(
      'focustube_notification_silence',
      _notificationSilenceEnabled,
    );
    await prefs.setString('focustube_friction_gate', _frictionGateType);
    await prefs.setStringList(
      'focustube_restricted_keywords',
      _restrictedKeywords,
    );
    await prefs.setString('focustube_daily_limits', jsonEncode(_dailyLimits));
    await prefs.setString(
      'focustube_emergency_counts',
      jsonEncode(_emergencyUseCounts),
    );
    await prefs.setStringList('focustube_blocked_apps', _unproductiveAppNames);
    await prefs.setString('focustube_channels', jsonEncode(_channels));

    notifyListeners();
  }

  Future<void> activateStrictMode({
    required String unlockOption,
    DateTime? lockUntilDate,
  }) async {
    _isStrictMode = true;
    _unlockOption = unlockOption;
    _lockUntilDate = lockUntilDate;
    _randomChallengeText = _generateRandomString(100);
    await _saveCore();
    notifyListeners();
  }

  Future<bool> tryDeactivateStrictMode({String? challengeInput}) async {
    if (_unlockOption == 'date') {
      if (_lockUntilDate != null && DateTime.now().isBefore(_lockUntilDate!)) {
        return false;
      }
    } else if (_unlockOption == 'text') {
      if ((challengeInput ?? '').trim() != _randomChallengeText.trim()) {
        return false;
      }
    }
    _isStrictMode = false;
    _lockUntilDate = null;
    await _saveCore();
    notifyListeners();
    return true;
  }

  Future<void> deactivateStrictModeForced() async {
    _isStrictMode = false;
    _lockUntilDate = null;
    await _saveCore();
    notifyListeners();
  }

  Future<void> _saveCore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focustube_strict_mode', _isStrictMode);
    await prefs.setString('focustube_unlock_option', _unlockOption);
    await prefs.setString(
      'focustube_lock_until',
      _lockUntilDate?.toIso8601String() ?? '',
    );
    await prefs.setString('focustube_challenge_text', _randomChallengeText);
  }

  List<Map<String, String>> _defaultChannels() => [
    {'name': 'MIT OpenCourseWare', 'type': 'allowed'},
    {'name': '3Blue1Brown', 'type': 'allowed'},
    {'name': 'MrBeast', 'type': 'blocked'},
    {'name': 'PewDiePie', 'type': 'blocked'},
  ];

  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()';
    final random = Random();
    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
