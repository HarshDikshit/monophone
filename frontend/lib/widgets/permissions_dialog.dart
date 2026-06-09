import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/launcher_state.dart';

/// A dialog that checks all required permissions and shows toggle buttons
/// for the user to enable/disable each one.
class PermissionsDialog extends StatefulWidget {
  final Map<String, bool> permissions;
  final VoidCallback? onRefresh;

  const PermissionsDialog({
    super.key,
    required this.permissions,
    this.onRefresh,
  });

  /// Show the dialog and return true if all permissions are granted
  static Future<bool> showIfNeeded(BuildContext context) async {
    final state = Provider.of<LauncherState>(context, listen: false);
    final perms = await state.checkAllPermissions();
    final allGranted = perms.values.every((v) => v == true);
    if (allGranted) return true;

    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PermissionsDialog(permissions: perms),
    );
    return result ?? false;
  }

  @override
  State<PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<PermissionsDialog>
    with WidgetsBindingObserver {
  late Map<String, bool> _perms;
  Timer? _autoRecheckTimer;

  static const _permLabels = {
    'usageStats': 'Usage Stats Access',
    'overlay': 'Overlay Permission',
    'notification': 'Notification Permission',
    'accessibility': 'Accessibility Service',
    'defaultLauncher': 'Default Launcher',
    'notificationListener': 'Notification Listener',
  };

  static const _permDescriptions = {
    'usageStats': 'Required to track app usage time and enforce daily limits',
    'overlay': 'Required to show blocker overlays and focus screens',
    'notification': 'Required for focus timer notifications',
    'accessibility': 'Required for auto lock screen and app blocking',
    'defaultLauncher': 'Required to intercept app launches for blocking',
    'notificationListener': 'Required to silence notifications during focus',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _perms = Map.from(widget.permissions);
    // Auto-recheck after initial load in case permissions are already good
    _recheckAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRecheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      // User just returned from system settings - recheck immediately
      _recheckAll();
    }
  }

  Future<void> _recheckAll() async {
    _autoRecheckTimer?.cancel();
    final state = Provider.of<LauncherState>(context, listen: false);
    final updated = await state.checkAllPermissions();
    if (!mounted) return;
    setState(() => _perms = updated);
    widget.onRefresh?.call();

    // If all granted now, auto-close after a moment
    if (updated.values.every((v) => v == true)) {
      _autoRecheckTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) Navigator.pop(context, true);
      });
    }
  }

  Future<void> _requestPermission(String name) async {
    final state = Provider.of<LauncherState>(context, listen: false);
    await state.requestPermissionByName(name);

    // Re-check after a delayed period to let system process
    _autoRecheckTimer?.cancel();
    _autoRecheckTimer = Timer(const Duration(seconds: 2), () {
      _recheckAll();
    });
  }

  bool get _allGranted => _perms.values.every((v) => v == true);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allGranted,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'REQUIRED PERMISSIONS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _allGranted
                      ? 'All permissions are granted. Tap Continue.'
                      : 'Enable all permissions for the app to function correctly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _allGranted ? Colors.green : Colors.grey[500],
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: ListView(
                    children: _perms.entries.map((entry) {
                      final name = entry.key;
                      final granted = entry.value;
                      final label = _permLabels[name] ?? name;
                      final desc = _permDescriptions[name] ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: granted
                                ? Colors.green.withOpacity(0.3)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: granted
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.05),
                              ),
                              child: Icon(
                                granted
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: granted ? Colors.green : Colors.white38,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: granted
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    desc,
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: granted
                                  ? null
                                  : () => _requestPermission(name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: granted
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: granted
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.white24,
                                  ),
                                ),
                                child: Text(
                                  granted ? 'ON' : 'ENABLE',
                                  style: TextStyle(
                                    color: granted
                                        ? Colors.green
                                        : Colors.white54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _allGranted
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: _allGranted ? Colors.white : Colors.white12,
                    ),
                    child: Center(
                      child: Text(
                        _allGranted
                            ? 'CONTINUE'
                            : 'ENABLE ALL PERMISSIONS TO CONTINUE',
                        style: TextStyle(
                          color: _allGranted ? Colors.black : Colors.white30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_allGranted) ...[
                  const SizedBox(height: 12),
                  Text(
                    'After enabling a permission, return here and tap the ENABLE button again to verify.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
