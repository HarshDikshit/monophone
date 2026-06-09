import 'package:flutter/material.dart';
import '../services/task_planner_service.dart';

class DayPlannerScreen extends StatefulWidget {
  const DayPlannerScreen({super.key});

  @override
  State<DayPlannerScreen> createState() => _DayPlannerScreenState();
}

class _DayPlannerScreenState extends State<DayPlannerScreen>
    with TickerProviderStateMixin {
  late TaskPlannerService _planner;
  DateTime _selectedDate = DateTime.now();
  bool _showMonthView = false;
  late AnimationController _viewAnimCtrl;
  late Animation<double> _viewAnim;

  @override
  void initState() {
    super.initState();
    _planner = TaskPlannerService();
    _planner.addListener(_onPlannerChange);
    _planner.load();
    _viewAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _viewAnim = CurvedAnimation(parent: _viewAnimCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _planner.removeListener(_onPlannerChange);
    _planner.dispose();
    _viewAnimCtrl.dispose();
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
          _iconBtn(Icons.add, 'Add task', () => _showTaskEditor(context, null)),
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

  // ── MONTH VIEW ─────────────────────────────────────────────────────
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

  // ── TODAY / DAY VIEW ──────────────────────────────────────────────
  Widget _buildTodayView(List<TimeBlockTask> tasks) {
    final now = DateTime.now();

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
                  if (_selectedDate.year != now.year ||
                      _selectedDate.month != now.month ||
                      _selectedDate.day != now.day)
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              const hourHeight = 80.0;
              final totalHeight = hourHeight * 24;

              return SingleChildScrollView(
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
                                          color: Colors.white.withOpacity(0.06),
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

                        return Positioned(
                          top: top,
                          left: 52,
                          right: 8,
                          height: height.clamp(30.0, hourHeight * 3),
                          child: GestureDetector(
                            onTap: () => _showTaskEditor(context, task),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: task.isCompleted
                                    ? task.tag.color.withOpacity(0.1)
                                    : task.tag.color.withOpacity(0.2),
                                border: Border.all(
                                  color: isActive
                                      ? Colors.white
                                      : task.tag.color.withOpacity(0.4),
                                  width: isActive ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        task.tag.icon,
                                        size: 10,
                                        color: task.tag.color,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          task.title,
                                          style: TextStyle(
                                            color: task.isCompleted
                                                ? Colors.white30
                                                : Colors.white,
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            decoration: task.isCompleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (task.isCompleted)
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 12,
                                        ),
                                    ],
                                  ),
                                  if (height > 35) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      task.timeSlotString,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontFamily: 'monospace',
                                        fontSize: 8,
                                      ),
                                    ),
                                    if (height > 50) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          _miniBadge(
                                            task.tag.displayName,
                                            task.tag.color,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '🍅 ${task.completedPomodoros}/${task.estimatedPomodoros}',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 8,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          if (task.isRecurring) ...[
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.autorenew,
                                              color: Colors.white24,
                                              size: 10,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),

                      if (_selectedDate.year == now.year &&
                          _selectedDate.month == now.month &&
                          _selectedDate.day == now.day)
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

  Widget _miniBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ── TASK EDITOR DIALOG ────────────────────────────────────────────
  void _showTaskEditor(BuildContext context, TimeBlockTask? existing) {
    final edit = existing != null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    TaskTag selectedTag = existing?.tag ?? TaskTag.focus;
    DateTime selectedTime = existing?.startTime ?? DateTime.now();
    int durationMins = existing?.durationMinutes ?? 60;
    int estPomodoros = existing?.estimatedPomodoros ?? 2;
    bool isRecurring = existing?.isRecurring ?? false;
    List<int> recurringDays = existing?.recurringDays ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0A0A),
      shape: const Border(top: BorderSide(color: Colors.white12)),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              builder: (ctx, scrollCtrl) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 3,
                          color: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        edit ? 'EDIT TASK' : 'NEW TASK',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 24),

                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          hintText: 'TASK TITLE',
                          hintStyle: TextStyle(color: Colors.white12),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white10),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: descCtrl,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        cursorColor: Colors.white,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'DESCRIPTION (optional)',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.08),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white10),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'TAG',
                        style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: TaskTag.values.map((tag) {
                          final isSel = selectedTag == tag;
                          return GestureDetector(
                            onTap: () =>
                                setDialogState(() => selectedTag = tag),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? tag.color.withOpacity(0.15)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSel ? tag.color : Colors.white12,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(tag.icon, size: 14, color: tag.color),
                                  const SizedBox(width: 6),
                                  Text(
                                    tag.displayName,
                                    style: TextStyle(
                                      color: isSel ? tag.color : Colors.white38,
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      fontWeight: isSel
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: _infoField(
                              'START TIME',
                              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                              () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                    selectedTime,
                                  ),
                                  builder: (ctx, child) => Theme(
                                    data: Theme.of(ctx).copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.white,
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (t != null) {
                                  selectedTime = DateTime(
                                    selectedTime.year,
                                    selectedTime.month,
                                    selectedTime.day,
                                    t.hour,
                                    t.minute,
                                  );
                                  setDialogState(() {});
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _infoField(
                              'DURATION',
                              '$durationMins min',
                              () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => _numberPickerDialog(
                                    ctx,
                                    'Duration (minutes)',
                                    durationMins,
                                    5,
                                    480,
                                    (v) {
                                      setDialogState(() => durationMins = v);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _infoField('ESTIMATED POMODOROS', '$estPomodoros 🍅', () {
                        showDialog(
                          context: context,
                          builder: (ctx) => _numberPickerDialog(
                            ctx,
                            'Estimated Pomodoros',
                            estPomodoros,
                            1,
                            20,
                            (v) {
                              setDialogState(() => estPomodoros = v);
                              Navigator.pop(ctx);
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'REPEAT WEEKLY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                                Switch(
                                  value: isRecurring,
                                  onChanged: (v) =>
                                      setDialogState(() => isRecurring = v),
                                  activeColor: Colors.white,
                                  activeTrackColor: Colors.white60,
                                ),
                              ],
                            ),
                            if (isRecurring) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children:
                                    [
                                      'Mon',
                                      'Tue',
                                      'Wed',
                                      'Thu',
                                      'Fri',
                                      'Sat',
                                      'Sun',
                                    ].asMap().entries.map((e) {
                                      final dayNum = e.key + 1;
                                      final isDaySelected = recurringDays
                                          .contains(dayNum);
                                      return GestureDetector(
                                        onTap: () {
                                          setDialogState(() {
                                            if (isDaySelected)
                                              recurringDays.remove(dayNum);
                                            else
                                              recurringDays.add(dayNum);
                                          });
                                        },
                                        child: Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: isDaySelected
                                                  ? Colors.white
                                                  : Colors.white12,
                                            ),
                                            color: isDaySelected
                                                ? Colors.white
                                                : Colors.transparent,
                                          ),
                                          child: Center(
                                            child: Text(
                                              e.value.substring(0, 1),
                                              style: TextStyle(
                                                color: isDaySelected
                                                    ? Colors.black
                                                    : Colors.white38,
                                                fontFamily: 'monospace',
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (titleCtrl.text.trim().isEmpty) return;
                                final task = TimeBlockTask(
                                  id:
                                      existing?.id ??
                                      DateTime.now().millisecondsSinceEpoch
                                          .toString(),
                                  title: titleCtrl.text.trim(),
                                  description: descCtrl.text.trim(),
                                  tag: selectedTag,
                                  startTime: selectedTime,
                                  durationMinutes: durationMins,
                                  estimatedPomodoros: estPomodoros,
                                  isRecurring: isRecurring,
                                  recurringDays: isRecurring
                                      ? recurringDays
                                      : [],
                                  isCompleted: existing?.isCompleted ?? false,
                                  focusSeconds: existing?.focusSeconds ?? 0,
                                  completedPomodoros:
                                      existing?.completedPomodoros ?? 0,
                                );
                                if (edit) {
                                  _planner.updateTask(task);
                                } else {
                                  _planner.addTask(task);
                                  _planner.scheduleReminders([task]);
                                }
                                Navigator.pop(context);
                              },
                              child: Container(
                                height: 48,
                                color: Colors.white,
                                child: const Center(
                                  child: Text(
                                    'SAVE',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      letterSpacing: 2,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (edit) ...[
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () {
                                _planner.removeTask(existing.id);
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.redAccent),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
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
