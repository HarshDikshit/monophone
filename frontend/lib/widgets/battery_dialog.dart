import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/launcher_state.dart';

/// A sweet, simple, non-dismissible dialog that demands the user
/// set battery optimization to "Unrestricted" before starting the focus timer.
/// 
/// This ensures the timer doesn't get killed by the system in the background.
class BatteryOptimizationDialog extends StatefulWidget {
  final LauncherState state;

  const BatteryOptimizationDialog({super.key, required this.state});

  /// Shows the dialog. Returns true if the user resolved the battery issue,
  /// false if they chose to continue anyway (or cancelled).
  /// Uses the global navigator key from [LauncherState] so it can be shown
  /// even from services without a BuildContext.
  static Future<bool> showIfNeeded() async {
    // Get context from global navigator
    final navKey = LauncherState.navigatorKey;
    if (navKey.currentContext == null) return false;
    final context = navKey.currentContext!;
    final state = Provider.of<LauncherState>(context, listen: false);

    // Check current status
    await state.checkBatteryOptimizationStatus();
    if (state.isBatteryOptimizationIgnored) return true;

    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      useSafeArea: false,
      builder: (ctx) => BatteryOptimizationDialog(state: state),
    );
    return result ?? false;
  }

  @override
  State<BatteryOptimizationDialog> createState() => _BatteryOptimizationDialogState();
}

class _BatteryOptimizationDialogState extends State<BatteryOptimizationDialog> {
  bool _checking = false;
  bool _resolved = false;

  Future<void> _openSettings() async {
    setState(() => _checking = true);
    await widget.state.requestIgnoreBatteryOptimizations();
    // Wait a moment for the settings to take effect
    await Future.delayed(const Duration(seconds: 2));
    await widget.state.checkBatteryOptimizationStatus();
    if (mounted) {
      setState(() {
        _checking = false;
        _resolved = widget.state.isBatteryOptimizationIgnored;
      });
    }
  }

  Future<void> _recheck() async {
    setState(() => _checking = true);
    await widget.state.checkBatteryOptimizationStatus();
    if (mounted) {
      setState(() {
        _checking = false;
        _resolved = widget.state.isBatteryOptimizationIgnored;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _resolved, // Only allow back if resolved
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icon ──
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _resolved
                            ? Colors.green.withOpacity(0.3)
                            : Colors.orange.withOpacity(0.3),
                      ),
                      color: _resolved
                          ? Colors.green.withOpacity(0.05)
                          : Colors.orange.withOpacity(0.05),
                    ),
                    child: Icon(
                      _resolved ? Icons.check_circle : Icons.battery_alert,
                      size: 40,
                      color: _resolved ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Title ──
                  Text(
                    _resolved ? 'ALL SET!' : 'BATTERY OPTIMIZATION',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Description ──
                  Text(
                    _resolved
                        ? 'Your battery is set to unrestricted.\nThe focus timer will run reliably.'
                        : 'To keep the focus timer running reliably\nin the background, set Monophone to\n"Unrestricted" battery mode.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Steps card ──
                  if (!_resolved)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white10),
                        color: Colors.white.withOpacity(0.02),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _step(1, 'Tap "Open Settings" below'),
                          const SizedBox(height: 8),
                          _step(2, 'Tap "Battery" or "Battery Optimization"'),
                          const SizedBox(height: 8),
                          _step(3, 'Select "Unrestricted" mode'),
                          const SizedBox(height: 8),
                          _step(4, 'Come back and tap "Check Again"'),
                        ],
                      ),
                    ),

                  if (!_resolved) const SizedBox(height: 32),

                  // ── Action buttons ──
                  if (!_resolved) ...[
                    // Open Settings button
                    GestureDetector(
                      onTap: _checking ? null : _openSettings,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.orange),
                          color: Colors.orange.withOpacity(0.05),
                        ),
                        child: Center(
                          child: _checking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.orange,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'OPEN SETTINGS',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Check Again button
                    GestureDetector(
                      onTap: _checking ? null : _recheck,
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Center(
                          child: _checking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white54,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'CHECK AGAIN',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    letterSpacing: 1,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Continue anyway (dimmed, smaller)
                    GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'CONTINUE ANYWAY',
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontFamily: 'monospace',
                            fontSize: 10,
                            letterSpacing: 1,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // ── Resolved state ──
                  if (_resolved) ...[
                    GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.green),
                          color: Colors.green.withOpacity(0.05),
                        ),
                        child: const Center(
                          child: Text(
                            'START FOCUSING',
                            style: TextStyle(
                              color: Colors.green,
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
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
        ),
      ),
    );
  }

  Widget _step(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white60,
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}