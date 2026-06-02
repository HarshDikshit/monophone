import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/launcher_state.dart';

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  final _taskController = TextEditingController();
  bool _isAddingTask = false;
  bool _isRecurringNew = false;
  int _targetPomodoros = 1; // target pomodoro count for new task creation

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
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

  // ── Task edit / details bottom sheet ──────────────────────────────────────
  void _showTaskEditSheet(BuildContext context, LauncherState state,
      Map<String, dynamic> task) {
    final editCtrl = TextEditingController(text: task['title'] as String? ?? '');
    int sheetEstPomos = (task['estimatedPomodoros'] as int?) ?? 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const Border(top: BorderSide(color: Colors.white12, width: 1)),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // handle bar
              Center(
                child: Container(
                    width: 36, height: 2, color: Colors.white24),
              ),
              const SizedBox(height: 20),
              const Text(
                'EDIT TASK',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              // Title field
              TextField(
                controller: editCtrl,
                autofocus: true,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace', fontSize: 14),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Task title…',
                  hintStyle: TextStyle(color: Colors.white24),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white12)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54)),
                ),
              ),
              const SizedBox(height: 20),
              // Stats row
              Row(
                children: [
                  _statChip(
                      '🍅 ${task['completedPomodoroCount'] ?? task['pomodoroCount'] ?? 0}', 'COMPLETED'),
                  const SizedBox(width: 24),
                  _statChip(
                      '⏱ ${_formatMinutes(task['focusSeconds'] ?? 0)}',
                      'FOCUS TIME'),
                ],
              ),
              const SizedBox(height: 20),
              // Target Pomodoros stepper
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TARGET POMODOROS',
                    style: TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        letterSpacing: 1),
                  ),
                  Row(
                    children: [
                      _stepperBtn('-', () {
                        if (sheetEstPomos > 1) setSheet(() => sheetEstPomos--);
                      }),
                      Container(
                        width: 40,
                        alignment: Alignment.center,
                        child: Text(
                          '$sheetEstPomos',
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      _stepperBtn('+', () {
                        if (sheetEstPomos < 99) setSheet(() => sheetEstPomos++);
                      }),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Recurring toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECURRING DAILY',
                    style: TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        letterSpacing: 1),
                  ),
                  Switch(
                    value: task['isRecurring'] ?? false,
                    activeColor: Colors.white,
                    activeTrackColor: Colors.white38,
                    inactiveThumbColor: Colors.grey[700],
                    inactiveTrackColor: Colors.white10,
                    onChanged: (val) async {
                      await state.toggleTaskRecurring(task['id'] as String);
                      setSheet(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // Save
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final t = editCtrl.text.trim();
                        if (t.isNotEmpty) {
                          await state.modifyTask(task['id'] as String, t);
                        }
                        await state.updateTaskEstimatedPomodoros(task['id'] as String, sheetEstPomos);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Container(
                        height: 44,
                        color: Colors.white,
                        child: const Center(
                          child: Text(
                            'SAVE',
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
                  ),
                  const SizedBox(width: 12),
                  // Delete
                  GestureDetector(
                    onTap: () async {
                      if (ctx.mounted) Navigator.pop(ctx);
                      await state.deleteTask(task['id'] as String);
                    },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.red.withOpacity(0.5))),
                      child: const Center(
                        child: Text(
                          'DELETE',
                          style: TextStyle(
                              color: Colors.red,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              letterSpacing: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 9,
              letterSpacing: 1),
        ),
      ],
    );
  }

  Widget _stepperBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
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
              fontSize: 14),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    color: Colors.grey[800], fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              
              // ── Task Selector Button ──
              Center(
                child: GestureDetector(
                  onTap: () => _showTaskSelectionModal(context, state),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12)
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state.activeTaskId != null ? Colors.redAccent : Colors.white38,
                          )
                        ),
                        const SizedBox(width: 12),
                        Text(
                          state.activeTaskId != null 
                              ? (state.activeTask?['title'] ?? 'Focus Session') 
                              : 'Select a task...',
                          style: TextStyle(
                            color: state.activeTaskId != null ? Colors.white : Colors.white54,
                            fontFamily: 'monospace',
                            fontSize: 13
                          )
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),

              // ── Timer ──
              Center(
                child: Column(
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
                      state.isPomodoroActive
                          ? (state.isBreak
                              ? 'COFFEE / CHILL TIME'
                              : 'FOCUS TIME INDUCED')
                          : 'STANDBY',
                      style: TextStyle(
                        color: state.isPomodoroActive
                            ? Colors.white38
                            : Colors.grey[850],
                        fontSize: 10,
                        letterSpacing: 3.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Permission / stats hint ──
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
                          fontFamily: 'monospace'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // ── Start / Stop button ──
              GestureDetector(
                onTap: () {
                  if (state.isPomodoroActive) {
                    state.stopPomodoro();
                  } else {
                    state.startPomodoro();
                  }
                },
                child: Container(
                  height: 52,
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
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Spacer(),
            ],
          ),
        ),
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
        return StatefulBuilder(builder: (context, setModalState) {
          // Re-fetch state manually or rely on Provider if it updates. 
          // Best to wrap with Consumer in the modal if we want real-time updates.
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
                              fontWeight: FontWeight.bold),
                        ),
                        GestureDetector(
                          onTap: () => setModalState(() => _isAddingTask = !_isAddingTask),
                          child: Icon(
                            _isAddingTask ? Icons.close : Icons.add_circle,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isAddingTask) ...[
                      // Title field
                      TextField(
                        controller: _taskController,
                        autofocus: true,
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'New task…',
                          hintStyle: TextStyle(color: Colors.white24),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                        ),
                        onSubmitted: (val) async {
                          if (val.trim().isNotEmpty) {
                            await modalState.addTask(
                              val.trim(),
                              isRecurring: _isRecurringNew,
                              estimatedPomodoros: _targetPomodoros,
                            );
                            _taskController.clear();
                            setModalState(() {
                              _isAddingTask = false;
                              _isRecurringNew = false;
                              _targetPomodoros = 1;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Target Pomodoros stepper + recurring toggle row
                      Row(
                        children: [
                          // Recurring toggle
                          GestureDetector(
                            onTap: () => setModalState(() => _isRecurringNew = !_isRecurringNew),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                border: Border.all(color: _isRecurringNew ? Colors.white54 : Colors.white12),
                              ),
                              child: Center(
                                child: Text('∞', style: TextStyle(color: _isRecurringNew ? Colors.white : Colors.white24, fontSize: 18)),
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Target Pomodoros label + stepper
                          const Text(
                            'TARGET  ',
                            style: TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 11, letterSpacing: 1),
                          ),
                          _stepperBtn('-', () {
                            if (_targetPomodoros > 1) setModalState(() => _targetPomodoros--);
                          }),
                          Container(
                            width: 40,
                            alignment: Alignment.center,
                            child: Text(
                              '$_targetPomodoros 🍅',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _stepperBtn('+', () {
                            if (_targetPomodoros < 99) setModalState(() => _targetPomodoros++);
                          }),
                        ],
                      ),
                      // Add button
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final val = _taskController.text.trim();
                          if (val.isNotEmpty) {
                            await modalState.addTask(
                              val,
                              isRecurring: _isRecurringNew,
                              estimatedPomodoros: _targetPomodoros,
                            );
                            _taskController.clear();
                            setModalState(() {
                              _isAddingTask = false;
                              _isRecurringNew = false;
                              _targetPomodoros = 1;
                            });
                          }
                        },
                        child: Container(
                          height: 40,
                          color: Colors.white,
                          alignment: Alignment.center,
                          child: const Text(
                            'ADD TASK',
                            style: TextStyle(
                                color: Colors.black,
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Expanded(
                      child: modalState.tasks.isEmpty
                          ? Center(
                              child: Text(
                                'NO TASKS. TAP + TO ADD.',
                                style: TextStyle(color: Colors.grey[850], fontFamily: 'monospace', fontSize: 12),
                              ),
                            )
                          : ListView.builder(
                              itemCount: modalState.tasks.length,
                              itemBuilder: (context, index) {
                                final task = modalState.tasks[index];
                                final isActive = modalState.activeTaskId == task['id'];
                                return GestureDetector(
                                  onLongPress: () {
                                    Navigator.pop(ctx);
                                    _showTaskEditSheet(context, modalState, task);
                                  },
                                  onTap: () {
                                    modalState.switchActiveTask(isActive ? null : task['id'] as String);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    decoration: const BoxDecoration(
                                      border: Border(bottom: BorderSide(color: Colors.white10)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                task['title'] as String? ?? '',
                                                style: TextStyle(
                                                  color: isActive ? Colors.white : Colors.grey[400],
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              // Pomodoro progress: completed 🍅 / estimated
                                              Builder(builder: (context) {
                                                final completed = (task['completedPomodoroCount'] ?? task['pomodoroCount'] ?? 0) as int;
                                                final estimated = (task['estimatedPomodoros'] ?? 1) as int;
                                                return Row(
                                                  children: [
                                                    // Filled tomatoes
                                                    ...List.generate(completed.clamp(0, estimated), (_) =>
                                                      const Padding(
                                                        padding: EdgeInsets.only(right: 3),
                                                        child: Text('🍅', style: TextStyle(fontSize: 10)),
                                                      )
                                                    ),
                                                    // Empty slots
                                                    ...List.generate((estimated - completed).clamp(0, estimated), (_) =>
                                                      Padding(
                                                        padding: const EdgeInsets.only(right: 3),
                                                        child: Icon(Icons.circle_outlined, size: 10,
                                                          color: isActive ? Colors.white24 : Colors.white12),
                                                      )
                                                    ),
                                                    if (completed > estimated)
                                                      Text(
                                                        '+${completed - estimated}',
                                                        style: const TextStyle(
                                                          color: Colors.redAccent,
                                                          fontSize: 9,
                                                          fontFamily: 'monospace',
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          isActive ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                          color: isActive ? Colors.white : Colors.redAccent.withOpacity(0.7),
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
                        child: const Text('Close', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                  ],
                ),
              );
            }
          );
        });
      },
    );
  }
}
