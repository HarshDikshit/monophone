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
  // Navigation State
  int _selectedTab =
      0; // 0: Dashboard, 1: Rules Manager, 2: Strict Mode Settings

  // Channel & App Rules
  List<Map<String, String>> _channels = [];
  List<String> _unproductiveApps = [];

  // Strict Mode Configurations
  bool _isStrictMode = false;
  bool _blockReelsShorts = false;
  String _unlockOption = 'text'; // 'date', 'text', 'qr'
  DateTime? _lockUntilDate;
  String _randomChallengeText = '';
  String _challengeInputText = '';

  // Controllers for Add Forms
  final _channelController = TextEditingController();
  String _channelCategory = 'blocked'; // 'allowed' or 'blocked'
  final _appController = TextEditingController();
  final _challengeController = TextEditingController();

  // Simulated Live Activity Stream
  List<Map<String, dynamic>> _activityLogs = [];
  Timer? _simulationTimer;
  bool _isBlockedOverlayShowing = false;
  String _blockedActivityName = '';
  String _currentMotivationalQuote = '';

  // Default lists to pre-populate and use in simulations
  final List<Map<String, dynamic>> _predefinedSimulations = [
    {
      'name': 'MIT OpenCourseWare',
      'isApp': false,
      'isReels': false,
      'defaultType': 'allowed',
    },
    {
      'name': '3Blue1Brown',
      'isApp': false,
      'isReels': false,
      'defaultType': 'allowed',
    },
    {
      'name': 'Khan Academy',
      'isApp': false,
      'isReels': false,
      'defaultType': 'allowed',
    },
    {
      'name': 'Veritasium',
      'isApp': false,
      'isReels': false,
      'defaultType': 'allowed',
    },
    {
      'name': 'MrBeast',
      'isApp': false,
      'isReels': false,
      'defaultType': 'blocked',
    },
    {
      'name': 'PewDiePie',
      'isApp': false,
      'isReels': false,
      'defaultType': 'blocked',
    },
    {
      'name': 'YouTube Shorts',
      'isApp': false,
      'isReels': true,
      'defaultType': 'blocked',
    },
    {
      'name': 'Instagram Reels',
      'isApp': true,
      'isReels': true,
      'defaultType': 'blocked',
    },
    {
      'name': 'Instagram',
      'isApp': true,
      'isReels': false,
      'defaultType': 'blocked',
    },
    {
      'name': 'TikTok',
      'isApp': true,
      'isReels': false,
      'defaultType': 'blocked',
    },
    {
      'name': 'Facebook',
      'isApp': true,
      'isReels': false,
      'defaultType': 'blocked',
    },
    {
      'name': 'WhatsApp',
      'isApp': true,
      'isReels': false,
      'defaultType': 'allowed',
    },
    {
      'name': 'Pomodoro Focus Timer',
      'isApp': true,
      'isReels': false,
      'defaultType': 'allowed',
    },
    {
      'name': 'Gmail',
      'isApp': true,
      'isReels': false,
      'defaultType': 'allowed',
    },
  ];

  final List<String> _motivationalQuotes = [
    "Focus on your North Star. Short-term distractions yield long-term regrets.",
    "Deep work is the superpower of the 21st century. Keep pushing forward.",
    "The successful warrior is the average man, with laser-like focus. — Bruce Lee",
    "Only those who fall asleep on the wheel miss the destination. Stay awake, stay focused.",
    "Disconnect to reconnect. Your future self is waiting for your attention today.",
    "Concentrate all your thoughts upon the work at hand. The sun's rays do not burn until brought to a focus.",
    "A distracted mind is a defeated mind. Reclaim your focus.",
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startActivitySimulation();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _channelController.dispose();
    _appController.dispose();
    _challengeController.dispose();
    super.dispose();
  }

  // Load and Save Configurations in LocalStorage (SharedPreferences)
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isStrictMode = prefs.getBool('focustube_strict_mode') ?? false;
      _blockReelsShorts =
          prefs.getBool('focustube_block_reels_shorts') ?? false;
      _unlockOption = prefs.getString('focustube_unlock_option') ?? 'text';

      final lockUntilStr = prefs.getString('focustube_lock_until') ?? '';
      if (lockUntilStr.isNotEmpty) {
        _lockUntilDate = DateTime.tryParse(lockUntilStr);
      }

      _randomChallengeText = prefs.getString('focustube_challenge_text') ?? '';
      if (_randomChallengeText.isEmpty) {
        _randomChallengeText = _generateRandomString(100);
      }

      // Load Channels
      final channelsJson = prefs.getString('focustube_channels') ?? '';
      if (channelsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(channelsJson) as List;
          _channels = decoded
              .map((item) => Map<String, String>.from(item))
              .toList();
        } catch (_) {
          _loadDefaultRules();
        }
      } else {
        _loadDefaultRules();
      }

      // Load Apps
      _unproductiveApps =
          prefs.getStringList('focustube_blocked_apps') ??
          ['Instagram', 'TikTok', 'Facebook'];
    });
  }

  void _loadDefaultRules() {
    _channels = [
      {'name': 'MIT OpenCourseWare', 'type': 'allowed'},
      {'name': '3Blue1Brown', 'type': 'allowed'},
      {'name': 'MrBeast', 'type': 'blocked'},
      {'name': 'PewDiePie', 'type': 'blocked'},
    ];
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focustube_strict_mode', _isStrictMode);
    await prefs.setBool('focustube_block_reels_shorts', _blockReelsShorts);
    await prefs.setString('focustube_unlock_option', _unlockOption);
    await prefs.setString(
      'focustube_lock_until',
      _lockUntilDate?.toIso8601String() ?? '',
    );
    await prefs.setString('focustube_challenge_text', _randomChallengeText);
    await prefs.setString('focustube_channels', jsonEncode(_channels));
    await prefs.setStringList('focustube_blocked_apps', _unproductiveApps);

    // Reload the singleton so the launcher immediately picks up the new rules.
    await BlockerService.instance.load();

    // If reels/shorts blocking is on, start the app monitoring service with
    // the social apps added to the block list.  This gives reliable blocking
    // (Samsung OneUI doesn't expose Reels/Shorts UI through accessibility,
    // so we block the parent app instead).
    if (_blockReelsShorts) {
      final launcherState = context.read<LauncherState>();
      final socialPackages = launcherState.allApps
          .where((app) {
            final name = (app['name'] ?? '').toLowerCase();
            return name.contains('instagram') ||
                name.contains('youtube') ||
                name.contains('tiktok') ||
                name.contains('facebook') ||
                name.contains('snapchat') ||
                name.contains('reels') ||
                name.contains('shorts');
          })
          .map((app) => app['packageName'] ?? '')
          .where((pkg) => pkg.isNotEmpty)
          .toList();
      if (socialPackages.isNotEmpty) {
        await launcherState.startAppMonitoring(socialPackages);
      }
    } else {
      // Reels blocking is off — stop the monitoring service.
      try {
        await context.read<LauncherState>().stopAppMonitoring();
      } catch (_) {}
    }
  }

  // Helper to generate a random 100-character alphanumeric text challenge
  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()';
    final random = Random();
    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  // Real-time Simulated Activity Stream
  void _startActivitySimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isBlockedOverlayShowing) return;

      final random = Random();

      // Determine what to visit
      // 60% chance to visit a channel, 40% to use an app (including Reels)
      final useApp = random.nextBool();
      String name = '';
      bool isApp = false;
      bool isReels = false;

      // Make a pool of options from predefined lists + user entries
      if (useApp) {
        isApp = true;
        // Combine predefined apps + custom user apps
        final List<String> appPool = [];
        for (var sim in _predefinedSimulations) {
          if (sim['isApp'] == true) {
            appPool.add(sim['name']);
          }
        }
        for (var app in _unproductiveApps) {
          if (!appPool.contains(app)) {
            appPool.add(app);
          }
        }
        name = appPool[random.nextInt(appPool.length)];
        isReels = name.toLowerCase().contains('reels');
      } else {
        isApp = false;
        final List<String> channelPool = [];
        for (var sim in _predefinedSimulations) {
          if (sim['isApp'] == false) {
            channelPool.add(sim['name']);
          }
        }
        for (var ch in _channels) {
          final chName = ch['name'] ?? '';
          if (chName.isNotEmpty && !channelPool.contains(chName)) {
            channelPool.add(chName);
          }
        }
        name = channelPool[random.nextInt(channelPool.length)];
        isReels = name.toLowerCase().contains('shorts');
      }

      // Check if blocked
      final blocked = _checkIfBlocked(name, isApp, isReels);

      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      setState(() {
        _activityLogs.insert(0, {
          'time': timeStr,
          'message': isApp ? 'Using App: $name' : 'Visiting Channel: $name',
          'blocked': blocked,
        });

        if (_activityLogs.length > 20) {
          _activityLogs.removeLast();
        }

        if (blocked) {
          _blockedActivityName = name;
          _isBlockedOverlayShowing = true;
          _currentMotivationalQuote =
              _motivationalQuotes[random.nextInt(_motivationalQuotes.length)];
        }
      });
    });
  }

  bool _checkIfBlocked(String name, bool isApp, bool isReels) {
    if (isReels && _blockReelsShorts) {
      return true;
    }

    if (isApp) {
      // Check user productive/unproductive custom apps list
      return _unproductiveApps.any(
        (app) => app.toLowerCase().trim() == name.toLowerCase().trim(),
      );
    } else {
      // Check YouTube channels
      final match = _channels.firstWhere(
        (ch) =>
            (ch['name'] ?? '').toLowerCase().trim() ==
            name.toLowerCase().trim(),
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        return match['type'] == 'blocked';
      }
      // If not in user channels, check predefined ones
      final predef = _predefinedSimulations.firstWhere(
        (sim) => sim['name'].toLowerCase().trim() == name.toLowerCase().trim(),
        orElse: () => {},
      );
      if (predef.isNotEmpty) {
        return predef['defaultType'] == 'blocked';
      }
    }
    return false;
  }

  // --- Strict Mode Unlock Operations ---
  void _lockStrictMode() {
    if (_unlockOption == 'date') {
      if (_lockUntilDate == null || _lockUntilDate!.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please select a valid future Date and Time to lock.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() {
      _isStrictMode = true;
      _randomChallengeText = _generateRandomString(100);
      _challengeInputText = '';
      _challengeController.clear();
      _selectedTab = 0; // jump back to dashboard
    });
    _saveSettings();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('STRICT LOCKDOWN ACTIVE. Content management locked.'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _unlockStrictMode() {
    if (_unlockOption == 'date') {
      if (_lockUntilDate != null && DateTime.now().isBefore(_lockUntilDate!)) {
        final diff = _lockUntilDate!.difference(DateTime.now());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Locked until date is active. Remaining: ${diff.inHours}h ${diff.inMinutes % 60}m',
            ),
            backgroundColor: Colors.amber,
          ),
        );
        return;
      }
    } else if (_unlockOption == 'text') {
      if (_challengeInputText.trim() != _randomChallengeText.trim()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Challenge text does not match. Please verify character case and symbols.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() {
      _isStrictMode = false;
      _lockUntilDate = null;
      _challengeInputText = '';
      _challengeController.clear();
    });
    _saveSettings();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Strict Mode disabled successfully.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // Add rule validators
  void _addChannelRule() {
    final name = _channelController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube Channel Name cannot be empty.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final exists = _channels.any(
      (ch) => (ch['name'] ?? '').toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This channel rule already exists.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() {
      _channels.add({'name': name, 'type': _channelCategory});
      _channelController.clear();
    });
    _saveSettings();
  }

  void _addAppRule() {
    final name = _appController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('App Name cannot be empty.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final exists = _unproductiveApps.any(
      (app) => app.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This app is already on the unproductive list.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() {
      _unproductiveApps.add(name);
      _appController.clear();
    });
    _saveSettings();
  }

  void _deleteChannelRule(int index) {
    if (_isStrictMode) return;
    setState(() {
      _channels.removeAt(index);
    });
    _saveSettings();
  }

  void _deleteAppRule(String appName) {
    if (_isStrictMode) return;
    setState(() {
      _unproductiveApps.remove(appName);
    });
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'FOCUSTUBE & APP BLOCKER',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                letterSpacing: 2,
                fontSize: 14,
              ),
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSidebar(),
                    Container(width: 1, color: Colors.white12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: _buildSelectedTabContent(isWide),
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildTopTabBar(),
                    Container(height: 1, color: Colors.white12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SingleChildScrollView(
                          child: _buildSelectedTabContent(isWide),
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ),

        // BLOCK TRIGGERED Overlays
        if (_isBlockedOverlayShowing) _buildBlockOverlay(),
      ],
    );
  }

  // Sidebar navigation panel (wide screens)
  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isStrictMode ? Icons.shield_rounded : Icons.shield_outlined,
                color: _isStrictMode ? Colors.redAccent : Colors.blueAccent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isStrictMode ? 'STRICT LOCK' : 'NORMAL MODE',
                  style: TextStyle(
                    color: _isStrictMode ? Colors.redAccent : Colors.blueAccent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildSidebarNavItem(0, 'Overview', Icons.dashboard),
          _buildSidebarNavItem(1, 'Rules Manager', Icons.list_alt),
          _buildSidebarNavItem(2, 'Strict Settings', Icons.security),
          const Spacer(),
          Text(
            'SANDBOX BLOCKER V1.0',
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem(int tabIndex, String label, IconData icon) {
    final isSelected = _selectedTab == tabIndex;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = tabIndex),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.05)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white24 : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white30,
              size: 18,
            ),
            const SizedBox(width: 16),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Top navigation panel (mobile screens)
  Widget _buildTopTabBar() {
    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTopTabItem(0, 'OVERVIEW', Icons.dashboard),
          _buildTopTabItem(1, 'RULES', Icons.list_alt),
          _buildTopTabItem(2, 'STRICT', Icons.security),
        ],
      ),
    );
  }

  Widget _buildTopTabItem(int tabIndex, String label, IconData icon) {
    final isSelected = _selectedTab == tabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = tabIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white24,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white30,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Master selector of tab screens
  Widget _buildSelectedTabContent(bool isWide) {
    switch (_selectedTab) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildRulesManagerTab(isWide);
      case 2:
        return _buildStrictModeSettingsTab(isWide);
      default:
        return _buildDashboardTab();
    }
  }

  // ----------------------------------------------------
  // TAB 1: DASHBOARD
  // ----------------------------------------------------
  Widget _buildDashboardTab() {
    final blockedChannelsCount = _channels
        .where((ch) => ch['type'] == 'blocked')
        .length;
    final allowedChannelsCount = _channels
        .where((ch) => ch['type'] == 'allowed')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'DASHBOARD OVERVIEW',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 18,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 20),

        // Stats summary layout
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.2,
          children: [
            _buildStatCard(
              'ACTIVE MODE',
              _isStrictMode ? 'STRICT LOCK' : 'NORMAL MODE',
              _isStrictMode ? Colors.redAccent : Colors.greenAccent,
              _isStrictMode ? Icons.lock : Icons.lock_open,
            ),
            _buildStatCard(
              'YOUTUBE RULES',
              '$blockedChannelsCount Blocked\n$allowedChannelsCount Allowed',
              Colors.white,
              Icons.video_library,
            ),
            _buildStatCard(
              'APP RESTRICTIONS',
              '${_unproductiveApps.length} Unproductive\n${_blockReelsShorts ? "Shorts/Reels Blocked" : "Shorts/Reels Allowed"}',
              Colors.white,
              Icons.phone_android,
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Activity Log Panel — use ConstrainedBox so it works inside
        // both SingleChildScrollView (mobile) and Row/Expanded (wide).
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 300, maxHeight: 480),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF080808),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildPulsingDot(),
                        const SizedBox(width: 10),
                        const Text(
                          'RULE ENGINE — ACTIVITY LOG',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Blocking is enforced on app launch. Green = allowed by your rules, Red = blocked.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: _activityLogs.isEmpty
                      ? const Center(
                          child: Text(
                            'WAITING FOR ACTIVITY...',
                            style: TextStyle(
                              color: Colors.white24,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _activityLogs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final log = _activityLogs[index];
                            final isBlocked = log['blocked'] == true;
                            return Row(
                              children: [
                                Text(
                                  '[${log['time']}]',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    log['message'] ?? '',
                                    style: TextStyle(
                                      color: isBlocked
                                          ? Colors.redAccent
                                          : Colors.greenAccent.withOpacity(0.8),
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isBlocked
                                          ? Colors.red.withOpacity(0.3)
                                          : Colors.green.withOpacity(0.3),
                                    ),
                                    color: isBlocked
                                        ? Colors.red.withOpacity(0.08)
                                        : Colors.green.withOpacity(0.08),
                                  ),
                                  child: Text(
                                    isBlocked ? 'BLOCKED' : 'ALLOWED',
                                    style: TextStyle(
                                      color: isBlocked
                                          ? Colors.redAccent
                                          : Colors.greenAccent,
                                      fontSize: 9,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color valueColor,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF080808),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 10,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: Colors.white12, size: 28),
        ],
      ),
    );
  }

  Widget _buildPulsingDot() {
    return const _PulsingIndicator();
  }

  // ----------------------------------------------------
  // TAB 2: CHANNEL & APP RULES MANAGER
  // ----------------------------------------------------
  Widget _buildRulesManagerTab(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'RULES & CATEGORIES',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (_isStrictMode)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  color: Colors.redAccent.withOpacity(0.1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, color: Colors.redAccent, size: 12),
                    SizedBox(width: 6),
                    Text(
                      'LOCKED BY STRICT MODE',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 9,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Add custom channel names or app packages and assign allowed or blocked statuses.',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 24),

        // FORMS SECTION
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildChannelRuleForm()),
              const SizedBox(width: 32),
              Expanded(child: _buildAppRuleForm()),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildChannelRuleForm(),
              const SizedBox(height: 32),
              _buildAppRuleForm(),
            ],
          ),

        const SizedBox(height: 32),
        Container(height: 1, color: Colors.white10),
        const SizedBox(height: 24),

        // RULES LIST
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildChannelRulesList()),
              const SizedBox(width: 32),
              Expanded(child: _buildAppRulesList()),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildChannelRulesList(),
              const SizedBox(height: 32),
              _buildAppRulesList(),
            ],
          ),
      ],
    );
  }

  Widget _buildChannelRuleForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'ADD YOUTUBE CHANNEL',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _channelController,
          enabled: !_isStrictMode,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'ENTER CHANNEL NAME...',
            hintStyle: TextStyle(color: Colors.grey[850], letterSpacing: 1),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white12),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            disabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white10),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'CATEGORY: ',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            // Blocked Selector
            GestureDetector(
              onTap: _isStrictMode
                  ? null
                  : () => setState(() => _channelCategory = 'blocked'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _channelCategory == 'blocked'
                        ? Colors.redAccent
                        : Colors.white12,
                  ),
                  color: _channelCategory == 'blocked'
                      ? Colors.redAccent.withOpacity(0.08)
                      : Colors.transparent,
                ),
                child: Text(
                  'UNPRODUCTIVE (BLOCK)',
                  style: TextStyle(
                    color: _channelCategory == 'blocked'
                        ? Colors.redAccent
                        : Colors.grey[600],
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: _channelCategory == 'blocked'
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
            // Allowed Selector
            GestureDetector(
              onTap: _isStrictMode
                  ? null
                  : () => setState(() => _channelCategory = 'allowed'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _channelCategory == 'allowed'
                        ? Colors.greenAccent
                        : Colors.white12,
                  ),
                  color: _channelCategory == 'allowed'
                      ? Colors.greenAccent.withOpacity(0.08)
                      : Colors.transparent,
                ),
                child: Text(
                  'PRODUCTIVE (ALLOW)',
                  style: TextStyle(
                    color: _channelCategory == 'allowed'
                        ? Colors.greenAccent
                        : Colors.grey[600],
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: _channelCategory == 'allowed'
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _isStrictMode ? null : _addChannelRule,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: _isStrictMode ? Colors.transparent : Colors.white,
              border: Border.all(
                color: _isStrictMode ? Colors.white10 : Colors.white,
              ),
            ),
            child: Center(
              child: Text(
                'ADD CHANNEL RULE',
                style: TextStyle(
                  color: _isStrictMode ? Colors.white24 : Colors.black,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppRuleForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'ADD UNPRODUCTIVE APP',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        // Text input (keep for custom/non-installed apps)
        TextField(
          controller: _appController,
          enabled: !_isStrictMode,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'TYPE APP NAME (e.g., TikTok)...',
            hintStyle: TextStyle(color: Colors.grey[850], letterSpacing: 1),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white12),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            disabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // OR divider
        Row(
          children: [
            const Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        const SizedBox(height: 8),
        // Pick from installed apps button
        GestureDetector(
          onTap: _isStrictMode ? null : () => _showInstalledAppPicker(),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              color: _isStrictMode
                  ? Colors.transparent
                  : Colors.white.withOpacity(0.05),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.apps,
                    color: _isStrictMode ? Colors.white24 : Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'PICK FROM INSTALLED APPS',
                    style: TextStyle(
                      color: _isStrictMode ? Colors.white24 : Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Manual add button
        GestureDetector(
          onTap: _isStrictMode ? null : _addAppRule,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: _isStrictMode ? Colors.transparent : Colors.white,
              border: Border.all(
                color: _isStrictMode ? Colors.white10 : Colors.white,
              ),
            ),
            child: Center(
              child: Text(
                'ADD TYPED NAME TO BLOCKLIST',
                style: TextStyle(
                  color: _isStrictMode ? Colors.white24 : Colors.black,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Show a bottom sheet with all installed apps for easy selection.
  void _showInstalledAppPicker() {
    final launcherState = context.read<LauncherState>();
    final allApps = launcherState.allApps;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const Border(top: BorderSide(color: Colors.white12, width: 1)),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'INSTALLED APPS',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: allApps.isEmpty
                        ? const Center(
                            child: Text(
                              'No apps loaded',
                              style: TextStyle(
                                color: Colors.white24,
                                fontFamily: 'monospace',
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: allApps.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final app = allApps[index];
                              final name = app['name'] ?? 'Unknown';
                              final pkg = app['packageName'] ?? '';
                              final alreadyBlocked = _unproductiveApps.any(
                                (a) =>
                                    a.toLowerCase().trim() ==
                                    name.toLowerCase().trim(),
                              );
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.phone_android,
                                  color: alreadyBlocked
                                      ? Colors.redAccent
                                      : Colors.white38,
                                  size: 20,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    color: alreadyBlocked
                                        ? Colors.redAccent.withOpacity(0.6)
                                        : Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  pkg,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                  ),
                                ),
                                trailing: alreadyBlocked
                                    ? const Text(
                                        'BLOCKED',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontFamily: 'monospace',
                                          fontSize: 9,
                                        ),
                                      )
                                    : null,
                                onTap: alreadyBlocked || _isStrictMode
                                    ? null
                                    : () {
                                        setState(() {
                                          _unproductiveApps.add(name);
                                        });
                                        _saveSettings();
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '$name added to blocklist',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChannelRulesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'YOUTUBE CHANNEL RULES',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 12),
        _channels.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'NO YOUTUBE CHANNEL RULES ADDED',
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              )
            : ListView.separated(
                itemCount: _channels.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (context, idx) =>
                    const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final rule = _channels[index];
                  final name = rule['name'] ?? '';
                  final type = rule['type'] ?? 'blocked';
                  final isBlocked = type == 'blocked';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.video_library,
                          color: Colors.white24,
                          size: 14,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: Colors.white.withOpacity(
                                _isStrictMode ? 0.4 : 0.9,
                              ),
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isBlocked
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.green.withOpacity(0.3),
                            ),
                            color: isBlocked
                                ? Colors.red.withOpacity(0.05)
                                : Colors.green.withOpacity(0.05),
                          ),
                          child: Text(
                            isBlocked ? 'BLOCKED' : 'ALLOWED',
                            style: TextStyle(
                              color: isBlocked
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                              fontSize: 8,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            _isStrictMode ? Icons.lock : Icons.delete,
                            color: _isStrictMode
                                ? Colors.white12
                                : Colors.red.withOpacity(0.7),
                            size: 16,
                          ),
                          onPressed: _isStrictMode
                              ? null
                              : () => _deleteChannelRule(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }

  Widget _buildAppRulesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'UNPRODUCTIVE APPS BLOCKLIST',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 12),
        _unproductiveApps.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'NO BLOCKED APPS ADDED',
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              )
            : ListView.separated(
                itemCount: _unproductiveApps.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (context, idx) =>
                    const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final appName = _unproductiveApps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.phone_android,
                          color: Colors.white24,
                          size: 14,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            appName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(
                                _isStrictMode ? 0.4 : 0.9,
                              ),
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.redAccent.withOpacity(0.3),
                            ),
                            color: Colors.redAccent.withOpacity(0.05),
                          ),
                          child: const Text(
                            'BLOCKED APP',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 8,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            _isStrictMode ? Icons.lock : Icons.delete,
                            color: _isStrictMode
                                ? Colors.white12
                                : Colors.red.withOpacity(0.7),
                            size: 16,
                          ),
                          onPressed: _isStrictMode
                              ? null
                              : () => _deleteAppRule(appName),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }

  // ----------------------------------------------------
  // TAB 3: STRICT MODE SETTINGS
  // ----------------------------------------------------
  Widget _buildStrictModeSettingsTab(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'STRICT MODE INTERFACE',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 18,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Lock your categories down to prevent impulsive editing or rule removal.',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 24),

        // Lock switch indicator & reels block toggle
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            border: Border.all(
              color: _isStrictMode
                  ? Colors.redAccent.withOpacity(0.3)
                  : Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isStrictMode
                              ? 'STRICT LOCKDOWN ACTIVE'
                              : 'STRICT MODE INACTIVE',
                          style: TextStyle(
                            color: _isStrictMode
                                ? Colors.redAccent
                                : Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isStrictMode
                              ? 'All add/delete controls are disabled. Unlock using your chosen method below.'
                              : 'Normal edits are active. Toggle below to lock all configurations.',
                          style: TextStyle(
                            color: Colors.grey[650],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    _isStrictMode ? Icons.security : Icons.lock_open,
                    color: _isStrictMode ? Colors.redAccent : Colors.white24,
                    size: 24,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(height: 1, color: Colors.white10),
              const SizedBox(height: 16),

              // REELS & SHORTS BLOCK TOGGLE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BLOCK REELS & SHORTS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Instantly blocks all simulated visits to YouTube Shorts & Instagram Reels.',
                          style: TextStyle(color: Colors.white30, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: _blockReelsShorts,
                    activeColor: Colors.blueAccent,
                    activeTrackColor: Colors.blueAccent.withOpacity(0.3),
                    inactiveThumbColor: Colors.grey[750],
                    inactiveTrackColor: Colors.white10,
                    onChanged: _isStrictMode
                        ? null
                        : (val) {
                            setState(() => _blockReelsShorts = val);
                            _saveSettings();
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Choose / Render unlocking mechanisms
        Text(
          'UNLOCKING MECHANISM OPTIONS',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 16),

        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _buildUnlockOptionsList()),
              const SizedBox(width: 32),
              Expanded(flex: 3, child: _buildUnlockConfigContainer()),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUnlockOptionsList(),
              const SizedBox(height: 24),
              _buildUnlockConfigContainer(),
            ],
          ),
      ],
    );
  }

  Widget _buildUnlockOptionsList() {
    return Column(
      children: [
        _buildUnlockOptionTile(
          'date',
          'OPTION A: DATE LOCK',
          'Disables unlocking until a specific future date and time timestamp.',
          Icons.calendar_today,
        ),
        const SizedBox(height: 12),
        _buildUnlockOptionTile(
          'text',
          'OPTION B: TEXT CHALLENGE',
          'Requires typing a randomized 100-character string perfectly.',
          Icons.keyboard,
        ),
        const SizedBox(height: 12),
        _buildUnlockOptionTile(
          'qr',
          'OPTION C: FRIEND\'S QR CODE',
          'Generates a lockdown QR code. Scan code to simulate verification.',
          Icons.qr_code,
        ),
      ],
    );
  }

  Widget _buildUnlockConfigContainer() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF080808),
        border: Border.all(color: Colors.white12),
      ),
      child: _isStrictMode
          ? _buildActiveUnlockInterface()
          : _buildConfigLockInterface(),
    );
  }

  Widget _buildUnlockOptionTile(
    String option,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = _unlockOption == option;
    final isLocked = _isStrictMode; // can't change unlock option when locked

    return GestureDetector(
      onTap: isLocked ? null : () => setState(() => _unlockOption = option),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.04)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white30 : Colors.white10,
          ),
        ),
        child: Opacity(
          opacity: isLocked && !isSelected ? 0.3 : 1.0,
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.blueAccent : Colors.white30,
                size: 20,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[650], fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Right configuration panel BEFORE lock is active
  Widget _buildConfigLockInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CONFIGURE LOCK PARAMETERS',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 16),

        if (_unlockOption == 'date') ...[
          const Text(
            'Select a future lock date and time. Interface changes will remain locked until this date passes.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pickLockDateTime,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white30),
              ),
              child: Center(
                child: Text(
                  _lockUntilDate == null
                      ? 'CHOOSE DATE & TIME'
                      : 'LOCK UNTIL: ${_lockUntilDate!.year}-${_lockUntilDate!.month.toString().padLeft(2, '0')}-${_lockUntilDate!.day.toString().padLeft(2, '0')} ${_lockUntilDate!.hour.toString().padLeft(2, '0')}:${_lockUntilDate!.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ] else if (_unlockOption == 'text') ...[
          const Text(
            'Option Selected: Text Challenge.\nUpon activating strict mode, a 100-character challenge string will be randomized. To unlock, you must type this string exactly.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ] else if (_unlockOption == 'qr') ...[
          const Text(
            'Option Selected: Friend\'s QR Code Approval.\nStrict mode generates a unique QR code. You can scan it to simulate verification from a study buddy or friend.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ],

        const SizedBox(height: 32),
        GestureDetector(
          onTap: _lockStrictMode,
          child: Container(
            height: 44,
            color: Colors.redAccent,
            child: const Center(
              child: Text(
                'LOCK INTERFACE DOWN',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickLockDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.grey[900],
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return;

    if (!mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              surface: Colors.black,
            ),
            dialogBackgroundColor: Colors.grey[900],
          ),
          child: child!,
        );
      },
    );

    if (pickedTime == null) return;

    setState(() {
      _lockUntilDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  // Right configuration panel AFTER lock is active
  Widget _buildActiveUnlockInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'VERIFY TO UNLOCK INTERFACE',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 16),

        if (_unlockOption == 'date') ...[
          Text(
            'Unlock requires waiting for the lock date and time to expire.',
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
          const SizedBox(height: 16),
          // Time countdown box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                const Icon(Icons.timer, color: Colors.white30, size: 24),
                const SizedBox(height: 10),
                Text(
                  _lockUntilDate == null
                      ? 'EXPIRED'
                      : _lockUntilDate!.isBefore(DateTime.now())
                      ? 'TIME ELAPSED: READY'
                      : 'COUNTDOWN ACTIVE',
                  style: TextStyle(
                    color:
                        _lockUntilDate != null &&
                            _lockUntilDate!.isBefore(DateTime.now())
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getCountdownString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _unlockStrictMode,
            child: Container(
              height: 44,
              color:
                  _lockUntilDate != null &&
                      DateTime.now().isAfter(_lockUntilDate!)
                  ? Colors.green
                  : Colors.grey[850],
              child: Center(
                child: Text(
                  'DISABLE STRICT MODE',
                  style: TextStyle(
                    color:
                        _lockUntilDate != null &&
                            DateTime.now().isAfter(_lockUntilDate!)
                        ? Colors.black
                        : Colors.white24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ] else if (_unlockOption == 'text') ...[
          const Text(
            'Type the following 100-character string exactly as shown to disable Strict Mode:',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 12),
          // Random String display box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: Border.all(color: Colors.white24),
            ),
            child: SelectableText(
              _randomChallengeText,
              style: TextStyle(
                color: Colors.greenAccent.withOpacity(0.8),
                fontSize: 12,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Text challenges input
          TextField(
            controller: _challengeController,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            cursorColor: Colors.white,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'TYPE THE CHALLENGE TEXT HERE...',
              hintStyle: TextStyle(color: Colors.grey[850], letterSpacing: 1),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white12),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white38),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _challengeInputText = val;
              });
            },
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _unlockStrictMode,
            child: Container(
              height: 44,
              color: Colors.white,
              child: const Center(
                child: Text(
                  'VERIFY & UNLOCK',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ] else if (_unlockOption == 'qr') ...[
          const Text(
            'A mock unique verification QR code is generated. Share or scan it using our friend scanner overlay simulation.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 16),
          // QR Rendering
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(
                data: 'FocusTubeStrictLock:UnlockSignatureApprovedForUser',
                version: QrVersions.auto,
                size: 120.0,
                gapless: false,
              ),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _showCameraSimulation,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white),
              ),
              child: const Center(
                child: Text(
                  'SCAN LOCK APPROVAL QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _getCountdownString() {
    if (_lockUntilDate == null) return 'N/A';
    if (_lockUntilDate!.isBefore(DateTime.now())) return '00:00:00 - EXPIRED';

    final diff = _lockUntilDate!.difference(DateTime.now());
    final hours = diff.inHours.toString().padLeft(2, '0');
    final mins = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$mins:$secs REMAINING';
  }

  // Option C scan QR mock overlay view
  void _showCameraSimulation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.black,
              shape: const RoundedRectangleBorder(
                side: BorderSide(color: Colors.white24),
              ),
              child: Container(
                width: 320,
                height: 400,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SCANNER VIEW SIMULATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white60,
                            size: 16,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0C0C),
                          border: Border.all(
                            color: Colors.blueAccent.withOpacity(0.5),
                          ),
                        ),
                        child: const Stack(
                          children: [
                            // Viewfinder frame corner graphics
                            Align(
                              alignment: Alignment.center,
                              child: _ScanningViewfinder(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx); // Close dialog
                        setState(() {
                          _isStrictMode = false;
                          _lockUntilDate = null;
                        });
                        _saveSettings();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Verification QR code approved. Strict mode disabled.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      child: Container(
                        height: 44,
                        color: Colors.white,
                        child: const Center(
                          child: Text(
                            'SIMULATE FRIEND SCANNED',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------
  // BLOCK OVERLAY MOTIVATIONAL UI
  // ----------------------------------------------------
  Widget _buildBlockOverlay() {
    final studyChannels = _channels
        .where((ch) => ch['type'] == 'allowed')
        .map((ch) => ch['name'] ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    return Positioned.fill(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;

              if (isWide) {
                return Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 30,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Column: Icon and Blocked Header Info
                        Expanded(
                          flex: 11,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(
                                Icons.shield_rounded,
                                color: Colors.redAccent,
                                size: 96,
                              ),
                              const SizedBox(height: 32),
                              const Text(
                                'BLOCK TRIGGERED',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  letterSpacing: 6,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Distraction Terminated: [$_blockedActivityName]',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 48),
                              _buildResumeButton(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),
                        // Divider
                        Container(width: 1, color: Colors.white12, height: 320),
                        const SizedBox(width: 40),
                        // Right Column: Quotes & Channels
                        Expanded(
                          flex: 12,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildMotivationalQuoteWidget(),
                              if (studyChannels.isNotEmpty) ...[
                                const SizedBox(height: 32),
                                _buildStudyChannelsWidget(
                                  studyChannels,
                                  maxHeight: 180,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                // Mobile Portrait Layout
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 40.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        const Icon(
                          Icons.shield_rounded,
                          color: Colors.redAccent,
                          size: 64,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'BLOCK TRIGGERED',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Distraction Terminated: [$_blockedActivityName]',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildMotivationalQuoteWidget(),
                        if (studyChannels.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildStudyChannelsWidget(
                            studyChannels,
                            maxHeight: 150,
                          ),
                        ],
                        const SizedBox(height: 40),
                        _buildResumeButton(),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMotivationalQuoteWidget() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(left: BorderSide(color: Colors.redAccent, width: 3)),
      ),
      child: Text(
        '"$_currentMotivationalQuote"',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontStyle: FontStyle.italic,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildStudyChannelsWidget(
    List<String> studyChannels, {
    double maxHeight = 180,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'REGAIN FOCUS - STUDY CHANNELS TO VISIT:',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            border: Border.all(color: Colors.white10),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: studyChannels.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        studyChannels[index],
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResumeButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isBlockedOverlayShowing = false;
          _blockedActivityName = '';
        });
        // Resume the tick simulator
        _startActivitySimulation();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 55,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'RESUME FOCUS SESSION',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom pulsing animation widgets
class _PulsingIndicator extends StatefulWidget {
  const _PulsingIndicator();

  @override
  State<_PulsingIndicator> createState() => _PulsingIndicatorState();
}

class _PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_animController);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent,
        ),
      ),
    );
  }
}

// Scanning viewfinder widget with a scanning beam animation
class _ScanningViewfinder extends StatefulWidget {
  const _ScanningViewfinder();

  @override
  State<_ScanningViewfinder> createState() => _ScanningViewfinderState();
}

class _ScanningViewfinderState extends State<_ScanningViewfinder>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _animation = Tween<double>(begin: 0.1, end: 0.9).animate(_animController);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Camera square border brackets
        Center(
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 1),
            ),
          ),
        ),
        // Pulsing scanning laser line
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Positioned(
              left: 30,
              right: 30,
              top: 50 + (_animation.value * 140),
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
