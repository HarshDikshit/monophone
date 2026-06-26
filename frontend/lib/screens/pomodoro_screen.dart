import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/launcher_state.dart';
import '../services/task_planner_service.dart';
import '../widgets/task_edit_sheet.dart';

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatMinutes(int seconds) {
    if (seconds <= 0) return '0m';
    final m = seconds ~/ 60;
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final rem = m % 60;
    return rem == 0 ? '${h}h' : '${h}h ${rem}m';
  }



  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final isFullScreen = state.isFullScreen && state.isFocusActive;

    // Auto fullscreen: when timer is active, if user remains here, go fullscreen
    if (state.isFocusActive && !state.isFullScreen && mounted) {
      // We'll let the user manually toggle via the button below
    }

    Widget content = Scaffold(
      backgroundColor: Colors.black,
      appBar: isFullScreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'STOPWATCH',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                  fontSize: 14,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.settings,
                    color: Colors.white30,
                    size: 20,
                  ),
                  onPressed: () => _showSettingsSheet(context, state),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.bar_chart,
                    color: Colors.white30,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pushNamed(context, '/analytics'),
                ),
              ],
            ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isFullScreen ? 32.0 : 24.0,
            vertical: isFullScreen ? 40.0 : 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isFullScreen) ...[
                // ── Status label ──
                Text(
                  'DEEP FOCUS',
                  style: TextStyle(
                    color: Colors.grey[600],
                    letterSpacing: 4.0,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Distraction lock active. Stay on target.',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Task Selector Button ──
                Center(
                  child: GestureDetector(
                    onTap: () => _showTaskSelectionModal(context, state),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: state.activeTaskId != null
                                  ? Colors.redAccent
                                  : Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            state.activeTaskId != null
                                ? (state.activeTask?['title'] ??
                                      'Focus Session')
                                : 'Select a task...',
                            style: TextStyle(
                              color: state.activeTaskId != null
                                  ? Colors.white
                                  : Colors.white54,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              if (isFullScreen) const SizedBox(height: 20),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Active task name (always shown when pomodoro is running) ──
                      if (state.isFocusActive) ...[
                        Text(
                          state.activeTaskId != null
                              ? (state.activeTask?['title'] as String? ??
                                    state.lastGoal)
                              : state.lastGoal.isNotEmpty
                              ? state.lastGoal
                              : 'FOCUS SESSION',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'monospace',
                            fontSize: isFullScreen ? 13 : 11,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // ── Timer display ──
                      Column(
                        children: [
                          Text(
                            _formatTime(state.focusElapsedSeconds),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isFullScreen ? 96.0 : 72.0,
                              fontWeight: FontWeight.w100,
                              letterSpacing: 4.0,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'FOCUSING',
                            style: TextStyle(
                              color: state.isFocusActive
                                  ? Colors.white38
                                  : Colors.grey[850],
                              fontSize: isFullScreen ? 12 : 10,
                              letterSpacing: 3.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),

                      if (state.isFocusActive) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Stop when you\'re done',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 10,
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                      ],

                      // ── Fullscreen toggle (always visible) ──
                      if (state.isFocusActive) ...[
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: () => state.toggleFullScreen(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 14,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: state.isFullScreen
                                    ? Colors.white54
                                    : Colors.white12,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  state.isFullScreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  color: Colors.white38,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  state.isFullScreen
                                      ? 'EXIT FULLSCREEN'
                                      : 'FULLSCREEN',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 9,
                                    letterSpacing: 2,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Permission / stats hint ──
              if (!isFullScreen)
                Center(
                  child: FutureBuilder<bool>(
                    future: state.checkUsagePermission(),
                    builder: (context, snap) {
                      if (!(snap.data ?? false)) {
                        return TextButton(
                          onPressed: state.toggleUsagePermission,
                          child: const Text(
                            'GRANT USAGE STATS ACCESS TO ENABLE HARD LOCK',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white30,
                              fontSize: 9,
                              letterSpacing: 1,
                              decoration: TextDecoration.underline,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      }
                      return Text(
                        'TODAY: ${_formatMinutes(state.studySeconds)} FOCUSED',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
                ),

              if (!isFullScreen) const SizedBox(height: 12),

              // ── Start / Stop button ──
              GestureDetector(
                onTap: () {
                  if (state.isFocusActive) {
                    state.stopFocusTimer(manual: true);
                  } else {
                    state.startFocusTimer();
                  }
                },
                child: Container(
                  height: isFullScreen ? 56 : 52,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: state.isFocusActive
                          ? Colors.red.withOpacity(0.6)
                          : Colors.white,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      state.isFocusActive
                          ? 'ABANDON SESSION'
                          : 'INITIATE FOCUS',
                      style: TextStyle(
                        color: state.isFocusActive
                            ? Colors.red
                            : Colors.white,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: isFullScreen ? 14 : 13,
                      ),
                    ),
                  ),
                ),
              ),

              if (isFullScreen) ...[
                const SizedBox(height: 16),
                // In fullscreen show a compact mini version of extra controls
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: const Center(
                      child: Text(
                        '← BACK TO TIMER VIEW',
                        style: TextStyle(
                          color: Colors.white24,
                          fontSize: 9,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return content;
  }

  void _showSettingsSheet(BuildContext context, LauncherState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const Border(top: BorderSide(color: Colors.white12, width: 1)),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Consumer<LauncherState>(
              builder: (context, state, _) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 3,
                          color: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'FOCUS SETTINGS',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _settingToggle(
                        'Vibration',
                        'Vibrate when pomodoro/break starts',
                        state.vibrationEnabled,
                        (val) {
                          state.setVibrationEnabled(val);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      _settingToggle(
                        'Sound',
                        'Play alert sound when pomodoro/break starts',
                        state.soundEnabled,
                        (val) {
                          state.setSoundEnabled(val);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _settingToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontFamily: 'monospace',
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white38,
          ),
        ],
      ),
    );
  }

  void _showTaskSelectionModal(BuildContext context, LauncherState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Consumer<LauncherState>(
              builder: (context, modalState, child) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.6,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Planned',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.pushNamed(context, '/planner');
                            },
                            child: const Icon(
                              Icons.add_circle,
                              color: Colors.redAccent,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: modalState.tasks.isEmpty
                            ? Center(
                                child: Text(
                                  'NO TASKS. TAP + TO ADD.',
                                  style: TextStyle(
                                    color: Colors.grey[850],
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: modalState.tasks.length,
                                itemBuilder: (context, index) {
                                  final task = modalState.tasks[index];
                                  final isActive =
                                      modalState.activeTaskId == task['id'];
                                  return GestureDetector(
                                    onLongPress: () {
                                      Navigator.pop(ctx);
                                      Navigator.pop(context);
                                      Navigator.pushNamed(context, '/planner');
                                    },
                                    onTap: () {
                                      modalState.switchActiveTask(
                                        isActive ? null : task['id'] as String,
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.white10,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // Completion toggle circle
                                          GestureDetector(
                                            onTap: () {
                                              modalState.toggleTaskComplete(
                                                task['id'] as String,
                                              );
                                            },
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              margin: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: (task['isDone'] == true)
                                                    ? Colors.green.withOpacity(
                                                        0.2,
                                                      )
                                                    : Colors.transparent,
                                                border: Border.all(
                                                  color: (task['isDone'] == true)
                                                      ? Colors.green
                                                      : Colors.white24,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: (task['isDone'] == true)
                                                  ? const Icon(
                                                      Icons.check,
                                                      size: 13,
                                                      color: Colors.green,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  task['title'] as String? ?? '',
                                                  style: TextStyle(
                                                    color: (task['isDone'] == true)
                                                        ? Colors.green.withOpacity(0.7)
                                                        : (isActive ? Colors.white : Colors.grey[400]),
                                                    fontSize: 14,
                                                    decoration: (task['isDone'] == true)
                                                        ? TextDecoration.lineThrough
                                                        : null,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Goal: ${task['durationMinutes'] ?? 25}m',
                                                  style: TextStyle(
                                                    color: isActive ? Colors.white38 : Colors.grey[700],
                                                    fontSize: 10,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            isActive
                                                ? Icons.pause_circle_filled
                                                : Icons.play_circle_filled,
                                            color: isActive
                                                ? Colors.white
                                                : Colors.redAccent.withOpacity(
                                                    0.7,
                                                  ),
                                            size: 28,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Close',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}


