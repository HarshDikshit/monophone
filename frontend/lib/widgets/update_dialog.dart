import 'package:flutter/material.dart';
import 'package:minimalist_launcher/services/update_service.dart';

class UpdateDialog extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final bool isCriticalUpdate;
  final String downloadUrl;
  final VoidCallback? onLater;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    required this.isCriticalUpdate,
    required this.downloadUrl,
    this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !isCriticalUpdate,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          isCriticalUpdate ? '⚠️  CRITICAL UPDATE' : '✨ NEW VERSION AVAILABLE',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            letterSpacing: 1.5,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCriticalUpdate
                    ? 'A critical security or stability update is available. You must update to continue using the app.'
                    : 'A new version is available with performance improvements and new features.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildVersionRow('Current Version', currentVersion),
                    const SizedBox(height: 8),
                    _buildVersionRow(
                      'Latest Version',
                      latestVersion,
                      isLatest: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!isCriticalUpdate)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onLater?.call();
              },
              child: const Text(
                'LATER',
                style: TextStyle(
                  color: Colors.white30,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await UpdateService.openDownloadUrl(downloadUrl);
            },
            child: Text(
              'UPDATE NOW',
              style: TextStyle(
                color: isCriticalUpdate ? Colors.red : Colors.green,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionRow(
    String label,
    String version, {
    bool isLatest = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          version,
          style: TextStyle(
            color: isLatest ? Colors.green : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

/// Show update dialog helper function
Future<void> showUpdateDialog(
  BuildContext context, {
  required String currentVersion,
  required String latestVersion,
  required bool isCriticalUpdate,
  required String downloadUrl,
  VoidCallback? onLater,
}) {
  return showDialog(
    context: context,
    barrierDismissible: !isCriticalUpdate,
    builder: (context) => UpdateDialog(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      isCriticalUpdate: isCriticalUpdate,
      downloadUrl: downloadUrl,
      onLater: onLater,
    ),
  );
}
