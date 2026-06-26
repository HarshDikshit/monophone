import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/launcher_state.dart';
import '../../services/widget_panel_service.dart';
import '../permissions_dialog.dart';

// ---------------------------------------------------------------------------
// CLOCK WIDGET
// ---------------------------------------------------------------------------
class _ClockWidget extends StatefulWidget {
  const _ClockWidget();

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  late Timer _timer;
  String _timeString = '';
  String _dateString = '';

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _update() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final weekday = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ][now.weekday % 7];
    final month = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][now.month - 1];
    setState(() {
      _timeString = '$hour:$min';
      _dateString = '$weekday, $month ${now.day}'.toUpperCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _timeString,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w100,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          _dateString,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SCRATCHPAD WIDGET
// ---------------------------------------------------------------------------
class _ScratchpadWidget extends StatefulWidget {
  const _ScratchpadWidget();

  @override
  State<_ScratchpadWidget> createState() => _ScratchpadWidgetState();
}

class _ScratchpadWidgetState extends State<_ScratchpadWidget> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _controller.text = prefs.getString('scratchpad_text') ?? '';
    });
  }

  Future<void> _save(String val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scratchpad_text', val);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'THOUGHT DUMP',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'TYPE YOUR THOUGHTS FREELY. WRITING PERSISTS.',
          style: TextStyle(
            color: Colors.grey[750],
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white10),
            color: Colors.white.withOpacity(0.02),
          ),
          child: TextField(
            controller: _controller,
            maxLines: null,
            minLines: 5,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
            ),
            cursorColor: Colors.white,
            decoration: const InputDecoration(
              hintText: 'Start writing...',
              hintStyle: TextStyle(color: Colors.white12),
              border: InputBorder.none,
            ),
            onChanged: _save,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MOTIVATIONAL QUOTE WIDGET
// ---------------------------------------------------------------------------
class _MotivationWidget extends StatelessWidget {
  const _MotivationWidget();

  static const _quotes = [
    'Deep work is the superpower of the 21st century. Stay focused.',
    'A distracted mind is a defeated mind. Reclaim your focus.',
    'Disconnect to reconnect. Your future self is waiting.',
    'Focus on your North Star. Short-term distractions yield long-term regrets.',
    'Concentrate all your thoughts upon the work at hand.',
    'The key to success is to focus your mind on the things you want, not the things you fear.',
    'Your focus determines your reality.',
    'The ability to concentrate and use your time well is everything.',
    "Don't let the noise of others' opinions drown out your own inner voice.",
    'Success is the sum of small efforts, repeated day in and day out.',
  ];

