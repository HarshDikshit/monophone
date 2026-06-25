import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/blocker_service.dart';
import '../services/launcher_state.dart';

class FocusTubeBlockerScreen extends StatefulWidget {
  const FocusTubeBlockerScreen({super.key});

  @override
  State<FocusTubeBlockerScreen> createState() => _FocusTubeBlockerScreenState();
}

class _FocusTubeBlockerScreenState extends State<FocusTubeBlockerScreen> {
  // Removed _selectedTab state and unnecessary tabs

  // Local Blocker configuration states (synced with BlockerService)
  bool _isStrictMode = false;
  bool _blockYoutubeShorts = false;
  bool _blockInstagramReels = false;
  bool _allowOneYoutubeShort = false;
  bool _allowOneInstagramReel = false;
  String _unlockOption = 'text';
  DateTime? _lockUntilDate;
  bool _vpnContentFilter = false;
  bool _monochromeMode = false;
  bool _notificationSilence = false;
  String _frictionGate = 'countdown';
  List<String> _keywords = [];
  Map<String, int> _dailyLimits = {};
  List<String> _unproductiveApps = [];
  List<Map<String, String>> _channels = [];

  Map<String, int> _emergencyUseCounts = {};

  // Controllers
  final _keywordController = TextEditingController();
  final _taskController = TextEditingController();
  final _appLimitMinutesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _taskController.dispose();
    _appLimitMinutesController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    final blocker = BlockerService.instance;
    setState(() {
      _isStrictMode = blocker.isStrictMode;
      _blockYoutubeShorts = blocker.blockYoutubeShorts;
      _blockInstagramReels = blocker.blockInstagramReels;
      _allowOneYoutubeShort = blocker.allowOneYoutubeShort;
      _allowOneInstagramReel = blocker.allowOneInstagramReel;
      _unlockOption = blocker.unlockOption;
      _lockUntilDate = blocker.lockUntilDate;
      _vpnContentFilter = blocker.vpnContentFilterEnabled;
      _monochromeMode = blocker.monochromeModeEnabled;
      _notificationSilence = blocker.notificationSilenceEnabled;
      _frictionGate = blocker.frictionGateType;
      _keywords = List<String>.from(blocker.restrictedKeywords);
      _dailyLimits = Map<String, int>.from(blocker.dailyLimits);
      _emergencyUseCounts = Map<String, int>.from(blocker.emergencyUseCounts);
      _unproductiveApps = List<String>.from(blocker.unproductiveAppNames);
      _channels = List<Map<String, String>>.from(blocker.channels);
    });
  }

  Future<void> _saveSettings() async {
    final state = context.read<LauncherState>();
    await state.updateBlockerSettings(
      isStrictMode: _isStrictMode,
      blockYoutubeShorts: _blockYoutubeShorts,
      blockInstagramReels: _blockInstagramReels,
      allowOneYoutubeShort: _allowOneYoutubeShort,
      allowOneInstagramReel: _allowOneInstagramReel,
      unlockOption: _unlockOption,
      lockUntilDate: _lockUntilDate,
      vpnContentFilterEnabled: _vpnContentFilter,
      monochromeModeEnabled: _monochromeMode,
      notificationSilenceEnabled: _notificationSilence,
      frictionGateType: _frictionGate,
      restrictedKeywords: _keywords,
      dailyLimits: _dailyLimits,
      emergencyUseCounts: _emergencyUseCounts,
      unproductiveAppNames: _unproductiveApps,
      channels: _channels,
    );
    _loadSettings(); // Reload to sync state
  }

  bool get _isLocked =>
      _isStrictMode &&
      _lockUntilDate != null &&
      DateTime.now().isBefore(_lockUntilDate!);

  String _formatStrictDate() {
    if (_lockUntilDate == null) return "Thu, 11 Jun"; // Placeholder fallback
    final weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${weekdays[_lockUntilDate!.weekday - 1]}, ${_lockUntilDate!.day} ${months[_lockUntilDate!.month - 1]}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildBlocksTab(),
      ),
    );
  }

  // Removed _buildTabContent, _buildFocusTab, _buildPlannerTab, and _buildGroupsTab

  // ── 4. BLOCKS TAB (Dashboard blocker) ──────────────────────────────────────
  Widget _buildBlocksTab() {
    final state = context.watch<LauncherState>();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Permission Warnings
            FutureBuilder<bool>(
              future: state.isAccessibilityServiceEnabled(),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data ?? true;
                if (isEnabled) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildWarningBanner(
                    "Accessibility Service Off",
                    "Required for Shorts/Reels blocking.",
                    () => state.openAccessibilitySettings(),
                  ),
                );
              },
            ),
            FutureBuilder<bool>(
              future: state.hasUsageAccessPermission(),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data ?? true;
                if (isEnabled) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildWarningBanner(
                    "Usage Access Missing",
                    "Required for App Limits & Stats.",
                    () => state.requestUsageAccessPermission(),
                  ),
                );
              },
            ),
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Blocks",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Help Center - Blocker setup and access guidance.",
                        ),
                        backgroundColor: Colors.white10,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Help",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // App Limits Section Header
            Row(
              children: [
                const Text(
                  "App Limits",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (!_isLocked)
                  GestureDetector(
                    onTap: () async {
                      final hasAccess = await state.hasUsageAccessPermission();
                      if (!hasAccess) {
                        _showPermissionAlert(
                          title: "USAGE ACCESS REQUIRED",
                          description:
                              "To track app usage and enforce limits, you need to enable Usage Access in Android settings.",
                          onFix: () => state.requestUsageAccessPermission(),
                        );
                        return;
                      }
                      _showAddAppLimitDialog();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.green.withOpacity(0.4),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.add, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            "Add App",
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // App Limits List
            if (_dailyLimits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  "No limits set. Tap Add App to configure.",
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              )
            else
              ..._dailyLimits.entries.map((entry) {
                final appName = entry.key;
                final minutesLimit = entry.value;
                final emergencyUses = _emergencyUseCounts[appName] ?? 3;

                return GestureDetector(
                  onTap: _isLocked
                      ? null
                      : () => _showEditAppLimitDialog(appName),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0F),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white10,
                              ),
                              child: Center(
                                child: Text(
                                  appName.isNotEmpty
                                      ? appName[0].toUpperCase()
                                      : 'A',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Limit: ${_formatMinutes(minutesLimit)} • Emergency: $emergencyUses/5",
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_isLocked)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        _showEditAppLimitDialog(appName),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white24,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.edit,
                                        color: Colors.white54,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _dailyLimits.remove(appName);
                                        _unproductiveApps.remove(appName);
                                        _emergencyUseCounts.remove(appName);
                                      });
                                      _saveSettings();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.redAccent.withOpacity(
                                            0.4,
                                          ),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (_isStrictMode) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                color: Colors.amber,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Strict mode is on till ${_formatStrictDate()}",
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 24),

            // Block Shorts (PRO) Header
            Row(
              children: [
                const Text(
                  "Block Shorts",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                _buildProPill(),
              ],
            ),
            const SizedBox(height: 16),

            // Shorts tiles
            _buildExpansionReelsTile(
              "YouTube Shorts",
              _blockYoutubeShorts,
              _allowOneYoutubeShort,
              (val) async {
                if (_isLocked) return;
                if (val) {
                  final enabled = await context.read<LauncherState>().isAccessibilityServiceEnabled();
                  if (!enabled) {
                    _showAccessibilityPermissionDialog();
                    return;
                  }
                }
                setState(() => _blockYoutubeShorts = val);
                _saveSettings();
              },
              (val) {
                if (_isLocked) return;
                setState(() => _allowOneYoutubeShort = val);
                _saveSettings();
              },
            ),
            _buildExpansionReelsTile(
              "Instagram Reels",
              _blockInstagramReels,
              _allowOneInstagramReel,
              (val) async {
                if (_isLocked) return;
                if (val) {
                  final enabled = await context.read<LauncherState>().isAccessibilityServiceEnabled();
                  if (!enabled) {
                    _showAccessibilityPermissionDialog();
                    return;
                  }
                }
                setState(() => _blockInstagramReels = val);
                _saveSettings();
              },
              (val) {
                if (_isLocked) return;
                setState(() => _allowOneInstagramReel = val);
                _saveSettings();
              },
            ),

            const SizedBox(height: 24),

            // Other blocks Header
            Row(
              children: [
                const Text(
                  "Other blocks",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                _buildProPill(),
              ],
            ),
            const SizedBox(height: 16),

            // Website block config tile
            GestureDetector(
              onTap: _isLocked ? null : _showWebConfigDialog,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12, width: 0.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language, color: Colors.white60, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Block Websites",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${_keywords.length} blocked domains & keywords",
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isStrictMode)
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            color: Colors.amber,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "Till ${_formatStrictDate()}",
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      )
                    else
                      const Icon(Icons.chevron_right, color: Colors.white30),
                  ],
                ),
              ),
            ),

            // Adult Content Shield (VPN)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Colors.white60, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Adult Content Shield",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "DNS Filter / SafeSearch Protection",
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _vpnContentFilter,
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.white60,
                    inactiveThumbColor: Colors.grey[800],
                    inactiveTrackColor: Colors.white10,
                    onChanged: _isLocked
                        ? null
                        : (val) async {
                            if (val) {
                              // VPN requires native permission which is handled by Android dialog usually, 
                              // but we can add a check if we want. For now, focus on the user's explicit asks.
                            }
                            setState(() => _vpnContentFilter = val);
                            _saveSettings();
                          },
                  ),
                ],
              ),
            ),

            // Monochrome Mode (Digital Friction)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.color_lens_outlined,
                    color: Colors.white60,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Monochrome Mode",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Grayscale rendering to reduce dopamine",
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _monochromeMode,
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.white60,
                    inactiveThumbColor: Colors.grey[800],
                    inactiveTrackColor: Colors.white10,
                    onChanged: _isLocked
                        ? null
                        : (val) async {
                            if (val) {
                              final hasSecure = await state.hasWriteSecureSettingsPermission();
                              if (!hasSecure) {
                                _showPermissionAlert(
                                  title: "SECURE SETTINGS REQUIRED",
                                  description:
                                      "System-wide monochrome mode requires a special permission that must be granted once via ADB:\n\nadb shell pm grant com.dixit.monophone android.permission.WRITE_SECURE_SETTINGS",
                                  onFix: null, // User must do this via PC
                                );
                                return;
                              }
                            }
                            setState(() => _monochromeMode = val);
                            _saveSettings();
                          },
                  ),
                ],
              ),
            ),

            // Notification Interception / Silence
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_off_outlined,
                    color: Colors.white60,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Silence Notifications",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Suppress alerts from blocked apps",
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _notificationSilence,
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.white60,
                    inactiveThumbColor: Colors.grey[800],
                    inactiveTrackColor: Colors.white10,
                    onChanged: _isLocked
                        ? null
                        : (val) async {
                            if (val) {
                              final allowed = await state
                                  .hasNotificationAccess();
                              if (!allowed) {
                                await state.requestNotificationAccess();
                                return;
                              }
                            }
                            setState(() => _notificationSilence = val);
                            _saveSettings();
                          },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),

            // Friction Overrides Config
            const Text(
              "Friction Overrides",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Friction Challenge Type Selection
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _frictionGate,
                  dropdownColor: Colors.black,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'countdown',
                      child: Text("Mindful countdown timer (30s)"),
                    ),
                    DropdownMenuItem(
                      value: 'breathing',
                      child: Text("Breathing exercise (60s)"),
                    ),
                    DropdownMenuItem(
                      value: 'typing',
                      child: Text("Long intentional phrase typing"),
                    ),
                  ],
                  onChanged: _isLocked
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _frictionGate = val);
                            _saveSettings();
                          }
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Strict Mode persistent config
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Strict Mode Persist",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Switch(
                        value: _isStrictMode,
                        activeThumbColor: Colors.redAccent,
                        activeTrackColor: Colors.redAccent.withOpacity(0.4),
                        inactiveThumbColor: Colors.grey[800],
                        inactiveTrackColor: Colors.white10,
                        onChanged: _isLocked
                            ? null
                            : (val) {
                                if (val) {
                                  _showDatePickerAndLock();
                                } else {
                                  _showUnlockChallenge();
                                }
                              },
                      ),
                    ],
                  ),
                  if (_isStrictMode) ...[
                    const SizedBox(height: 12),
                    Text(
                      "LOCKDOWN IS ACTIVE. Bypasses, app limits, and uninstallation are disabled until ${_formatStrictDate()}.",
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        height: 1.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleBlockTile(
    String label,
    String key,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white10,
            ),
            child: const Center(
              child: Icon(
                Icons.play_circle_outline,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (_isStrictMode) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: Colors.amber,
                        size: 10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Strict active till ${_formatStrictDate()}",
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white60,
            inactiveThumbColor: Colors.grey[800],
            inactiveTrackColor: Colors.white10,
            onChanged: _isLocked ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildExpansionReelsTile(
    String label,
    bool isEnabled,
    bool allowOne,
    ValueChanged<bool> onToggle,
    ValueChanged<bool> onAllowOneChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.only(left: 60, right: 16, bottom: 16),
        collapsedIconColor: Colors.white30,
        iconColor: Colors.white,
        title: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        leading: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white10,
          ),
          child: const Center(
            child: Icon(
              Icons.video_library_outlined,
              color: Colors.white70,
              size: 18,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: isEnabled,
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.white60,
              inactiveThumbColor: Colors.grey[800],
              inactiveTrackColor: Colors.white10,
              onChanged: _isLocked ? null : onToggle,
            ),
            const Icon(Icons.expand_more, color: Colors.white30),
          ],
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 16),
              const Text(
                "BLOCKING MODE",
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),
              _buildModeOption(
                "Block completely",
                "Blocks instantly on detection",
                !allowOne,
                () => onAllowOneChanged(false),
              ),
              const SizedBox(height: 12),
              _buildModeOption(
                "Allow 1 (Block on Scroll)",
                "View first, block when scrolling",
                allowOne,
                () => onAllowOneChanged(true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption(
    String title,
    String subtitle,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: _isLocked ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: isSelected
                ? Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProPill() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD54F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        "PRO",
        style: TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remaining = minutes % 60;
      if (remaining == 0) return "${hours}h";
      return "${hours}h ${remaining}m";
    }
    return "${minutes}m";
  }

  void _showEditAppLimitDialog(String appName) {
    final currentLimit = _dailyLimits[appName] ?? 60;
    final currentEmergency = _emergencyUseCounts[appName] ?? 3;
    final limitController = TextEditingController(
      text: currentLimit.toString(),
    );
    int emergencyCount = currentEmergency;
    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.black,
              shape: Border.all(color: Colors.white24),
              title: const Text(
                "EDIT APP LIMIT",
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 15,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    appName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: limitController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      labelText: "Daily limit (minutes)",
                      labelStyle: TextStyle(
                        color: Colors.white54,
                        fontFamily: 'monospace',
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Emergency uses per day",
                        style: TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (emergencyCount > 1) {
                                setDialogState(() => emergencyCount--);
                              }
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Center(
                                child: Text(
                                  "-",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 40,
                            alignment: Alignment.center,
                            child: Text(
                              "$emergencyCount",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (emergencyCount < 5) {
                                setDialogState(() => emergencyCount++);
                              }
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Center(
                                child: Text(
                                  "+",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Max 5 emergency uses per day • Each use = 5 minutes",
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(
                      color: Colors.white30,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final newLimit =
                        int.tryParse(limitController.text.trim()) ??
                        currentLimit;
                    setState(() {
                      _dailyLimits[appName] = newLimit;
                      _emergencyUseCounts[appName] = emergencyCount;
                    });
                    limitController.dispose();
                    Navigator.pop(context);
                    _saveSettings();
                  },
                  child: const Text(
                    "SAVE",
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── POPUPS & DIALOGS ───────────────────────────────────────────────────────

  void _showAddAppLimitDialog() {
    final state = context.read<LauncherState>();
    final nonLimitedApps = state.allApps
        .where((app) => !_dailyLimits.containsKey(app['name'] ?? ''))
        .toList();

    showDialog(
      context: context,
      builder: (_) {
        String? selectedAppName;
        return AlertDialog(
          backgroundColor: Colors.black,
          shape: Border.all(color: Colors.white24),
          title: const Text(
            "SET DAILY LIMIT",
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 15,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (nonLimitedApps.isEmpty)
                const Text(
                  "All apps configured.",
                  style: TextStyle(
                    color: Colors.white54,
                    fontFamily: 'monospace',
                  ),
                )
              else
                StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Column(
                      children: [
                        DropdownButton<String>(
                          value: selectedAppName,
                          dropdownColor: Colors.black,
                          hint: const Text(
                            "Select App",
                            style: TextStyle(
                              color: Colors.white30,
                              fontFamily: 'monospace',
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                          ),
                          isExpanded: true,
                          items: nonLimitedApps.map((app) {
                            return DropdownMenuItem<String>(
                              value: app['name'],
                              child: Text(
                                app['name'] ?? '',
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() => selectedAppName = val);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _appLimitMinutesController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                          ),
                          decoration: const InputDecoration(
                            labelText: "Limit in minutes",
                            labelStyle: TextStyle(
                              color: Colors.white54,
                              fontFamily: 'monospace',
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "CANCEL",
                style: TextStyle(
                  color: Colors.white30,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final limitMin =
                    int.tryParse(_appLimitMinutesController.text.trim()) ?? 60;
                if (selectedAppName != null) {
                  setState(() {
                    _dailyLimits[selectedAppName!] = limitMin;
                    _unproductiveApps.add(selectedAppName!);
                  });
                  _appLimitMinutesController.clear();
                  Navigator.pop(context);
                  _saveSettings();
                }
              },
              child: const Text(
                "ADD",
                style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showWebConfigDialog() {
    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.black,
              shape: Border.all(color: Colors.white24),
              title: const Text(
                "BLACKLIST MANAGER",
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 15,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _keywordController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                            ),
                            decoration: const InputDecoration(
                              hintText: "Add domain/keyword...",
                              hintStyle: TextStyle(
                                color: Colors.white30,
                                fontFamily: 'monospace',
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.white),
                          onPressed: () {
                            final txt = _keywordController.text
                                .trim()
                                .toLowerCase();
                            if (txt.isNotEmpty && !_keywords.contains(txt)) {
                              setState(() => _keywords.add(txt));
                              setDialogState(() {});
                              _keywordController.clear();
                              _saveSettings();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _keywords.length,
                        itemBuilder: (context, idx) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _keywords[idx],
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setState(() => _keywords.removeAt(idx));
                                  setDialogState(() {});
                                  _saveSettings();
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "DONE",
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDatePickerAndLock() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 2)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.redAccent,
              onPrimary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
            ), dialogTheme: DialogThemeData(backgroundColor: Colors.black),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _isStrictMode = true;
        _lockUntilDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      });
      await _saveSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Strict lock enabled till ${_formatStrictDate()}."),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else {
      setState(() => _isStrictMode = false);
    }
  }

  void _showUnlockChallenge() {
    if (_frictionGate == 'breathing') {
      _triggerBreathingChallenge();
    } else if (_frictionGate == 'typing') {
      _triggerTypingChallenge();
    } else {
      _triggerCountdownChallenge();
    }
  }

  // Challenge 1: Countdown
  void _triggerCountdownChallenge() {
    int duration = 5;
    Timer? t;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            t ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (duration > 0) {
                setDialogState(() => duration--);
              } else {
                timer.cancel();
              }
            });

            return AlertDialog(
              backgroundColor: Colors.black,
              shape: Border.all(color: Colors.white24),
              title: const Text(
                "WAIT MINDFULLY",
                style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Do you really want to change these rules? Pause and wait out the timer.",
                    style: TextStyle(
                      color: Colors.white54,
                      height: 1.5,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "$duration",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    t?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "GO BACK",
                    style: TextStyle(
                      color: Colors.white30,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: duration > 0
                      ? null
                      : () {
                          t?.cancel();
                          Navigator.pop(context);
                          setState(() {
                            _isStrictMode = false;
                            _lockUntilDate = null;
                          });
                          _saveSettings();
                        },
                  child: Text(
                    "UNLOCK",
                    style: TextStyle(
                      color: duration > 0 ? Colors.white12 : Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Challenge 2: Breathing
  void _triggerBreathingChallenge() {
    int count = 10;
    Timer? countdownTimer;
    double size = 100;
    bool isBreatheIn = true;
    Timer? scaleTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (
              timer,
            ) {
              if (count > 0) {
                setDialogState(() => count--);
              } else {
                timer.cancel();
                scaleTimer?.cancel();
              }
            });

            scaleTimer ??= Timer.periodic(const Duration(milliseconds: 3000), (
              timer,
            ) {
              setDialogState(() {
                isBreatheIn = !isBreatheIn;
                size = isBreatheIn ? 180 : 100;
              });
            });

            return AlertDialog(
              backgroundColor: Colors.black,
              shape: Border.all(color: Colors.white24),
              title: const Text(
                "BREATHE",
                style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Synchronize with the circle. Inhale as it grows, exhale as it shrinks.",
                    style: TextStyle(
                      color: Colors.white54,
                      height: 1.5,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 200,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 3000),
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                          border: Border.all(color: Colors.white30, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            isBreatheIn ? "IN" : "OUT",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Seconds remaining: $count",
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    scaleTimer?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "ABORT",
                    style: TextStyle(
                      color: Colors.white30,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: count > 0
                      ? null
                      : () {
                          countdownTimer?.cancel();
                          scaleTimer?.cancel();
                          Navigator.pop(context);
                          setState(() {
                            _isStrictMode = false;
                            _lockUntilDate = null;
                          });
                          _saveSettings();
                        },
                  child: Text(
                    "DONE",
                    style: TextStyle(
                      color: count > 0 ? Colors.white12 : Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Challenge 3: Intentional Typing
  void _triggerTypingChallenge() {
    const targetText =
        "I am choosing to open this app intentionally and will close it in five minutes.";
    final textController = TextEditingController();
    bool matches = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.black,
              shape: Border.all(color: Colors.white24),
              title: const Text(
                "TYPE CHALLENGE",
                style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Type the following phrase exactly to prove intent:",
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFF0F0F0F),
                      child: const Text(
                        targetText,
                        style: TextStyle(
                          color: Colors.white70,
                          height: 1.4,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: textController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: "Start typing...",
                        hintStyle: TextStyle(
                          color: Colors.white24,
                          fontFamily: 'monospace',
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          matches = val.trim() == targetText;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    textController.dispose();
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(
                      color: Colors.white30,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: !matches
                      ? null
                      : () {
                          textController.dispose();
                          Navigator.pop(context);
                          setState(() {
                            _isStrictMode = false;
                            _lockUntilDate = null;
                          });
                          _saveSettings();
                        },
                  child: Text(
                    "UNLOCK",
                    style: TextStyle(
                      color: !matches ? Colors.white12 : Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Removed _buildCustomBottomNavBar and _buildNavBarItem

  Widget _buildWarningBanner(String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.redAccent.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.redAccent, size: 16),
          ],
        ),
      ),
    );
  }

  void _showPermissionAlert({
    required String title,
    required String description,
    VoidCallback? onFix,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: Border.all(color: Colors.white24),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 15,
          ),
        ),
        content: Text(
          description,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.white30, fontFamily: 'monospace'),
            ),
          ),
          if (onFix != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onFix();
              },
              child: const Text(
                "FIX NOW",
                style: TextStyle(color: Colors.green, fontFamily: 'monospace'),
              ),
            ),
        ],
      ),
    );
  }

  void _showAccessibilityPermissionDialog() {
    _showPermissionAlert(
      title: "ACCESSIBILITY REQUIRED",
      description:
          "To block Reels and Shorts, the Accessibility Service must be enabled. This allows the app to detect when you are in a scrolling video feed.",
      onFix: () => context.read<LauncherState>().openAccessibilitySettings(),
    );
  }
}
