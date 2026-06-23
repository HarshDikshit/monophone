import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class UpdateService {
  // Uses the same base URL as ApiService - update this to match your backend
  static String get _apiEndpoint => '${ApiService.baseUrl}/version';

  /// Fetch version info from backend
  static Future<Map<String, dynamic>?> fetchLatestVersion() async {
    try {
      final response = await http
          .get(
            Uri.parse(_apiEndpoint),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'latestVersion': data['latestVersion'] as String? ?? '1.0.0',
          'isCriticalUpdate': data['isCriticalUpdate'] as bool? ?? false,
          'downloadUrl': data['downloadUrl'] as String? ?? '',
        };
      }
    } catch (e) {
      debugPrint('Error fetching version info: $e');
    }
    return null;
  }

  /// Get current app version
  static Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      debugPrint('Error getting current version: $e');
      return '0.0.0';
    }
  }

  /// Compare two semantic versions
  /// Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
  static int compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map(int.parse).toList();
      final parts2 = v2.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;

        if (p1 > p2) return 1;
        if (p1 < p2) return -1;
      }
      return 0;
    } catch (e) {
      debugPrint('Error comparing versions: $e');
      return 0;
    }
  }

  /// Check if an update is available
  static Future<bool> isUpdateAvailable() async {
    try {
      final currentVersion = await getCurrentVersion();
      final versionInfo = await fetchLatestVersion();

      if (versionInfo == null) return false;

      final latestVersion = versionInfo['latestVersion'] as String;
      return compareVersions(latestVersion, currentVersion) > 0;
    } catch (e) {
      debugPrint('Error checking update availability: $e');
      return false;
    }
  }

  /// Open download URL in browser
  static Future<bool> openDownloadUrl(String downloadUrl) async {
    try {
      final Uri uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Cannot launch URL: $downloadUrl');
        return false;
      }
    } catch (e) {
      debugPrint('Error opening download URL: $e');
      return false;
    }
  }

  /// Check for updates and return the update info if available
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTime = prefs.getInt('last_update_check_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Only check once every 24 hours
      if (now - lastCheckTime < 24 * 60 * 60 * 1000) {
        debugPrint(
          'Performance: Skipping update check (last check was < 24h ago)',
        );
        return null;
      }

      final currentVersion = await getCurrentVersion();
      final versionInfo = await fetchLatestVersion();

      if (versionInfo == null) return null;

      final latestVersion = versionInfo['latestVersion'] as String;
      final comparison = compareVersions(latestVersion, currentVersion);

      if (comparison > 0) {
        return versionInfo;
      }

      // Record success check even if no update found
      await prefs.setInt('last_update_check_time', now);
    } catch (e) {
      debugPrint('Error in checkForUpdate: $e');
    }
    return null;
  }
}
