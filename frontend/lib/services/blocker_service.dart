import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service that exposes FocusTube blocker rules to the rest of the app.
///
/// Loaded eagerly on first access and kept in sync whenever [FocusTubeBlockerScreen]
/// saves its settings.  The launcher's [_onAppTap] hook reads [isAppBlocked] /
/// [isStrictMode] to decide whether to launch or intercept.
class BlockerService extends ChangeNotifier {
  BlockerService._internal();
  static final BlockerService instance = BlockerService._internal();

  // --- State ---
  bool _isStrictMode = false;
  bool _blockReelsShorts = false;
  String _unlockOption = 'text';
  DateTime? _lockUntilDate;
  String _randomChallengeText = '';

  /// Channel rules: list of {name, type} where type = 'allowed' | 'blocked'
  List<Map<String, String>> _channels = [];

  /// Display-name list of apps the user marked unproductive (e.g. "Instagram")
  List<String> _unproductiveAppNames = [];

  bool get isStrictMode => _isStrictMode;
  bool get blockReelsShorts => _blockReelsShorts;
  String get unlockOption => _unlockOption;
  DateTime? get lockUntilDate => _lockUntilDate;
  String get randomChallengeText => _randomChallengeText;
  List<Map<String, String>> get channels => List.unmodifiable(_channels);
  List<String> get unproductiveAppNames => List.unmodifiable(_unproductiveAppNames);

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

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Load (or reload) settings from SharedPreferences.
  /// Call this once at app startup and after any save in [FocusTubeBlockerScreen].
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _isStrictMode = prefs.getBool('focustube_strict_mode') ?? false;
    _blockReelsShorts = prefs.getBool('focustube_block_reels_shorts') ?? false;
    _unlockOption = prefs.getString('focustube_unlock_option') ?? 'text';

    final lockUntilStr = prefs.getString('focustube_lock_until') ?? '';
    _lockUntilDate =
        lockUntilStr.isNotEmpty ? DateTime.tryParse(lockUntilStr) : null;

    _randomChallengeText =
        prefs.getString('focustube_challenge_text') ?? _generateRandomString(100);

    final channelsJson = prefs.getString('focustube_channels') ?? '';
    if (channelsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(channelsJson) as List;
        _channels =
            decoded.map((item) => Map<String, String>.from(item)).toList();
      } catch (_) {
        _channels = _defaultChannels();
      }
    } else {
      _channels = _defaultChannels();
    }

    _unproductiveAppNames = prefs.getStringList('focustube_blocked_apps') ??
        ['Instagram', 'TikTok', 'Facebook'];

    _loaded = true;
    notifyListeners();
  }

  /// Returns true if the given installed [appName] is blocked by FocusTube rules.
  /// [packageName] is used for future native-side checks.
  bool isAppBlockedByName(String appName) {
    if (!_loaded) return false;
    final nameLower = appName.toLowerCase().trim();
    return _unproductiveAppNames
        .any((blocked) => blocked.toLowerCase().trim() == nameLower);
  }

  /// Returns true if the given [appName] contains "reels" / "shorts" keywords
  /// AND the reels-block toggle is active.
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

  /// Returns true if the YouTube [channelName] is classified as blocked.
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

  // ---------------------------------------------------------------------------
  // Strict-Mode lock / unlock helpers (called from FocusTubeBlockerScreen too)
  // ---------------------------------------------------------------------------

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

  Future<bool> tryDeactivateStrictMode({
    String? challengeInput,
  }) async {
    if (_unlockOption == 'date') {
      if (_lockUntilDate != null && DateTime.now().isBefore(_lockUntilDate!)) {
        return false; // still locked
      }
    } else if (_unlockOption == 'text') {
      if ((challengeInput ?? '').trim() != _randomChallengeText.trim()) {
        return false; // wrong challenge
      }
    }
    // QR option: caller verifies externally
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

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _saveCore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focustube_strict_mode', _isStrictMode);
    await prefs.setString('focustube_unlock_option', _unlockOption);
    await prefs.setString(
        'focustube_lock_until', _lockUntilDate?.toIso8601String() ?? '');
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
        length, (index) => chars[random.nextInt(chars.length)]).join();
  }
}
