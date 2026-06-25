import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/launcher_state.dart';

/// A compact left-panel sidebar with:
///   - Quick Task Block Creation
///   - Compact Timeline View
///   - Global Focus Timer Play/Pause controls
class LeftPanelWidget extends StatefulWidget {
  final VoidCallback? onToggleView;
  final VoidCallback? onAddTask;

  const LeftPanelWidget({super.key, this.onToggleView, this.onAddTask});

  @override
  State<LeftPanelWidget> createState() => _LeftPanelWidgetState();
}

class _LeftPanelWidgetState extends State<LeftPanelWidget> {
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);

    return Container(
      width: 60,
      color: Colors.black,
      child: Column(
        children: [
          const SizedBox(height: 8),
          // ── Quick Task Creation ──
          _panelBtn(
            icon: Icons.add,
            label: 'TASK',
            onTap: widget.onAddTask ?? () {},
          ),
          const SizedBox(height: 12),
          // ── Timeline / View toggle ──
          _panelBtn(
            icon: Icons.calendar_view_week,
            label: 'VIEW',
            onTap: widget.onToggleView ?? () {},
          ),
          const Spacer(),
          // ── Focus Global Controls ──
          _panelBtn(
            icon: state.isFocusActive ? Icons.pause : Icons.play_arrow,
            label: state.isFocusActive ? 'STOP' : 'START',
            color: state.isFocusActive ? Colors.redAccent : Colors.white,
            onTap: () {
              if (state.isFocusActive) {
                state.stopFocusTimer(manual: true);
              } else {
                state.startFocusTimer();
              }
            },
          ),
          const SizedBox(height: 8),
          // ── Focus timer mini display ──
          if (state.isFocusActive) ...[
            Text(
              state.focusElapsedSecondsFormatted,
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  String _fmtTime(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _panelBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          color: Colors.white.withOpacity(0.03),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontFamily: 'monospace',
                fontSize: 6,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
