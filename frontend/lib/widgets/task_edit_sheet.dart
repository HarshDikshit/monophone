import 'package:flutter/material.dart';
import '../services/task_planner_service.dart';

class TaskEditSheet extends StatefulWidget {
  final TimeBlockTask? existing;
  final DateTime initialDate;
  final TaskPlannerService planner;
  final int initialDurationMins;

  const TaskEditSheet({
    super.key,
    this.existing,
    required this.initialDate,
    required this.planner,
    this.initialDurationMins = 25,
  });

  @override
  State<TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<TaskEditSheet> {
  late TextEditingController titleCtrl;
  late TextEditingController descCtrl;
  late TaskTag selectedTag;
  late DateTime selectedTime;
  late int durationMins;
  late bool isAlarmEnabled;
  late bool isRecurring;
  late List<int> recurringDays;
  bool allowOverlap = false;

  // HH:MM duration editing
  late int _durationHours;
  late int _durationMinutes;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    titleCtrl = TextEditingController(text: existing?.title ?? '');
    descCtrl = TextEditingController(text: existing?.description ?? '');
    selectedTag = existing?.tag ?? TaskTag.general;
    selectedTime = existing?.startTime ?? widget.initialDate;
    durationMins = existing?.durationMinutes ?? widget.initialDurationMins;
    isAlarmEnabled = existing?.isAlarmEnabled ?? true;
    isRecurring = existing?.isRecurring ?? false;
    recurringDays = List.from(existing?.recurringDays ?? [1, 2, 3, 4, 5, 6, 7]);
    _durationHours = durationMins ~/ 60;
    _durationMinutes = durationMins % 60;
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  void _syncDuration() {
    durationMins = _durationHours * 60 + _durationMinutes;
    if (durationMins < 1) {
      durationMins = 1;
      _durationHours = 0;
      _durationMinutes = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncDuration();
    final endTime = selectedTime.add(Duration(minutes: durationMins));
    final endStr =
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

    return Container(
      color: Colors.black,
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(width: 36, height: 3, color: Colors.white24),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing != null ? 'EDIT TASK' : 'NEW TASK',
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
                maxLines: 1,
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
                maxLines: null,
                style: const TextStyle(
                  color: Colors.white60,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  hintText: 'DESCRIPTION (optional)',
                  hintStyle: TextStyle(color: Colors.white12),
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
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TaskTag.values.map((tag) {
                  final isSel = selectedTag == tag;
                  return GestureDetector(
                    onTap: () => setState(() => selectedTag = tag),
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
              _buildTimeSection(),
              const SizedBox(height: 12),
              _buildDurationSelector(),
              const SizedBox(height: 12),
              _buildDurationSummary(durationMins, endStr),
              const SizedBox(height: 12),
              _buildAlarmToggle(),
              const SizedBox(height: 20),
              _buildRecurringToggle(),
              const SizedBox(height: 24),
              _buildActionButtons(durationMins),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FOCUS DURATION (HH:MM)',
            style: TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // HOURS selector
              Expanded(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        _durationHours = (_durationHours + 1) % 24;
                      }),
                      child: const Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _showNumberPicker(
                        'Hours',
                        _durationHours,
                        0,
                        23,
                        (v) => setState(() => _durationHours = v),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _durationHours.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => setState(() {
                        _durationHours = (_durationHours - 1 + 24) % 24;
                      }),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'HOURS',
                      style: TextStyle(
                        color: Colors.white24,
                        fontFamily: 'monospace',
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  ':',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              // MINUTES selector
              Expanded(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        _durationMinutes = (_durationMinutes + 5) % 60;
                      }),
                      child: const Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _showNumberPicker(
                        'Minutes',
                        _durationMinutes,
                        0,
                        55,
                        (v) => setState(() => _durationMinutes = v),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _durationMinutes.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => setState(() {
                        _durationMinutes = (_durationMinutes - 5 + 60) % 60;
                      }),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'MINS',
                      style: TextStyle(
                        color: Colors.white24,
                        fontFamily: 'monospace',
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quick preset buttons
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _presetChip('15m', 0, 15),
              _presetChip('30m', 0, 30),
              _presetChip('45m', 0, 45),
              _presetChip('1h', 1, 0),
              _presetChip('1.5h', 1, 30),
              _presetChip('2h', 2, 0),
              _presetChip('3h', 3, 0),
              _presetChip('4h', 4, 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, int h, int m) {
    final active = _durationHours == h && _durationMinutes == m;
    return GestureDetector(
      onTap: () => setState(() {
        _durationHours = h;
        _durationMinutes = m;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: active ? Colors.white : Colors.white12),
          color: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white38,
            fontFamily: 'monospace',
            fontSize: 9,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'START TIME',
            style: TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(selectedTime),
                );
                if (t != null) {
                  setState(() {
                    selectedTime = DateTime(
                      selectedTime.year,
                      selectedTime.month,
                      selectedTime.day,
                      t.hour,
                      t.minute,
                    );
                  });
                }
              },
              child: Text(
                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildTimeButtons(),
        ],
      ),
    );
  }

  Widget _buildTimeButtons() {
    Widget btn(String label, int delta) => GestureDetector(
      onTap: () => setState(
        () => selectedTime = selectedTime.add(Duration(minutes: delta)),
      ),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 8),
          ),
        ),
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        btn('-10', -10),
        const SizedBox(width: 4),
        btn('-5', -5),
        const SizedBox(width: 4),
        btn('-1', -1),
        const SizedBox(width: 12),
        btn('+1', 1),
        const SizedBox(width: 4),
        btn('+5', 5),
        const SizedBox(width: 4),
        btn('+10', 10),
      ],
    );
  }

  Widget _infoField(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontFamily: 'monospace',
                    fontSize: 9,
                  ),
                ),
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
            const Icon(Icons.edit, size: 14, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSummary(int totalMinutes, String endStr) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    final displayStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white.withOpacity(0.02),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _summaryCol('FOCUS DURATION', displayStr),
          _summaryCol('END TIME', endStr),
        ],
      ),
    );
  }

