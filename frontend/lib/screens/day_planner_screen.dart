import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/task_planner_service.dart';
import '../services/launcher_state.dart';
import '../services/unified_task_service.dart';
import '../services/alarm_service.dart';
import '../widgets/task_edit_sheet.dart';

class DayPlannerScreen extends StatefulWidget {
  const DayPlannerScreen({super.key});

  @override
  State<DayPlannerScreen> createState() => _DayPlannerScreenState();
}

class _DayPlannerScreenState extends State<DayPlannerScreen>
    with TickerProviderStateMixin {
  late TaskPlannerService _planner;
  final AlarmService _alarmService = AlarmService();
  DateTime _selectedDate = DateTime.now();
  bool _showMonthView = false;
  late AnimationController _viewAnimCtrl;
  late Animation<double> _viewAnim;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _timeRefreshTimer;

  @override
  void initState() {
    super.initState();
    _planner = TaskPlannerService();
    _planner.addListener(_onPlannerChange);
    _planner.load();
    _alarmService.addListener(_onPlannerChange);
    _alarmService.attach(_planner);
    _viewAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _viewAnim = CurvedAnimation(parent: _viewAnimCtrl, curve: Curves.easeInOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launcherState = context.read<LauncherState>();
      UnifiedTaskService.instance.attach(launcherState, _planner);
      launcherState.attachPlanner(_planner);
      _scrollToCurrentTime();
    });
  }

  void _scrollToCurrentTime() {
    const hourHeight = 120.0;
    final now = DateTime.now();
    final target =
        now.hour * hourHeight + (now.minute / 60.0) * hourHeight - 120;
    if (target > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timeRefreshTimer?.cancel();
    _timeRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timeRefreshTimer?.cancel();
    _alarmService.removeListener(_onPlannerChange);
    _alarmService.detach();
    _alarmService.dispose();
    _planner.removeListener(_onPlannerChange);
    _planner.dispose();
    _viewAnimCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onPlannerChange() {
    if (mounted) setState(() {});
  }

  void _toggleView() {
    if (_showMonthView) {
      _viewAnimCtrl.reverse();
    } else {
      _viewAnimCtrl.forward();
    }
    setState(() => _showMonthView = !_showMonthView);
  }

  void _goToDate(DateTime date) {
    setState(() => _selectedDate = date);
    if (_showMonthView) _toggleView();
  }

  double _computeHourHeight(List<TimeBlockTask> tasks) {
    if (tasks.isEmpty) return 120.0;
    int minHour = 23;
    int maxHour = 0;
    for (final t in tasks) {
      final sh = t.startTime.hour;
      final eh = t.endTime.hour;
      if (sh < minHour) minHour = sh;
      if (eh > maxHour) maxHour = eh;
    }
    final span = (maxHour - minHour).clamp(1, 18);
    final base = (400.0 / span).clamp(60.0, 180.0);
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final todayTasks = _planner.tasksForDate(_selectedDate);
    final monthData = _planner.tasksForMonth(
      DateTime(_selectedDate.year, _selectedDate.month, 1),
    );

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
          'DAY PLANNER',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            letterSpacing: 2,
            fontSize: 14,
          ),
        ),
        actions: [
          _iconBtn(
            Icons.calendar_month,
            _showMonthView ? 'Today view' : 'Month view',
            _toggleView,
          ),
          const SizedBox(width: 4),
          _iconBtn(Icons.add, 'Add task', () => _showTaskSheet(context)),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _viewAnim,
          builder: (context, _) {
            return _showMonthView
                ? _buildMonthView(monthData)
                : _buildTodayView(todayTasks);
          },
        ),
      ),
    );
  }

  Widget _buildMonthView(Map<DateTime, List<TimeBlockTask>> monthData) {
    final now = DateTime.now();
    final firstDay = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final lastDay = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final firstWeekday = firstDay.weekday % 7;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => _shiftMonth(-1),
                child: const Icon(Icons.chevron_left, color: Colors.white54),
              ),
              Text(
                '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][_selectedDate.month - 1]} ${_selectedDate.year}',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              GestureDetector(
                onTap: () => _shiftMonth(1),
                child: const Icon(Icons.chevron_right, color: Colors.white54),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          color: Colors.white24,
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 0.85,
            ),
            itemCount: firstWeekday + lastDay.day,
            itemBuilder: (context, index) {
              if (index < firstWeekday) return const SizedBox();
              final day = index - firstWeekday + 1;
              final date = DateTime(
                _selectedDate.year,
                _selectedDate.month,
                day,
              );
              final isToday =
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
              final isSelected =
                  date.year == _selectedDate.year &&
                  date.month == _selectedDate.month &&
                  date.day == _selectedDate.day;
              final tasks =
                  monthData[DateTime(date.year, date.month, date.day)] ?? [];
              return GestureDetector(
                onTap: () => _goToDate(date),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.06),
                    ),
                    color: isToday
                        ? Colors.white.withOpacity(0.06)
                        : Colors.transparent,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        '$day',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isToday ? Colors.white : Colors.grey[600]),
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: isSelected || isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (tasks.length <= 3)
                        ...tasks
                            .take(3)
                            .map(
                              (t) => Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: t.tag.color.withOpacity(0.7),
                                ),
                              ),
                            )
                      else ...[
                        ...tasks
                            .take(2)
                            .map(
                              (t) => Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: t.tag.color.withOpacity(0.7),
                                ),
                              ),
                            ),
                        Text(
                          '+${tasks.length - 2}',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 7,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _shiftMonth(int delta) {
    setState(
      () => _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month + delta,
        1,
      ),
    );
  }

  Widget _buildTodayView(List<TimeBlockTask> tasks) {
    final now = DateTime.now();
    final isToday =
        _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final hourHeight = _computeHourHeight(tasks);
    final totalHeight = hourHeight * 24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => _shiftDay(-1),
                child: const Icon(Icons.chevron_left, color: Colors.white38),
              ),
              Column(
                children: [
                  Text(
                    '${['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][_selectedDate.weekday % 7]}, ${_selectedDate.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][_selectedDate.month - 1]}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  if (isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white38),
                      ),
                      child: const Text(
                        'TODAY',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1,
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () =>
                          setState(() => _selectedDate = DateTime.now()),
                      child: const Text(
                        'TODAY',
                        style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
              GestureDetector(
                onTap: () => _shiftDay(1),
                child: const Icon(Icons.chevron_right, color: Colors.white38),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        Expanded(
          child: Consumer<LauncherState>(
            builder: (context, state, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  return RefreshIndicator(
                    onRefresh: () => state.syncStats(),
                    color: Colors.white,
                    backgroundColor: Colors.black,
                    child: SingleChildScrollView(
                      controller: _scrollCtrl,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: totalHeight,
                        child: Stack(
                          children: [
                            ...List.generate(24, (h) {
                              return Positioned(
                                top: h * hourHeight,
                                left: 0,
                                right: 0,
                                child: SizedBox(
                                  height: hourHeight,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 48,
                                        child: Text(
                                          '${h.toString().padLeft(2, '0')}:00',
                                          style: TextStyle(
                                            color: Colors.grey[800],
                                            fontFamily: 'monospace',
                                            fontSize: 9,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: Colors.white.withOpacity(
                                                  0.06,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
  
                            ...tasks.map((task) {
                              final top =
                                  task.startTime.hour * hourHeight +
                                  (task.startTime.minute / 60.0) * hourHeight;
                              final height =
                                  (task.durationMinutes / 60.0) * hourHeight;
                              final isActive =
                                  task.startTime.isBefore(now) &&
                                  task.endTime.isAfter(now);
                              final totalMinutes =
                                  task.estimatedPomodoros *
                                  task.pomodoroDurationMinutes;
  
                              return Positioned(
                                top: top,
                                left: 52,
                                right: 8,
                                height: height.clamp(50.0, hourHeight * 5),
                                child: _TaskBlock(
                                  task: task,
                                  isActive: isActive,
                                  totalMinutes: totalMinutes,
                                  pomoDuration: task.pomodoroDurationMinutes,
                                  onTap: () => _showTaskSheet(context, existing: task),
                                ),
                              );
                            }),
  
                            if (isToday)
                              Positioned(
                                top:
                                    now.hour * hourHeight +
                                    (now.minute / 60.0) * hourHeight,
                                left: 0,
                                right: 0,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontFamily: 'monospace',
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        height: 1,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _shiftDay(int delta) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: delta)));
  }

  void _showTaskSheet(
    BuildContext context, {
    TimeBlockTask? existing,
    DateTime? initialTime,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TaskEditSheet(
        existing: existing,
        initialDate: initialTime ?? _selectedDate,
        planner: _planner,
        pomoDurationMins: existing?.pomodoroDurationMinutes ?? _planner.pomodoroDuration,
      ),
    );
  }

  Widget _timeBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(border: Border.all(color: Colors.white12)),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoField(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'monospace',
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberPickerDialog(
    BuildContext context,
    String title,
    int current,
    int min,
    int max,
    ValueChanged<int> onSelect,
  ) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: Border.all(color: Colors.white12),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 200,
        child: ListView.builder(
          itemCount: (max - min + 1),
          itemBuilder: (ctx, i) {
            final val = min + i;
            return GestureDetector(
              onTap: () => onSelect(val),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: val == current
                      ? const Border(bottom: BorderSide(color: Colors.white))
                      : null,
                ),
                child: Center(
                  child: Text(
                    '$val',
                    style: TextStyle(
                      color: val == current ? Colors.white : Colors.white38,
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: val == current
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          },
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
}

// ── Task Block Widget ──
class _TaskBlock extends StatefulWidget {
  final TimeBlockTask task;
  final bool isActive;
  final int totalMinutes;
  final int pomoDuration;
  final VoidCallback onTap;

  const _TaskBlock({
    required this.task,
    required this.isActive,
    required this.totalMinutes,
    required this.pomoDuration,
    required this.onTap,
  });

  @override
  State<_TaskBlock> createState() => _TaskBlockState();
}

class _TaskBlockState extends State<_TaskBlock> {
  double _dragOffset = 0;
  bool _isRevealed = false;
  static const double _revealThreshold = 120;

  void _toggleComplete() {
    final planner = context
        .findAncestorStateOfType<_DayPlannerScreenState>()
        ?._planner;
    if (planner != null) {
      planner.toggleComplete(widget.task.id);
    }
  }

  void _onTapDismiss() {
    setState(() {
      _dragOffset = 0;
      _isRevealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset = (_dragOffset + details.delta.dx).clamp(
            -_revealThreshold - 20,
            0,
          );
          _isRevealed = _dragOffset < -_revealThreshold;
        });
      },
      onHorizontalDragEnd: (details) {
        setState(() {
          if (_dragOffset < -_revealThreshold / 2) {
            _dragOffset = -_revealThreshold;
            _isRevealed = true;
          } else {
            _dragOffset = 0;
            _isRevealed = false;
          }
        });
      },
      onTap: () {
        if (_isRevealed) {
          _onTapDismiss();
        } else {
          widget.onTap();
        }
      },
      onLongPress: _toggleComplete,
      child: SizedBox(
        height: double.infinity,
        child: Stack(
          children: [
            // Background actions (edit + delete) revealed on swipe
            if (_isRevealed || _dragOffset < -10)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        _onTapDismiss();
                        widget.onTap();
                      },
                      child: Container(
                        width: _revealThreshold / 2,
                        color: Colors.blue.withOpacity(0.2),
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, color: Colors.blue, size: 14),
                            SizedBox(height: 2),
                            Text(
                              'EDIT',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 7,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _onTapDismiss();
                        final planner = context
                            .findAncestorStateOfType<_DayPlannerScreenState>()
                            ?._planner;
                        if (planner != null) {
                          planner.removeTask(widget.task.id);
                        }
                      },
                      child: Container(
                        width: _revealThreshold / 2,
                        color: Colors.red.withOpacity(0.2),
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 14,
                            ),
                            SizedBox(height: 2),
                            Text(
                              'DELETE',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 7,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Main content that slides
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.translationValues(_dragOffset, 0, 0),
              padding: const EdgeInsets.all(6),
              height: double.infinity,
              decoration: BoxDecoration(
                color: widget.task.isCompleted
                    ? Colors.green.withOpacity(0.08)
                    : Colors.amber.withOpacity(0.08),
                border: Border(
                  left: BorderSide(
                    color: widget.isActive
                        ? Colors.white
                        : (widget.task.isCompleted
                              ? Colors.green.withOpacity(0.6)
                              : Colors.amber.withOpacity(0.6)),
                    width: widget.isActive ? 2 : 1,
                  ),
                ),
              ),
              child: Consumer<LauncherState>(
                builder: (context, state, _) {
                  final isThisTaskActive = state.activeTaskId == widget.task.id;
                  final isRunning = state.isPomodoroActive && isThisTaskActive;
                  // Re-fetch live task data from planner to get updated completedPomodoros
                  final liveTask = state.planner?.getTaskById(widget.task.id);
                  final completedPomodoros = liveTask?.completedPomodoros ?? widget.task.completedPomodoros;
                  final estimatedPomodoros = liveTask?.estimatedPomodoros ?? widget.task.estimatedPomodoros;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Row(
                        children: [
                          // Completion indicator icon (visual only)
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.task.isCompleted
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.transparent,
                              border: Border.all(
                                color: widget.task.isCompleted
                                    ? Colors.green
                                    : Colors.white24,
                                width: 1.5,
                              ),
                            ),
                            child: widget.task.isCompleted
                                ? const Icon(
                                    Icons.check,
                                    size: 8,
                                    color: Colors.green,
                                  )
                                : null,
                          ),
                          Icon(
                            widget.task.tag.icon,
                            size: 9,
                            color: widget.task.tag.color,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                widget.task.title,
                                style: TextStyle(
                                  color: widget.task.isCompleted
                                      ? Colors.green.withOpacity(0.7)
                                      : Colors.white,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  decoration: widget.task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          // Bell icon for alarm-enabled tasks
                          if (widget.task.isAlarmEnabled)
                            const Padding(
                              padding: EdgeInsets.only(right: 2),
                              child: Icon(
                                Icons.notifications_active,
                                color: Colors.orangeAccent,
                                size: 8,
                              ),
                            ),
                          const SizedBox(width: 4),
                          // Play button
                          GestureDetector(
                            onTap: () {
                              state.switchActiveTask(
                                widget.task.id,
                                taskName: widget.task.title,
                              );
                              state.setCustomDuration(widget.task.pomodoroDurationMinutes * 60);
                              if (!state.isPomodoroActive) {
                                state.startPomodoro();
                              }
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: isRunning
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isRunning
                                      ? Colors.white38
                                      : Colors.white12,
                                ),
                              ),
                              child: Icon(
                                Icons.play_arrow,
                                color: isRunning
                                    ? Colors.white
                                    : Colors.greenAccent,
                                size: 13,
                              ),
                            ),
                          ),
                          if (isRunning) ...[
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: () {
                                state.stopPomodoro(manual: true);
                                state.switchActiveTask(null);
                              },
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                ),
                                child: const Icon(
                                  Icons.stop,
                                  color: Colors.redAccent,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${widget.task.startTime.hour.toString().padLeft(2, '0')}:${widget.task.startTime.minute.toString().padLeft(2, '0')}-${widget.task.endTime.hour.toString().padLeft(2, '0')}:${widget.task.endTime.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white30,
                              fontFamily: 'monospace',
                              fontSize: 7,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: widget.task.tag.color.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              widget.task.tag.displayName.substring(0, 3),
                              style: TextStyle(
                                color: widget.task.tag.color,
                                fontSize: 6,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '🍅$completedPomodoros/$estimatedPomodoros',
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 7,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${widget.totalMinutes}m',
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 7,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (isRunning) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${(state.pomodoroSecondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(state.pomodoroSecondsRemaining % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 7,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (widget.task.description.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            widget.task.description,
                            style: const TextStyle(
                              color: Colors.white12,
                              fontSize: 6,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
