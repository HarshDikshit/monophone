import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/launcher_state.dart';
import '../services/auth_guard.dart';

// ====================================================================
//  AnalyticsScreen – Monochrome (white/grey/black) design
//  -----------------------------------------------------------------
//  Fed by GET /analytics?days=NN. Supports three time-window modes:
//  - DAY    : current day, hourly heatmap
//  - WEEK   : current week (7 days), per-day hourly heatmap
//  - MONTH  : trailing 30 days, per-day hourly heatmap
//  Each mode has < > navigation arrows to move forward/backward.
// ====================================================================

enum _RangeMode { day, week, month }

const _bg = Color(0xFF000000);
const _card = Color(0xFF0A0A0A);
const _border = Color(0xFF1A1A1A);
const _dim = Color(0xFF555555);
const _text = Color(0xFFAAAAAA);
const _white = Color(0xFFFFFFFF);

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _RangeMode _mode = _RangeMode.day;
  int _offset = 0; // navigation offset (0 = most recent period)
  Map<String, dynamic>? _analytics;
  bool _loading = true;
  String? _error;
  final _shareKey = GlobalKey();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _checkAuthThenLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start a periodic timer to refresh analytics data every 15 seconds
    // so focus time metrics update in real-time from pomodoro progress.
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_loading && _offset == 0) {
        // Only auto-refresh when viewing the most recent period
        _silentRefresh();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkAuthThenLoad() async {
    await requireAuth(context, onAuthenticated: _refresh);
  }

  /// Silent refresh — no loading spinner, keeps current offset.
  Future<void> _silentRefresh() async {
    try {
      final data = await ApiService.getAnalytics(daysBack: 30);
      if (!mounted) return;
      setState(() {
        _analytics = data;
      });
    } catch (_) {
      // Silent fail — don't show errors on auto-refresh
    }
  }

  void _goPrev() =>
      setState(() => _offset = math.min(_offset + 1, _maxOffset()));
  void _goNext() => setState(() => _offset = math.max(_offset - 1, 0));

  int _maxOffset() {
    final daily = (_analytics?['daily'] as List? ?? []);
    if (_mode == _RangeMode.day) return math.max(0, daily.length - 1);
    if (_mode == _RangeMode.week) return math.max(0, daily.length - 1);
    return math.max(0, daily.length - 1);
  }

  Future<void> _shareAnalytics() async {
    try {
      final boundary =
          _shareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      await Share.shareXFiles([
        XFile.fromData(
          byteData.buffer.asUint8List(),
          mimeType: 'image/png',
          name: 'analytics.png',
        ),
      ], text: 'My Study Analytics');
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share analytics'),
            backgroundColor: Colors.black,
          ),
        );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<LauncherState>();
      await state.syncStats(); // Manual sync before fetching data
      
      final data = await ApiService.getAnalytics(daysBack: 30);
      if (!mounted) return;
      setState(() {
        _analytics = data;
        _loading = false;
        _offset = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  _DateWindow _resolveWindow(_RangeMode mode, int offset) {
    final daily = (_analytics?['daily'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (daily.isEmpty) return const _DateWindow();
    final allDates = daily.map((d) => d['date'] as String).toList();

    if (mode == _RangeMode.day) {
      final idx = math.max(0, daily.length - 1 - offset);
      final dayData = daily[idx];
      return _DateWindow(
        start: dayData['date'] as String,
        end: dayData['date'] as String,
        rangeLabel: _fmtDateLong(dayData['date'] as String),
        days: [dayData],
        hourly: List<int>.from(dayData['hourly'] ?? new List.filled(24, 0)),
        sessions: List<Map<String, dynamic>>.from(dayData['sessions'] ?? []),
        taskAnalytics: List<Map<String, dynamic>>.from(dayData['taskAnalytics'] ?? []),
        allDates: allDates,
      );
    }
    if (mode == _RangeMode.week) {
      final endIdx = math.max(0, daily.length - 1 - offset * 7);
      final startIdx = math.max(0, endIdx - 6);
      final slice = daily.sublist(startIdx, endIdx + 1);
      final aggregatedHourly = List.filled(24, 0);
      final allSessions = <Map<String, dynamic>>[];
      final allTaskAnalytics = <Map<String, dynamic>>[];
      for (final d in slice) {
        final h = List<int>.from(d['hourly'] ?? List.filled(24, 0));
        for (int i = 0; i < 24; i++) aggregatedHourly[i] += h[i];
        allSessions.addAll(List<Map<String, dynamic>>.from(d['sessions'] ?? []));
        allTaskAnalytics.addAll(List<Map<String, dynamic>>.from(d['taskAnalytics'] ?? []));
      }
      return _DateWindow(
        start: slice.first['date'] as String,
        end: slice.last['date'] as String,
        rangeLabel:
            '${_fmtDateShort(slice.first['date'] as String)} - ${_fmtDateShort(slice.last['date'] as String)}',
        days: slice,
        hourly: aggregatedHourly,
        sessions: allSessions,
        taskAnalytics: allTaskAnalytics,
        allDates: allDates,
      );
    }
    // month
    final endIdx = math.max(0, daily.length - 1 - offset * 30);
    final startIdx = math.max(0, endIdx - 29);
    final slice = daily.sublist(startIdx, endIdx + 1);
    final aggregatedHourly = List.filled(24, 0);
    final allSessions = <Map<String, dynamic>>[];
    final allTaskAnalytics = <Map<String, dynamic>>[];
    for (final d in slice) {
      final h = List<int>.from(d['hourly'] ?? List.filled(24, 0));
      for (int i = 0; i < 24; i++) aggregatedHourly[i] += h[i];
      allSessions.addAll(List<Map<String, dynamic>>.from(d['sessions'] ?? []));
      allTaskAnalytics.addAll(List<Map<String, dynamic>>.from(d['taskAnalytics'] ?? []));
    }
    return _DateWindow(
      start: slice.first['date'] as String,
      end: slice.last['date'] as String,
      rangeLabel: _fmtMonthYear(slice.first['date'] as String),
      days: slice,
      hourly: aggregatedHourly,
      sessions: allSessions,
      taskAnalytics: allTaskAnalytics,
      allDates: allDates,
    );
  }

  List<int> _synthesizeHourly(
    List<Map<String, dynamic>> days,
    List<dynamic> hourlyRaw,
  ) {
    if (days.length != 1) return List.filled(24, 0);
    final hourly = hourlyRaw.map((e) => (e as num).toInt()).toList();
    if (hourly.length != 24) return List.filled(24, 0);
    final dayTotal = ((days.first['studySeconds'] as num?) ?? 0).toInt();
    final sum = hourly.fold<int>(0, (a, b) => a + b);
    if (sum == 0) return List.filled(24, 0);
    return hourly.map((v) => (v * dayTotal / sum).round()).toList();
  }

  String _fmtDateLong(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    const m = [
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
    ];
    return '${int.tryParse(p[2]) ?? 0} ${m[(int.tryParse(p[1]) ?? 1) - 1]} ${p[0]}';
  }

  String _fmtDateShort(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    const m = [
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
    ];
    return '${int.tryParse(p[2]) ?? 0} ${m[(int.tryParse(p[1]) ?? 1) - 1]}';
  }

  String _fmtMonthYear(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    const m = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${m[(int.tryParse(p[1]) ?? 1) - 1]} ${p[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final user = state.userProfile ?? const <String, dynamic>{};
    final window = _resolveWindow(_mode, _offset);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'ANALYTICS',
          style: TextStyle(
            color: _white,
            fontFamily: 'monospace',
            letterSpacing: 3,
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, color: _dim, size: 20),
            onPressed: _shareAnalytics,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: _dim, size: 20),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: _white,
                  strokeWidth: 1.2,
                ),
              )
            : _error != null
            ? _ErrorView(message: _error!, onRetry: _refresh)
            : RefreshIndicator(
                color: _white,
                backgroundColor: _bg,
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    RepaintBoundary(
                      key: _shareKey,
                      child: Column(
                        children: [
                          _ProfileHeader(
                            name: (user['name'] ?? 'focus-hero').toString(),
                            rangeLabel: window.rangeLabel,
                          ),
                          const SizedBox(height: 20),
                          _RangeToggle(
                            mode: _mode,
                            onChanged: (m) => setState(() {
                              _mode = m;
                              _offset = 0;
                            }),
                          ),
                          const SizedBox(height: 16),
                          _NavBar(
                            canGoBack: _offset < _maxOffset(),
                            canGoForward: _offset > 0,
                            onBack: _goPrev,
                            onForward: _goNext,
                          ),
                          const SizedBox(height: 16),
                          _StatsRow(
                            window: window,
                            completedTasks: _completedTaskCount(state, window),
                            nonCompletedTasks: _nonCompletedTaskCount(
                              state,
                              window,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _FocusPeriodsCard(
                            mode: _mode,
                            window: window,
                          ),
                          const SizedBox(height: 18),
                          _FocusDistributionCard(window: window, state: state),
                          const SizedBox(height: 18),
                          _TaskAnalyticsCard(window: window),
                          const SizedBox(height: 18),
                          if (_mode != _RangeMode.day) ...[
                            _FocusTimeBarCard(days: window.days),
                            const SizedBox(height: 18),
                          ],
                          _GoalAchievementCard(
                            mode: _mode,
                            window: window,
                            state: state,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  int _completedTaskCount(LauncherState state, _DateWindow window) {
    return _taskCounts(state, window).$1;
  }

  int _nonCompletedTaskCount(LauncherState state, _DateWindow window) {
    return _taskCounts(state, window).$2;
  }

  (int, int) _taskCounts(LauncherState state, _DateWindow window) {
    final tasks = state.tasks;
    if (tasks.isEmpty) return (0, 0);
    final start = DateTime.parse('${window.start}T00:00:00');
    final end = DateTime.parse('${window.end}T23:59:59');
    int completed = 0;
    int nonCompleted = 0;
    for (final t in tasks) {
      final isDone = t['isDone'] == true;
      final created = t['createdAt'];
      bool inWindow = false;
      if (created is String) {
        try {
          final d = DateTime.parse(created);
          if (!d.isBefore(start) && !d.isAfter(end)) {
            inWindow = true;
          }
        } catch (_) {}
      }
      if (!inWindow && _mode == _RangeMode.day) {
        inWindow = true;
      }
      if (inWindow) {
        if (isDone) {
          completed++;
        } else {
          nonCompleted++;
        }
      }
    }
    return (completed, nonCompleted);
  }
}

// ── Model ────────────────────────────────────────────────────────────
class _DateWindow {
  final String start, end, rangeLabel;
  final List<Map<String, dynamic>> days;
  final List<int> hourly;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> taskAnalytics;
  final List<String> allDates; // full available dates for offset calc
  const _DateWindow({
    this.start = '',
    this.end = '',
    this.rangeLabel = '',
    this.days = const [],
    this.hourly = const [],
    this.sessions = const [],
    this.taskAnalytics = const [],
    this.allDates = const [],
  });
  int get totalStudySeconds => days.fold<int>(
    0,
    (a, d) => a + ((d['studySeconds'] as num?) ?? 0).toInt(),
  );
}

String _fmtHM(int s) {
  if (s <= 0) return '0m';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String _fmtHMD(int s) {
  if (s <= 0) return '0';
  final h = s / 3600.0;
  if (h >= 1) return h.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return ((s / 3600.0) * 10).round().toString();
}

// ── Navigation Bar ──────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final bool canGoBack, canGoForward;
  final VoidCallback onBack, onForward;
  const _NavBar({
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: canGoBack ? onBack : null,
          child: Icon(
            Icons.chevron_left,
            color: canGoBack ? _white : _border,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: canGoForward ? onForward : null,
          child: Icon(
            Icons.chevron_right,
            color: canGoForward ? _white : _border,
            size: 28,
          ),
        ),
      ],
    );
  }
}

// ── Profile Header ──────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final String name, rangeLabel;
  const _ProfileHeader({required this.name, required this.rangeLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 4),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: _white, width: 1.5),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'F',
            style: const TextStyle(
              color: _white,
              fontSize: 28,
              fontWeight: FontWeight.w200,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            color: _white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '///',
              style: TextStyle(
                color: _dim,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                rangeLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '///',
              style: TextStyle(
                color: _dim,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Range Toggle ───────────────────────────────────────────────────
class _RangeToggle extends StatelessWidget {
  final _RangeMode mode;
  final ValueChanged<_RangeMode> onChanged;
  const _RangeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _border)),
      child: Row(
        children: [
          _tab('DAY', _RangeMode.day),
          _tab('WEEK', _RangeMode.week),
          _tab('MONTH', _RangeMode.month),
        ],
      ),
    );
  }

  Widget _tab(String label, _RangeMode m) {
    final sel = mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(m),
        child: Container(
          height: 34,
          color: sel ? _white : Colors.transparent,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: sel ? _bg : _dim,
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stats Row ──────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final _DateWindow window;
  final int completedTasks;
  final int nonCompletedTasks;
  const _StatsRow({
    required this.window,
    required this.completedTasks,
    required this.nonCompletedTasks,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'FOCUS TIME',
            child: _FocusTimeText(seconds: window.totalStudySeconds),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'COMPLETED',
            child: Text(
              '$completedTasks',
              style: const TextStyle(
                color: _white,
                fontSize: 36,
                fontWeight: FontWeight.w200,
                fontFamily: 'monospace',
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final Widget child;
  const _StatCard({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _dim,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FocusTimeText extends StatelessWidget {
  final int seconds;
  const _FocusTimeText({required this.seconds});
  @override
  Widget build(BuildContext context) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$h',
          style: const TextStyle(
            color: _white,
            fontSize: 38,
            fontWeight: FontWeight.w200,
            fontFamily: 'monospace',
            height: 1.0,
          ),
        ),
        const SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'h',
            style: const TextStyle(
              color: _dim,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$m',
          style: const TextStyle(
            color: _white,
            fontSize: 38,
            fontWeight: FontWeight.w200,
            fontFamily: 'monospace',
            height: 1.0,
          ),
        ),
        const SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'm',
            style: const TextStyle(
              color: _dim,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

// ── Focus Periods ─────────────────────────────────────────────────
class _FocusPeriodsCard extends StatelessWidget {
  final _RangeMode mode;
  final _DateWindow window;
  const _FocusPeriodsCard({required this.mode, required this.window});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Focus Periods',
      child: Column(
        children: [
          const SizedBox(height: 12),
          _TimelineHeader(),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: _SessionTimeline(sessions: window.sessions),
          ),
          const SizedBox(height: 12),
          const _TimeAxis(),
        ],
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem('☀', 'Day', Colors.amber),
        const SizedBox(width: 24),
        _legendItem('☾', 'Night', _dim),
      ],
    );
  }

  Widget _legendItem(String icon, String label, Color color) => Row(
    children: [
      Text(icon, style: TextStyle(color: color, fontSize: 12)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: _dim, fontSize: 9, fontFamily: 'monospace')),
    ],
  );
}

class _SessionTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  const _SessionTimeline({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        painter: _SessionTimelinePainter(sessions: sessions),
      ),
    );
  }
}

class _SessionTimelinePainter extends CustomPainter {
  final List<Map<String, dynamic>> sessions;
  _SessionTimelinePainter({required this.sessions});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background segments (6am-6pm day, else night)
    final dayPaint = Paint()..color = _white.withValues(alpha: 0.03);
    final nightPaint = Paint()..color = _white.withValues(alpha: 0.01);
    
    // Simple 24h split for visual guide
    final hrW = w / 24;
    canvas.drawRect(Rect.fromLTWH(0, 0, 6 * hrW, h), nightPaint);
    canvas.drawRect(Rect.fromLTWH(6 * hrW, 0, 12 * hrW, h), dayPaint);
    canvas.drawRect(Rect.fromLTWH(18 * hrW, 0, 6 * hrW, h), nightPaint);

    if (sessions.isEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'No sessions recorded for this period',
          style: TextStyle(
            color: _white.withValues(alpha: 0.2),
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2),
      );
      return;
    }

    for (final s in sessions) {
      final startStr = s['startTime'] as String?;
      if (startStr == null) continue;
      final startTime = DateTime.tryParse(startStr)?.toLocal();
      if (startTime == null) continue;

      final actualSec = (s['actualSeconds'] as num? ?? 0).toDouble();
      final definedSec = (s['definedSeconds'] as num? ?? actualSec).toDouble();
      if (definedSec <= 0) continue;

      // Calculate X position (0-24h)
      final hourFrac = startTime.hour + (startTime.minute / 60.0);
      final startX = hourFrac * hrW;
      
      // Calculate width (proportional to defined duration)
      final width = (definedSec / 3600.0) * hrW;
      
      // Bar styling
      final rect = Rect.fromLTWH(startX, h * 0.1, width.clamp(2.0, w), h * 0.8);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      
      // Draw "Defined" background
      final bgPaint = Paint()..color = const Color(0xFF222222);
      canvas.drawRRect(rrect, bgPaint);

      // Draw "Actual" filling
      final fillRatio = (actualSec / definedSec).clamp(0.0, 1.0);
      final fillWidth = width * fillRatio;
      if (fillWidth > 0.5) {
        final fillRect = Rect.fromLTWH(startX, h * 0.1, fillWidth.clamp(1.0, width), h * 0.8);
        final fillRRect = RRect.fromRectAndRadius(fillRect, const Radius.circular(2));
        final fillPaint = Paint()..color = _white.withValues(alpha: 0.8);
        canvas.drawRRect(fillRRect, fillPaint);
      }
      
      // Border
      final borderPaint = Paint()..color = _white.withValues(alpha: 0.2)..style = PaintingStyle.stroke..strokeWidth = 0.5;
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SessionTimelinePainter old) => old.sessions != sessions;
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis();
  @override
  Widget build(BuildContext context) {
    const labels = [
      '00:00',
      '04:00',
      '08:00',
      '12:00',
      '16:00',
      '20:00',
      '24:00',
    ];
    return SizedBox(
      height: 12,
      child: Row(
        children: labels
            .map(
              (l) => Expanded(
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _dim,
                    fontSize: 7,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DayHeatmap extends StatelessWidget {
  final List<int> hourly;
  const _DayHeatmap({required this.hourly});
  @override
  Widget build(BuildContext context) {
    final maxV = hourly.isEmpty ? 0 : hourly.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 50,
      child: CustomPaint(
        size: Size.infinite,
        painter: _DayHeatmapPainter(
          hourly: hourly,
          maxValue: maxV == 0 ? 1 : maxV,
        ),
      ),
    );
  }
}

class _DayHeatmapPainter extends CustomPainter {
  final List<int> hourly;
  final int maxValue;
  _DayHeatmapPainter({required this.hourly, required this.maxValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (hourly.isEmpty) return;
    final cellW = size.width / 24.0, h = size.height;
    final dayPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    final nightPaint = Paint()..color = _white.withValues(alpha: 0.02);
    canvas.drawRect(Rect.fromLTWH(6 * cellW, 0, 12 * cellW, h), dayPaint);
    canvas.drawRect(Rect.fromLTWH(0, 0, 6 * cellW, h), nightPaint);
    canvas.drawRect(Rect.fromLTWH(18 * cellW, 0, 6 * cellW, h), nightPaint);

    for (int hr = 0; hr < 24; hr++) {
      final v = hourly[hr];
      if (v <= 0) continue;
      
      // Width proportional to study seconds in that hour
      final ratio = (v / 3600.0).clamp(0.05, 1.0);
      final bw = cellW * ratio;
      final bh = h * 0.8; // Fixed height for a cleaner timeline look
      
      final Paint p = Paint()
        ..color = _white.withValues(alpha: (0.5 + ratio * 0.4).clamp(0.5, 0.9));
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            hr * cellW + (cellW - bw) / 2, 
            (h - bh) / 2, 
            bw, 
            bh
          ),
          const Radius.circular(1.0),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DayHeatmapPainter old) => old.hourly != hourly;
}

// ── Card Shell ─────────────────────────────────────────────────────
class _CardShell extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _CardShell({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                color: _white.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: _white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          child,
        ],
      ),
    );
  }
}

// ── Focus Time Distribution (task vs non-task) ────────────────────
class _TaskAnalyticsCard extends StatelessWidget {
  final _DateWindow window;
  const _TaskAnalyticsCard({required this.window});

  @override
  Widget build(BuildContext context) {
    // Collect all taskAnalytics from all days in the window
    final Map<String, (String, int)> taskTotals = {};
    for (final day in window.days) {
      final list = day['taskAnalytics'] as List? ?? [];
      for (final item in list) {
        final id = item['taskId'] as String? ?? 'unknown';
        final title = item['title'] as String? ?? 'Untitled Task';
        final sec = (item['seconds'] as num? ?? 0).toInt();
        if (taskTotals.containsKey(id)) {
          taskTotals[id] = (title, taskTotals[id]!.$2 + sec);
        } else {
          taskTotals[id] = (title, sec);
        }
      }
    }

    // Filter tasks >= 1 minute
    final sortedTasks = taskTotals.entries
        .where((e) => e.value.$2 >= 60)
        .toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));

    if (sortedTasks.isEmpty) {
      return _CardShell(
        title: 'Task Analytics',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              'No task focus > 1m recorded',
              style: TextStyle(
                color: _white.withValues(alpha: 0.2),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      );
    }

    return _CardShell(
      title: 'Task Analytics',
      child: Column(
        children: [
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedTasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = sortedTasks[index].value;
              final totalStudy = window.totalStudySeconds.clamp(1, 1000000);
              final pct = (task.$2 / totalStudy).clamp(0.0, 1.0);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          task.$1,
                          style: const TextStyle(
                            color: _white,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_fmtHMD(task.$2)}h',
                        style: const TextStyle(
                          color: _white,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    children: [
                      Container(
                        height: 4,
                        width: double.infinity,
                        color: _white.withValues(alpha: 0.05),
                      ),
                      FractionallySizedBox(
                        widthFactor: pct,
                        child: Container(
                          height: 4,
                          color: _white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Focus Time Distribution (task vs non-task) ────────────────────
class _FocusDistributionCard extends StatelessWidget {
  final _DateWindow window;
  final LauncherState state;
  const _FocusDistributionCard({required this.window, required this.state});

  @override
  Widget build(BuildContext context) {
    final isDay = window.days.length == 1;

    // For DAY view: focus time vs goal (from launcher state)
    if (isDay) {
      final goal = _goalSeconds(state.lastGoal);
      final study = window.totalStudySeconds;
      final pct = (study / goal).clamp(0.0, 1.0);

      return _CardShell(
        title: 'Focus Time Distribution',
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  size: const Size(150, 150),
                  painter: _DonutPainter(
                    segments: [pct, 1 - pct],
                    colors: const [_white, Color(0xFF222222)],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(pct * 100).round()}%',
                          style: const TextStyle(
                            color: _white,
                            fontSize: 26,
                            fontWeight: FontWeight.w200,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmtHMD(study)}h',
                          style: const TextStyle(
                            color: _dim,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(_white),
                const SizedBox(width: 4),
                const Text(
                  'Focus',
                  style: TextStyle(
                    color: _dim,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 16),
                _legendDot(const Color(0xFF222222)),
                const SizedBox(width: 4),
                const Text(
                  'Remaining',
                  style: TextStyle(
                    color: _dim,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: Stack(
                          children: [
                            Container(
                              height: 6,
                              color: const Color(0xFF1A1A1A),
                            ),
                            FractionallySizedBox(
                              widthFactor: pct.clamp(0.0, 1.0),
                              child: Container(height: 6, color: _white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_fmtHMD(study)}h / ${_fmtHMD(goal)}h',
                      style: const TextStyle(
                        color: _dim,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    // For WEEK / MONTH: task vs non-task
    final Map<String, (String, int)> taskTotals = {};
    for (final item in window.taskAnalytics) {
      final id = item['taskId'] as String? ?? 'unknown';
      final title = item['title'] as String? ?? 'Task';
      final sec = (item['seconds'] as num? ?? 0).toInt();
      taskTotals[id] = (title, (taskTotals[id]?.$2 ?? 0) + sec);
    }
    
    int taskStudySecTotal = taskTotals.values.fold(0, (a, b) => a + b.$2);
    final sorted = taskTotals.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    String topTask = sorted.isEmpty ? 'None' : sorted.first.value.$1;
    final totalStudySec = window.totalStudySeconds;
    final taskPct = totalStudySec > 0 ? (taskStudySecTotal / totalStudySec).clamp(0.0, 1.0) : 0.0;

    return _CardShell(
      title: 'Focus Time Distribution',
      child: Column(
        children: [
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: CustomPaint(
                size: const Size(150, 150),
                painter: _DonutPainter(
                  segments: [taskPct, 1 - taskPct],
                  colors: const [_white, Color(0xFF222222)],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(taskPct * 100).round()}%',
                        style: const TextStyle(
                          color: _white,
                          fontSize: 26,
                          fontWeight: FontWeight.w200,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmtHMD(taskStudySecTotal)}h',
                        style: const TextStyle(
                          color: _dim,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(_white),
              const SizedBox(width: 4),
              const Text(
                'Task',
                style: TextStyle(
                  color: _dim,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFF222222)),
              const SizedBox(width: 4),
              const Text(
                'Non-Task',
                style: TextStyle(
                  color: _dim,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (topTask.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Top: $topTask',
                style: const TextStyle(
                  color: _white,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: Stack(
                        children: [
                          Container(height: 6, color: const Color(0xFF1A1A1A)),
                          FractionallySizedBox(
                            widthFactor: taskPct.clamp(0.0, 1.0),
                            child: Container(height: 6, color: _white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_fmtHMD(taskStudySecTotal)}h / ${_fmtHMD(window.totalStudySeconds)}h',
                    style: const TextStyle(
                      color: _dim,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _goalSeconds(String? t) {
    if (t == null || t.isEmpty) return 6 * 3600;
    final m = RegExp(r'(\d+)\s*hours?').firstMatch(t);
    return ((m != null ? int.tryParse(m.group(1)!) : null) ?? 6) * 3600;
  }

  Widget _legendDot(Color c) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
  );
}

class _DonutPainter extends CustomPainter {
  final List<double> segments;
  final List<Color> colors;
  _DonutPainter({required this.segments, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 18.0, half = stroke / 2;
    final arcRect = Rect.fromLTWH(
      half,
      half,
      size.width - stroke,
      size.height - stroke,
    );
    double start = -math.pi / 2;
    for (int i = 0; i < segments.length; i++) {
      final sweep = segments[i] * 2 * math.pi;
      if (sweep <= 0) continue;
      final p = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(arcRect, start, sweep, false, p);
      start += sweep;
    }
    final bg = Paint()
      ..color = _bg
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      arcRect.center,
      math.min(size.width, size.height) / 2 - stroke,
      bg,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segments != segments || old.colors != colors;
}

// ── Focus Time Bar Chart (clickable, with day tooltip for week & month) ─
class _FocusTimeBarCard extends StatefulWidget {
  final List<Map<String, dynamic>> days;
  const _FocusTimeBarCard({required this.days});
  @override
  State<_FocusTimeBarCard> createState() => _FocusTimeBarCardState();
}

class _FocusTimeBarCardState extends State<_FocusTimeBarCard> {
  int _selectedBarIndex = -1;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty)
      return _CardShell(
        title: 'Focus Time',
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No data',
            style: TextStyle(color: _dim, fontFamily: 'monospace'),
          ),
        ),
      );

    final values = days
        .map((d) => (((d['studySeconds'] as num?) ?? 0).toInt()) / 3600.0)
        .toList();
    final maxV = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(0.5, double.infinity);
    final activeDays = values.where((v) => v > 0).length;
    final avg = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;

    return _CardShell(
      title: 'Focus Time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (_selectedBarIndex >= 0 && _selectedBarIndex < days.length)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${days[_selectedBarIndex]['date']}: ${_fmtHM((values[_selectedBarIndex] * 3600).round())}',
                style: const TextStyle(
                  color: _white,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Tap a bar for details',
                style: TextStyle(
                  color: _dim,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          SizedBox(
            height: 140,
            child: _BarChart(
              values: values,
              maxValue: maxV,
              maxLabel: maxV.toStringAsFixed(1),
              totalDays: days.length,
              selectedIndex: _selectedBarIndex,
              onBarTap: (i) => setState(
                () => _selectedBarIndex = _selectedBarIndex == i ? -1 : i,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Days Focused',
                  value: activeDays.toString(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Average Daily',
                  value: avg >= 1
                      ? '${avg.toStringAsFixed(1)}h'
                      : '${(avg * 60).round()}m',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<double> values;
  final double maxValue;
  final String maxLabel;
  final int totalDays;
  final int selectedIndex;
  final ValueChanged<int> onBarTap;
  const _BarChart({
    required this.values,
    required this.maxValue,
    required this.maxLabel,
    required this.totalDays,
    required this.selectedIndex,
    required this.onBarTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final n = values.length;
        if (n == 0) return const SizedBox.shrink();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    maxLabel,
                    style: const TextStyle(
                      color: _dim,
                      fontSize: 8,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Text(
                    '0',
                    style: TextStyle(
                      color: _dim,
                      fontSize: 8,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(n, (i) {
                  final v = values[i];
                  final ratio = maxValue > 0
                      ? (v / maxValue).clamp(0.0, 1.0)
                      : 0.0;
                  final isSel = selectedIndex == i;
                  final nCols = n <= 31 ? n : 31;
                  final gap = n <= 31 ? (n <= 7 ? 3.0 : 1.5) : 0.5;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onBarTap(i),
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: gap),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: (c.maxHeight - 16) * ratio,
                              decoration: BoxDecoration(
                                color: isSel
                                    ? _white
                                    : _white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (nCols <= 7)
                              Text(
                                ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'][i
                                    .clamp(0, 6)],
                                style: TextStyle(
                                  color: isSel ? _white : _dim,
                                  fontSize: 7,
                                  fontFamily: 'monospace',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF060606),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _dim,
              fontSize: 9,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: _white,
              fontSize: 18,
              fontWeight: FontWeight.w200,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Goal Achievement ──────────────────────────────────────────────
class _GoalAchievementCard extends StatefulWidget {
  final _RangeMode mode;
  final _DateWindow window;
  final LauncherState state;
  const _GoalAchievementCard({
    required this.mode,
    required this.window,
    required this.state,
  });
  @override
  State<_GoalAchievementCard> createState() => _GoalAchievementCardState();
}

class _GoalAchievementCardState extends State<_GoalAchievementCard> {
  final _goalCtrl = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _goalCtrl.text = _parsed();
  }

  @override
  void didUpdateWidget(_GoalAchievementCard old) {
    super.didUpdateWidget(old);
    if (!_isEditing) _goalCtrl.text = _parsed();
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }

  int _goalSec(String? t) {
    if (t == null || t.isEmpty) return 6 * 3600;
    final m = RegExp(r'(\d+)\s*hours?').firstMatch(t);
    return (m != null ? int.tryParse(m.group(1)!) : null) ?? 6;
  }

  String _parsed() {
    final g = widget.state.lastGoal;
    if (g.isEmpty) return '6 hours';
    final m = RegExp(r'(\d+)\s*hours?').firstMatch(g);
    return m != null ? '${m.group(1)} hours' : '6 hours';
  }

  int get _goal => _goalSec(widget.state.lastGoal) * 3600;

  Future<void> _save() async {
    final t = _goalCtrl.text.trim();
    if (t.isNotEmpty) await widget.state.setTargetGoal(t);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goal updated'),
          backgroundColor: Colors.black,
          duration: Duration(seconds: 1),
        ),
      );
      setState(() => _isEditing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = _goal;
    return _CardShell(
      title: 'Goal Achievement',
      trailing: GestureDetector(
        onTap: () => setState(() => _isEditing = !_isEditing),
        child: Icon(
          _isEditing ? Icons.check : Icons.edit,
          color: _dim,
          size: 14,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          if (_isEditing)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _goalCtrl,
                    style: const TextStyle(
                      color: _white,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                    cursorColor: _white,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 10 hours daily',
                      hintStyle: TextStyle(color: _dim),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _border),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _white),
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: _border),
                    ),
                    child: const Text(
                      'SAVE',
                      style: TextStyle(
                        color: _white,
                        fontFamily: 'monospace',
                        fontSize: 8,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            GestureDetector(
              onTap: () => setState(() => _isEditing = true),
              child: Row(
                children: [
                  Text(
                    'Daily Goal: ${_parsed()}',
                    style: const TextStyle(
                      color: _dim,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, color: _dim, size: 10),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (widget.mode == _RangeMode.day)
            _DayGoalRing(study: widget.window.totalStudySeconds, goal: goal)
          else if (widget.mode == _RangeMode.week)
            _WeekGoalRings(
              days: widget.window.days.take(7).toList(),
              goal: goal,
            )
          else
            _MonthGoalGrid(days: widget.window.days, goal: goal),
        ],
      ),
    );
  }
}

class _DayGoalRing extends StatelessWidget {
  final int study, goal;
  const _DayGoalRing({required this.study, required this.goal});

  @override
  Widget build(BuildContext context) {
    final pct = (study / goal).clamp(0.0, 1.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _FocusTimeText(seconds: study)),
        const SizedBox(width: 6),
        const Spacer(),
        Text(
          '/ ${_fmtHM(goal)}',
          style: const TextStyle(
            color: _dim,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          height: 80,
          child: CustomPaint(
            painter: _CircularProgressPainter(
              value: pct,
              progressColor: _white.withValues(alpha: 0.8),
            ),
            child: Center(
              child: Text(
                '${(pct * 100).round()}%',
                style: const TextStyle(
                  color: _white,
                  fontSize: 16,
                  fontWeight: FontWeight.w200,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekGoalRings extends StatelessWidget {
  final List<Map<String, dynamic>> days;
  final int goal;
  const _WeekGoalRings({required this.days, required this.goal});

  @override
  Widget build(BuildContext context) {
    const w = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final study = (i < days.length ? days[i] : null)?['studySeconds'] ?? 0;
        final pct = (((study as num?) ?? 0).toInt() / goal).clamp(0.0, 1.0);
        return Column(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CustomPaint(
                painter: _CircularProgressPainter(
                  value: pct,
                  strokeWidth: 2.5,
                  progressColor: _white.withValues(alpha: 0.7),
                ),
                child: Center(
                  child: Text(
                    '${(pct * 100).round()}',
                    style: const TextStyle(
                      color: _white,
                      fontSize: 6,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              w[i],
              style: const TextStyle(
                color: _dim,
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _MonthGoalGrid extends StatelessWidget {
  final List<Map<String, dynamic>> days;
  final int goal;
  const _MonthGoalGrid({required this.days, required this.goal});

  @override
  Widget build(BuildContext context) {
    const w = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    String firstDate = days.isEmpty
        ? ''
        : (days.first['date'] as String? ?? '');
    int pad = 0;
    if (firstDate.isNotEmpty) {
      final dt = DateTime.tryParse(firstDate);
      if (dt != null) pad = (dt.weekday - 1).clamp(0, 6);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: w
              .map(
                (l) => Text(
                  l,
                  style: const TextStyle(
                    color: _dim,
                    fontSize: 8,
                    fontFamily: 'monospace',
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (int p = 0; p < pad; p++) const SizedBox(width: 32, height: 32),
            for (final d in days) _dayCell(d, goal),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(Map<String, dynamic> d, int goal) {
    final study = ((d['studySeconds'] as num?) ?? 0).toInt();
    final pct = (study / goal).clamp(0.0, 1.0);
    final dayNum = (d['date'] as String? ?? '').split('-').last;
    return SizedBox(
      width: 32,
      height: 32,
      child: CustomPaint(
        painter: _CircularProgressPainter(
          value: pct,
          strokeWidth: 3,
          progressColor: _white.withValues(alpha: 0.6),
        ),
        child: Center(
          child: Text(
            dayNum,
            style: const TextStyle(
              color: _white,
              fontSize: 10,
              fontWeight: FontWeight.w400,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double value, strokeWidth;
  final Color progressColor;
  _CircularProgressPainter({
    required this.value,
    this.progressColor = _white,
    this.strokeWidth = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final track = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);
    if (value > 0) {
      final fg = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        value * 2 * math.pi,
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter old) =>
      old.value != value;
}

// ── Error View ────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: _dim, size: 36),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _dim,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onRetry,
            child: const Text(
              'RETRY',
              style: TextStyle(
                color: _white,
                fontSize: 11,
                fontFamily: 'monospace',
                letterSpacing: 1.5,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