  Widget _summaryCol(String label, String val) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8)),
      Text(
        val,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  Widget _buildAlarmToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'ENABLE ALARM',
            style: TextStyle(color: Colors.white, fontSize: 11),
          ),
          Switch(
            value: isAlarmEnabled,
            onChanged: (v) => setState(() => isAlarmEnabled = v),
            activeThumbColor: Colors.orangeAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringToggle() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'REPEAT WEEKLY',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
              Switch(
                value: isRecurring,
                onChanged: (v) => setState(() => isRecurring = v),
                activeThumbColor: Colors.white,
              ),
            ],
          ),
          if (isRecurring) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].asMap().entries.map(
                (e) {
                  final d = e.key + 1;
                  final sel = recurringDays.contains(d);
                  return GestureDetector(
                    onTap: () => setState(
                      () =>
                          sel ? recurringDays.remove(d) : recurringDays.add(d),
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: sel ? Colors.white : Colors.white10,
                        ),
                        color: sel ? Colors.white : Colors.transparent,
                      ),
                      child: Center(
                        child: Text(
                          e.value,
                          style: TextStyle(
                            color: sel ? Colors.black : Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(int totalDurationMins) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              if (titleCtrl.text.isEmpty) return;
              final task = TimeBlockTask(
                id:
                    widget.existing?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                title: titleCtrl.text,
                description: descCtrl.text,
                tag: selectedTag,
                startTime: selectedTime,
                durationMinutes: durationMins,
                isRecurring: isRecurring,
                recurringDays: isRecurring ? recurringDays : [],
                focusSeconds: widget.existing?.focusSeconds ?? 0,
                isCompleted: widget.existing?.isCompleted ?? false,
                isAlarmEnabled: isAlarmEnabled,
              );
              if (widget.existing != null) {
                await widget.planner.updateTask(task);
              } else {
                await widget.planner.addTask(task);
              }
              if (mounted) Navigator.pop(context);
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
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.existing != null) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              await widget.planner.removeTask(widget.existing!.id);
              if (mounted) Navigator.pop(context);
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }

  void _showNumberPicker(
    String title,
    int current,
    int min,
    int max,
    ValueChanged<int> onSelect,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: ListView.builder(
            itemCount: max - min + 1,
            itemBuilder: (c, i) {
              final v = min + i;
              return ListTile(
                title: Text('$v', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  onSelect(v);
                  Navigator.pop(c);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