  @override
  Widget build(BuildContext context) {
    final idx = DateTime.now().millisecondsSinceEpoch % _quotes.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.white38, width: 2)),
      ),
      child: Text(
        '"${_quotes[idx]}"',
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 12,
          height: 1.4,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QUICK ACTIONS WIDGET
// ---------------------------------------------------------------------------
class _QuickActionsWidget extends StatelessWidget {
  const _QuickActionsWidget();

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('POMODORO', '/pomodoro'),
      ('SOCIAL LOOP', '/social'),
      ('PARENTS', '/parent'),
      ('BLOCKER', '/blocker'),
      ('ANALYTICS', '/analytics'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: actions.map((a) {
              return GestureDetector(
                onTap: () => Navigator.pushNamed(context, a.$2),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    a.$1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ANALYTICS WIDGET
// ---------------------------------------------------------------------------
class _AnalyticsWidget extends StatefulWidget {
  const _AnalyticsWidget();

  @override
  State<_AnalyticsWidget> createState() => _AnalyticsWidgetState();
}

class _AnalyticsWidgetState extends State<_AnalyticsWidget> {
  String _tab = 'TODAY';

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    int studySec = 0;
    int distractedSec = 0;

    if (_tab == 'TODAY') {
      studySec = state.studySeconds;
      distractedSec = state.distractedSeconds;
    } else if (_tab == 'WEEKLY') {
      studySec = state.weeklyStudyData.values.fold(0, (a, b) => a + b);
      distractedSec = state.weeklyDistractedData.values.fold(
        0,
        (a, b) => a + b,
      );
    } else {
      studySec = state.monthlyStudySeconds;
      distractedSec = state.monthlyDistractedSeconds;
    }

    final focusStr = _format(studySec);
    final distractStr = _format(distractedSec);
    final ratio = studySec + distractedSec == 0
        ? '0%'
        : '${(studySec / (studySec + distractedSec) * 100).toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'STUDY ANALYTICS',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: ['TODAY', 'WEEKLY', 'MONTHLY'].map((label) {
            final isActive = _tab == label;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = label),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isActive ? Colors.black : Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard('FOCUS', focusStr),
            const SizedBox(width: 6),
            _statCard('DISTRACTED', distractStr),
            const SizedBox(width: 6),
            _statCard('RATIO', ratio),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white10),
          color: Colors.white.withOpacity(0.01),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white30,
                fontSize: 8,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _format(int sec) {
    if (sec <= 0) return '0m';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

// ---------------------------------------------------------------------------
// TASK BLOCKS WIDGET
// ---------------------------------------------------------------------------
class _TaskBlocksWidget extends StatelessWidget {
  const _TaskBlocksWidget();

  String _fmtDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final planner = state.planner;
    final now = DateTime.now();
    final todayTasks = (planner?.tasksForDate(now) ?? [])
        .where((t) => !t.isCompleted)
        .toList();

    if (todayTasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: const Text(
          'NO TASKS TODAY',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "TODAY'S TASKS",
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ...todayTasks.map((task) {
          final isActive = state.activeTaskId == task.id;
          final isRunning = state.isFocusActive && isActive;
          final scheduledMinutes = task.durationMinutes;
          final focusSeconds = task.focusSeconds;
          final isDone = task.isCompleted;

          return Container(
            key: ValueKey(task.id),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withOpacity(0.06)
                  : Colors.transparent,
              border: Border.all(
                color: isActive ? Colors.white38 : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          color: isDone
                              ? Colors.green.withOpacity(0.6)
                              : (isActive ? Colors.white : Colors.white70),
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmtDuration(focusSeconds)} / ${scheduledMinutes}m',
                        style: TextStyle(
                          color: focusSeconds > 0
                              ? Colors.greenAccent.withOpacity(0.7)
                              : Colors.white30,
                          fontFamily: 'monospace',
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: isRunning
                      ? null
                      : () {
                          state.switchActiveTask(
                            isActive ? null : task.id,
                            taskName: task.title,
                          );
                          if (!state.isFocusActive) {
                            state.startFocusTimer();
                          }
                        },
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isRunning ? Colors.white24 : Colors.white12,
                      ),
                      color: isRunning
                          ? Colors.white.withOpacity(0.1)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      isRunning ? Icons.pause : Icons.play_arrow,
                      color: isRunning ? Colors.white : Colors.greenAccent,
                      size: 16,
                    ),
                  ),
                ),
                if (isRunning)
                  GestureDetector(
                    onTap: () {
                      state.stopFocusTimer(manual: true);
                      state.switchActiveTask(null);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.5),
                        ),
                      ),
                      child: const Icon(
                        Icons.stop,
                        color: Colors.redAccent,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TASK BREAKDOWN WIDGET
// ---------------------------------------------------------------------------
class _TaskBreakdownWidget extends StatelessWidget {
  const _TaskBreakdownWidget();

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final tasks = state.tasks;

    if (tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: const Text(
          'NO TASKS DEFINED',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    final sorted = List<Map<String, dynamic>>.from(tasks)
      ..sort(
        (a, b) => (b['focusSeconds'] ?? 0).compareTo(a['focusSeconds'] ?? 0),
      );
    final total = sorted.fold<int>(
      0,
      (s, t) => s + ((t['focusSeconds'] as num?) ?? 0).toInt(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'TIME DISTRIBUTION BY TASK',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ...sorted.take(5).map((task) {
          final title = (task['title'] as String? ?? 'Untitled').toUpperCase();
          final sec = ((task['focusSeconds'] as num?) ?? 0).toInt();
          final pct = total > 0 ? (sec / total).clamp(0.0, 1.0) : 0.0;
          final dur = sec <= 0
              ? '0m'
              : '${sec ~/ 3600 > 0 ? '${sec ~/ 3600}h ' : ''}${(sec % 3600) ~/ 60}m';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      dur,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Stack(
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(pct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 8,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SYSTEM INFO WIDGET
// ---------------------------------------------------------------------------
class _SystemInfoWidget extends StatefulWidget {
  const _SystemInfoWidget();

  @override
  State<_SystemInfoWidget> createState() => _SystemInfoWidgetState();
}

class _SystemInfoWidgetState extends State<_SystemInfoWidget> {
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = '${info.version}+${info.buildNumber}');
    } catch (_) {
      setState(() => _appVersion = '1.0.0');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white10),
        color: Colors.white.withOpacity(0.02),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SYSTEM INFO',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _infoRow('App Version', _appVersion),
          _infoRow('Platform', Platform.operatingSystem.toUpperCase()),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ANDROID APP WIDGET
// ---------------------------------------------------------------------------
class _AndroidAppWidget extends StatelessWidget {
  final int appWidgetId;
  final String label;

  const _AndroidAppWidget({required this.appWidgetId, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white10),
        color: Colors.white.withOpacity(0.02),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Colors.white54,
                fontFamily: 'monospace',
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(
            height: 200,
            child: AndroidView(
              viewType: 'com.dixit.monophone/app_widget',
              creationParams: {'appWidgetId': appWidgetId},
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ADD WIDGET OVERLAY
// ---------------------------------------------------------------------------
class _AddWidgetOverlay extends StatefulWidget {
  final WidgetPanelService panelService;

  const _AddWidgetOverlay({required this.panelService});

  @override
  State<_AddWidgetOverlay> createState() => _AddWidgetOverlayState();
}

class _AddWidgetOverlayState extends State<_AddWidgetOverlay> {
  List<Map<String, dynamic>> _appWidgetProviders = [];
  bool _loadingProviders = false;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() => _loadingProviders = true);
    await widget.panelService.loadAppWidgetProviders();
    setState(() {
      _appWidgetProviders = widget.panelService.availableWidgetProviders;
      _loadingProviders = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final availableTypes = widget.panelService.availableWidgetTypes;

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ADD WIDGET',
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
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (availableTypes.isNotEmpty) ...[
                      const Text(
                        'LAUNCHER WIDGETS',
                        style: TextStyle(
                          color: Colors.grey,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...availableTypes
                          .where((t) => t != PanelWidgetType.androidAppWidget)
                          .map((type) {
                            return GestureDetector(
                              onTap: () {
                                widget.panelService.addWidget(type);
                                Navigator.pop(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Colors.white10),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      type.icon,
                                      color: Colors.white54,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            type.displayName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'monospace',
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            type.description,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontFamily: 'monospace',
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.add_circle_outline,
                                      color: Colors.white24,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                    ],

                    const SizedBox(height: 24),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 12),

                    const Text(
                      'ANDROID APP WIDGETS',
                      style: TextStyle(
                        color: Colors.grey,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loadingProviders)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: Colors.white24,
                          ),
                        ),
                      )
                    else if (_appWidgetProviders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.widgets_outlined,
                              color: Colors.white10,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'NO APP WIDGETS AVAILABLE',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Install apps with widgets (like Weather, Calendar) to see them here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._appWidgetProviders.map((provider) {
                        final providerName =
                            provider['providerName'] as String? ?? '';
                        final label = provider['label'] as String? ?? 'Unknown';
                        final packageName =
                            provider['packageName'] as String? ?? '';

                        return GestureDetector(
                          onTap: () async {
                            final success = await widget.panelService
                                .bindAppWidget(providerName);
                            if (success && context.mounted) {
                              Navigator.pop(context);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Failed to add widget. Try granting permission.',
                                    style: TextStyle(fontFamily: 'monospace'),
                                  ),
                                  backgroundColor: Colors.black,
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.white10),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.widgets,
                                  color: Colors.white54,
                                  size: 22,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        packageName,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.white24,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Renders a widget from its type
// ---------------------------------------------------------------------------
Widget _buildWidgetByType(WidgetPanelEntry entry) {
  switch (entry.type) {
    case PanelWidgetType.clock:
      return const _ClockWidget();
    case PanelWidgetType.scratchpad:
      return const _ScratchpadWidget();
    case PanelWidgetType.analytics:
      return const _AnalyticsWidget();
    case PanelWidgetType.taskBlocks:
      return const _TaskBlocksWidget();
    case PanelWidgetType.taskBreakdown:
      return const _TaskBreakdownWidget();
    case PanelWidgetType.quickActions:
      return const _QuickActionsWidget();
    case PanelWidgetType.motivation:
      return const _MotivationWidget();
    case PanelWidgetType.systemInfo:
      return const _SystemInfoWidget();
    case PanelWidgetType.androidAppWidget:
      return _AndroidAppWidget(
        appWidgetId: entry.config['appWidgetId'] as int? ?? 0,
        label: entry.config['label'] as String? ?? 'App Widget',
      );
  }
}

// ---------------------------------------------------------------------------
// MAIN WIDGET PANEL
// ---------------------------------------------------------------------------
class WidgetPanel extends StatefulWidget {
  final VoidCallback onClose;

  const WidgetPanel({super.key, required this.onClose});

  @override
  State<WidgetPanel> createState() => _WidgetPanelState();
}

class _WidgetPanelState extends State<WidgetPanel> {
  late WidgetPanelService _panelService;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _panelService = WidgetPanelService();
    _panelService.addListener(_onServiceChange);
    _panelService.load();
    _panelService.startWidgetHost();
    _panelService.loadAppWidgetProviders();
  }

  @override
  void dispose() {
    _panelService.removeListener(_onServiceChange);
    _panelService.stopWidgetHost();
    _panelService.dispose();
    super.dispose();
  }

  void _onServiceChange() {
    if (mounted) setState(() {});
  }

  Future<void> _showPermissions() async {
    final state = Provider.of<LauncherState>(context, listen: false);
    final perms = await state.checkAllPermissions();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Permissions dialog',
      builder: (ctx) => ChangeNotifierProvider.value(
        value: state,
        child: PermissionsDialog(permissions: perms),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final vel = details.primaryVelocity ?? 0;
        if (vel > 200) {
          widget.onClose();
        }
      },
      child: Container(
        color: Colors.black,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'LEFT PANEL',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    Row(
                      children: [
                        _iconBtn(Icons.add, 'Add widget', () {
                          showGeneralDialog(
                            context: context,
                            barrierDismissible: true,
                            barrierLabel: 'Add widget dialog',
                            barrierColor: Colors.black87,
                            transitionDuration: const Duration(
                              milliseconds: 200,
                            ),
                            pageBuilder: (ctx, a1, a2) =>
                                _AddWidgetOverlay(panelService: _panelService),
                          );
                        }),
                        const SizedBox(width: 8),
                        _iconBtn(Icons.shield_outlined, 'Permissions', () {
                          _showPermissions();
                        }),
                        const SizedBox(width: 8),
                        _iconBtn(Icons.close, 'Close panel', widget.onClose),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'LONG-PRESS to reorder • TAP ✕ to remove',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontFamily: 'monospace',
                    fontSize: 9,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),

                if (_editMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _editMode = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.redAccent.withOpacity(0.4),
                          ),
                          color: Colors.redAccent.withOpacity(0.05),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.close,
                              color: Colors.redAccent,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'TAP TO EXIT EDIT MODE',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontFamily: 'monospace',
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                Expanded(
                  child: _panelService.entries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.widgets_outlined,
                                color: Colors.grey[800],
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'NO WIDGETS ADDED',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () {
                                  showGeneralDialog(
                                    context: context,
                                    barrierDismissible: true,
                                    barrierLabel: 'Add widget dialog',
                                    barrierColor: Colors.black87,
                                    transitionDuration: const Duration(
                                      milliseconds: 200,
                                    ),
                                    pageBuilder: (ctx, a1, a2) =>
                                        _AddWidgetOverlay(
                                          panelService: _panelService,
                                        ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: const Text(
                                    'ADD WIDGET',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          itemCount: _panelService.entries.length,
                          onReorder: (oldIndex, newIndex) {
                            _panelService.reorderWidget(oldIndex, newIndex);
                          },
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, child) {
                                final double elevation =
                                    Tween<double>(begin: 0, end: 8)
                                        .animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeInOut,
                                          ),
                                        )
                                        .value;
                                return Material(
                                  color: Colors.transparent,
                                  elevation: elevation,
                                  shadowColor: Colors.white24,
                                  child: child,
                                );
                              },
                              child: child,
                            );
                          },
                          itemBuilder: (context, index) {
                            final entry = _panelService.entries[index];
                            return _buildWidgetCard(entry, index);
                          },
                        ),
                ),

                Center(
                  child: Text(
                    'SWIPE RIGHT TO RETURN',
                    style: TextStyle(
                      color: Colors.white12,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
            color: Colors.white.withOpacity(0.03),
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  Widget _buildWidgetCard(WidgetPanelEntry entry, int index) {
    return Container(
      key: ValueKey(entry.id),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white10),
          color: Colors.white.withOpacity(0.01),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
                color: _editMode
                    ? Colors.redAccent.withOpacity(0.05)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  if (_editMode)
                    Icon(Icons.drag_handle, color: Colors.white60, size: 20),
                  if (_editMode) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.type.displayName,
                      style: TextStyle(
                        color: _editMode ? Colors.white : Colors.white24,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  if (_editMode)
                    GestureDetector(
                      onTap: () => _panelService.removeWidget(entry.id),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.redAccent.withOpacity(0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.redAccent,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildWidgetByType(entry),
            ),
          ],
        ),
      );
  }
}
