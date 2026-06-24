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
  // Time picker wheel state (mm:ss)
  late int _pickerMinutes;
  late int _pickerSeconds;

  @override
  void initState() {
    super.initState();
    final state = context.read<LauncherState>();
    _pickerMinutes = state.customDurationSeconds ~/ 60;
    _pickerSeconds = state.customDurationSeconds % 60;
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
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

  void _applyPickerToState(LauncherState state) {
    final totalSeconds = _pickerMinutes * 60 + _pickerSeconds;
    state.setCustomDuration(totalSeconds);
  }

  // ── Task edit / details bottom sheet ──────────────────────────────────────
  void _showTaskEditSheet(
    BuildContext context,
    LauncherState state,
    Map<String, dynamic> taskMap,
  ) {
    if (state.planner == null) return;

    // Find the actual TimeBlockTask from the planner
    final taskId = taskMap['id'] as String;
    final task = state.planner!.tasks.firstWhere((t) => t.id == taskId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TaskEditSheet(
        existing: task,
        initialDate: DateTime.now(),
        planner: state.planner!,
        pomoDurationMins: task.pomodoroDurationMinutes,
      ),
    );
  }

  // ── Swipeable mm:ss picker ──────────────────────────────────────────────
  Widget _buildTimePicker(LauncherState state) {
    // When timer is active, don't show the picker, show the running time
    if (state.isPomodoroActive) {
      return Column(
        children: [
          Text(
            _formatTime(state.pomodoroSecondsRemaining),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 72.0,
              fontWeight: FontWeight.w100,
              letterSpacing: 4.0,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            state.isBreak
                ? 'COFFEE / CHILL TIME'
                : (state.timerMode == 'countup' ? 'COUNTING UP' : 'FOCUS TIME'),
            style: TextStyle(
              color: state.isPomodoroActive ? Colors.white38 : Colors.grey[850],
              fontSize: 10,
              letterSpacing: 3.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    }

    // Show the swipeable time picker when NOT running
    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minutes wheel
              SizedBox(
                width: 70,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 45,
                  perspective: 0.005,
                  diameterRatio: 1.5,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    setState(() {
                      _pickerMinutes = index;
                    });
                    _applyPickerToState(state);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: 100,
                    builder: (context, index) {
                      final isSelected = index == _pickerMinutes;
                      return Center(
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white24,
                            fontSize: isSelected ? 42 : 24,
                            fontWeight: isSelected
                                ? FontWeight.w200
                                : FontWeight.w300,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  ':',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 42,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              // Seconds wheel
              SizedBox(
                width: 70,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 45,
                  perspective: 0.005,
                  diameterRatio: 1.5,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    setState(() {
                      _pickerSeconds = index;
                    });
                    _applyPickerToState(state);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: 60,
                    builder: (context, index) {
                      final isSelected = index == _pickerSeconds;
                      return Center(
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white24,
                            fontSize: isSelected ? 42 : 24,
                            fontWeight: isSelected
                                ? FontWeight.w200
                                : FontWeight.w300,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'SWIPE TO SET TIME',
          style: TextStyle(
            color: Colors.grey[850],
            fontSize: 9,
            letterSpacing: 3,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // ── Timer Mode Toggle ───────────────────────────────────────────────────
  Widget _buildTimerModeToggle(LauncherState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Countdown mode
          GestureDetector(
            onTap: () {
              state.setTimerMode('countdown');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: state.timerMode == 'countdown'
                    ? Colors.white.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'COUNTDOWN',
                style: TextStyle(
                  color: state.timerMode == 'countdown'
                      ? Colors.white
                      : Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                  fontWeight: state.timerMode == 'countdown'
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Countup mode
          GestureDetector(
            onTap: () {
              state.setTimerMode('countup');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: state.timerMode == 'countup'
                    ? Colors.white.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '∞ COUNT UP',
                style: TextStyle(
                  color: state.timerMode == 'countup'
                      ? Colors.white
                      : Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                  fontWeight: state.timerMode == 'countup'
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final isFullScreen = state.isFullScreen && state.isPomodoroActive;

    // Auto fullscreen: when timer is active, if user remains here, go fullscreen
    if (state.isPomodoroActive && !state.isFullScreen && mounted) {
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
                'FOCUS ENGINE',
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
                  state.isBreak ? 'BREAK TIME' : 'DEEP FOCUS',
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
                  state.isBreak
                      ? 'Relax. Let your brain recharge.'
                      : 'Distraction lock active. Stay on target.',
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
                      if (state.isPomodoroActive && !state.isBreak) ...[
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
                      if (!state.isPomodoroActive)
                        _buildTimePicker(state)
                      else
                        Column(
                          children: [
                            Text(
                              _formatTime(state.pomodoroSecondsRemaining),
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
                              state.isBreak
                                  ? 'COFFEE / CHILL TIME'
                                  : (state.timerMode == 'countup'
                                        ? 'COUNTING UP'
                                        : 'FOCUS TIME'),
                              style: TextStyle(
                                color: state.isPomodoroActive
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

                      if (state.isPomodoroActive) ...[
                        const SizedBox(height: 12),
                        // ── When count-up, show "stopped" hint ──
                        if (state.timerMode == 'countup')
                          Text(
                            'Counting up — stop when you\'re done',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 10,
                              fontFamily: 'monospace',
                              letterSpacing: 1,
                            ),
                          ),
                      ],

                      if (!state.isPomodoroActive) ...[
                        const SizedBox(height: 16),
                        // ── Timer Mode Toggle ──
                        _buildTimerModeToggle(state),
                        const SizedBox(height: 12),
                        // Timer mode description
                        Text(
                          state.timerMode == 'countdown'
                              ? 'Timer runs from set time → 0'
                              : 'Timer counts up from 0 until stopped',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],

                      // ── Fullscreen toggle (always visible) ──
                      if (state.isPomodoroActive) ...[
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

              // ── Start / Stop / Break button ──
              GestureDetector(
                onTap: () {
                  if (state.isPomodoroActive) {
                    state.stopPomodoro(manual: true);
                  } else {
                    state.startPomodoro();
                  }
                },
                child: Container(
                  height: isFullScreen ? 56 : 52,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: state.isPomodoroActive
                          ? Colors.red.withOpacity(0.6)
                          : Colors.white,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      state.isPomodoroActive
                          ? 'ABANDON SESSION'
                          : 'INITIATE FOCUS',
                      style: TextStyle(
                        color: state.isPomodoroActive
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

              // ── Skip break button ──
              if (state.isPomodoroActive && state.isBreak) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    // Stop break, start new pomodoro
                    state.stopPomodoro(manual: true);
                    // Briefly delay then start a new pomodoro
                    Future.delayed(const Duration(milliseconds: 300), () {
                      state.startPomodoro();
                    });
                  },
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Center(
                      child: Text(
                        'STOP BREAK & START NEW',
                        style: TextStyle(
                          color: Colors.white54,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ],

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
                        'POMODORO SETTINGS',
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
                        'Auto-start next pomodoro',
                        'Automatically start next focus session after break ends',
                        state.autoStartNextPomodoro,
                        (val) {
                          state.setAutoStartNextPomodoro(val);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      _settingToggle(
                        'Auto-start break',
                        'Automatically start break when pomodoro completes',
                        state.autoStartBreak,
                        (val) {
                          state.setAutoStartBreak(val);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 16),
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
            activeColor: Colors.white,
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
                                      if (!isActive) {
                                        // Set the custom duration from the task's pomodoro duration
                                        final taskId = task['id'] as String;
                                        final timeBlockTask = modalState.planner
                                            ?.getTaskById(taskId);
                                        if (timeBlockTask != null) {
                                          modalState.setCustomDuration(
                                            timeBlockTask
                                                    .pomodoroDurationMinutes *
                                                60,
                                          );
                                        }
                                      }
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
                                                  color:
                                                      (task['isDone'] == true)
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
                                                  task['title'] as String? ??
                                                      '',
                                                  style: TextStyle(
                                                    color:
                                                        (task['isDone'] == true)
                                                        ? Colors.green
                                                              .withOpacity(0.7)
                                                        : (isActive
                                                              ? Colors.white
                                                              : Colors
                                                                    .grey[400]),
                                                    fontSize: 14,
                                                    decoration:
                                                        (task['isDone'] == true)
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : null,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Builder(
                                                  builder: (context) {
                                                    final completed =
                                                        (task['completedPomodoroCount'] ??
                                                                task['pomodoroCount'] ??
                                                                0)
                                                            as int;
                                                    final estimated =
                                                        (task['estimatedPomodoros'] ??
                                                                1)
                                                            as int;
                                                    return Row(
                                                      children: [
                                                        ...List.generate(
                                                          completed.clamp(
                                                            0,
                                                            estimated,
                                                          ),
                                                          (_) => const Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                  right: 3,
                                                                ),
                                                            child: Text(
                                                              '🍅',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        ...List.generate(
                                                          (estimated -
                                                                  completed)
                                                              .clamp(
                                                                0,
                                                                estimated,
                                                              ),
                                                          (_) => Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  right: 3,
                                                                ),
                                                            child: Icon(
                                                              Icons
                                                                  .circle_outlined,
                                                              size: 10,
                                                              color: isActive
                                                                  ? Colors
                                                                        .white24
                                                                  : Colors
                                                                        .white12,
                                                            ),
                                                          ),
                                                        ),
                                                        if (completed >
                                                            estimated)
                                                          Text(
                                                            '+${completed - estimated}',
                                                            style: const TextStyle(
                                                              color: Colors
                                                                  .redAccent,
                                                              fontSize: 9,
                                                              fontFamily:
                                                                  'monospace',
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  },
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
