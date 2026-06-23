import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // The production API URL is injected at build time.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.8:5000/api',
  );
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_email');
    await prefs.remove('auth_password');
  }

  /// Save credentials for silent re-authentication.
  /// The backend now issues tokens with no expiry, but this ensures
  /// that if the token ever becomes invalid (e.g. secret rotation),
  /// the app can silently re-login without bothering the user.
  static Future<void> saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_email', email);
    await prefs.setString('auth_password', password);
  }

  /// Attempt silent re-login using stored credentials.
  /// Returns true if a new token was obtained.
  static Future<bool> trySilentReauth() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('auth_email');
    final password = prefs.getString('auth_password');
    if (email == null || password == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['token'] != null) {
          await saveToken(data['token'] as String);
          return true;
        }
      }
    } catch (_) {
      // Network error — silent fail, app works offline
    }
    return false;
  }

  /// Make an HTTP request with automatic silent re-authentication on 401/403.
  /// If the request fails with an auth error, it will attempt to re-login
  /// with stored credentials and retry the request once.
  static Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function(String token) requestFn,
  ) async {
    final token = await getToken();
    if (token == null) {
      // No token at all — try silent re-auth first
      final reauthed = await trySilentReauth();
      if (reauthed) {
        final newToken = await getToken();
        return await requestFn(newToken!);
      }
      throw Exception('Not authenticated');
    }

    try {
      final response = await requestFn(token);
      if (response.statusCode == 401 || response.statusCode == 403) {
        // Token invalid — try silent re-auth and retry once
        final reauthed = await trySilentReauth();
        if (reauthed) {
          final newToken = await getToken();
          return await requestFn(newToken!);
        }
        // Re-auth failed, throw auth error
        throw Exception(
          jsonDecode(response.body)['message'] ?? 'Authentication failed',
        );
      }
      return response;
    } on SocketException {
      rethrow;
    } on http.ClientException {
      rethrow;
    }
  }

  static Map<String, String> _headers(String? token) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Auth: Login
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers(null),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['token'] != null) {
      await saveToken(data['token']);
      await saveCredentials(email, password); // for silent re-auth
    }
    return data;
  }

  // Auth: Register (with credential saving for silent re-auth)
  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers(null),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201 && data['token'] != null) {
      await saveToken(data['token']);
      await saveCredentials(email, password); // for silent re-auth
    }
    return data;
  }

  // User Profile
  static Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/profile'),
        headers: _headers(token),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception(
        jsonDecode(response.body)['message'] ?? 'Failed to get profile',
      );
    } on SocketException {
      throw Exception('No internet connection');
    } on http.ClientException {
      throw Exception('Server unreachable');
    }
  }

  // Update Goal
  static Future<Map<String, dynamic>> updateGoal(String targetGoal) async {
    final token = await getToken();
    final response = await http.put(
      Uri.parse('$baseUrl/user/goal'),
      headers: _headers(token),
      body: jsonEncode({'targetGoal': targetGoal}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to update goal',
    );
  }

  // Update Status
  static Future<Map<String, dynamic>> updateStatus(
    String activity,
    bool isStudying,
  ) async {
    final token = await getToken();
    final response = await http.put(
      Uri.parse('$baseUrl/user/status'),
      headers: _headers(token),
      body: jsonEncode({'activity': activity, 'isStudying': isStudying}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to update status',
    );
  }

  // Generate pairing code (Student)
  static Future<Map<String, dynamic>> generatePairingCode() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/user/parent-pairing-code'),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to generate code',
    );
  }

  // Pair parent (Parent)
  static Future<Map<String, dynamic>> pairParent(String pairingCode) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/parent/pair'),
      headers: _headers(token),
      body: jsonEncode({'pairingCode': pairingCode}),
    );
    return jsonDecode(response.body);
  }

  // Get report (Parent or self)
  static Future<Map<String, dynamic>> getParentReport(String studentId) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/parent/reports/$studentId'),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to load reports',
    );
  }

  // Sync activity daily summary
  static Future<Map<String, dynamic>> syncActivity(
    String date,
    int totalStudySeconds,
    int totalDistractedSeconds, {
    List<int>? hourly,
    List<Map<String, dynamic>>? taskAnalytics,
    List<Map<String, dynamic>>? sessions,
  }) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');
    try {
      final payload = {
        'date': date,
        'totalStudySeconds': totalStudySeconds,
        'totalDistractedSeconds': totalDistractedSeconds,
      };
      if (hourly != null) payload['hourly'] = hourly;
      if (taskAnalytics != null) payload['taskAnalytics'] = taskAnalytics;
      if (sessions != null) payload['sessions'] = sessions;

      final response = await http.post(
        Uri.parse('$baseUrl/activity/sync'),
        headers: _headers(token),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception(
        jsonDecode(response.body)['message'] ?? 'Failed to sync activity',
      );
    } on SocketException {
      throw Exception('No internet connection');
    } on http.ClientException {
      throw Exception('Server unreachable');
    }
  }

  // New: Batch sync on timer events (start, pause, stop)
  static Future<Map<String, dynamic>> batchSyncActivity(
    Map<String, dynamic> payload,
  ) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/activity/batch-sync'),
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to batch sync',
    );
  }

  // New: Get comprehensive analytics for the dashboard
  // Supports offline fallback: caches last successful response in SharedPreferences.
  static const _analyticsCacheKey = 'analytics_cache_json';

  static Future<Map<String, dynamic>> getAnalytics({int daysBack = 30, String? studentId}) async {
    final token = await getToken();
    try {
      String url = '$baseUrl/analytics?days=$daysBack';
      if (studentId != null) {
        url += '&studentId=$studentId';
      }
      final response = await http
          .get(
            Uri.parse(url),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          // Cache the successful response for offline use.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_analyticsCacheKey, response.body);
          return data;
        } catch (_) {
          throw Exception(
            'Server returned invalid data. Please try again later.',
          );
        }
      }
      // Try to extract error message from JSON, fall back to status code + body preview
      try {
        final body = jsonDecode(response.body);
        throw Exception(
          body['message'] ??
              'Failed to load analytics (${response.statusCode})',
        );
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception(
          'Server error (${response.statusCode}). The analytics endpoint may be unavailable.',
        );
      }
    } on SocketException {
      return _getAnalyticsCacheFallback();
    } on http.ClientException {
      return _getAnalyticsCacheFallback();
    } on TimeoutException {
      return _getAnalyticsCacheFallback();
    }
  }

  /// Returns cached analytics data from SharedPreferences, or throws if none available.
  static Future<Map<String, dynamic>> _getAnalyticsCacheFallback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_analyticsCacheKey);
      if (cached != null && cached.isNotEmpty) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        // Tag the response so the UI can show an 'offline' indicator.
        return {...data, '_offline': true};
      }
    } catch (_) {}
    throw Exception(
      'No internet connection and no cached analytics available.',
    );
  }

  // Buddies: Add
  static Future<Map<String, dynamic>> addBuddy(String buddyEmail) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/buddies/add'),
      headers: _headers(token),
      body: jsonEncode({'buddyEmail': buddyEmail}),
    );
    return jsonDecode(response.body);
  }

  // Buddies: Status
  static Future<List<dynamic>> getBuddiesStatus() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/buddies/status'),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to get buddies status',
    );
  }

  // Groups: List
  static Future<List<dynamic>> getGroups() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/groups'),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to load groups',
    );
  }

  // Groups: Search
  static Future<List<dynamic>> searchGroups(String query) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/groups/search?query=${Uri.encodeComponent(query)}'),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to search groups',
    );
  }

  // Groups: Get Members
  static Future<List<dynamic>> getGroupMembers(String groupId) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/groups/$groupId/members'),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to get group members',
    );
  }

  // Groups: Remove Member (Eviction)
  static Future<Map<String, dynamic>> removeGroupMember(
    String targetUserId,
  ) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/groups/remove-member'),
      headers: _headers(token),
      body: jsonEncode({'targetUserId': targetUserId}),
    );
    return jsonDecode(response.body);
  }

  // Groups: Create
  static Future<Map<String, dynamic>> createGroup(
    String groupName,
    String category,
  ) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/groups/create'),
      headers: _headers(token),
      body: jsonEncode({'groupName': groupName, 'category': category}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to create group',
    );
  }

  // Groups: Join
  static Future<Map<String, dynamic>> joinGroup(String groupId) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/groups/join'),
      headers: _headers(token),
      body: jsonEncode({'groupId': groupId}),
    );
    return jsonDecode(response.body);
  }

  // Rankings
  static Future<Map<String, dynamic>> getRankings({
    String category = 'overall',
    int skip = 0,
    int limit = 10,
  }) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/rankings?category=$category&skip=$skip&limit=$limit'),
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      if (response.headers['content-type']?.contains('application/json') ?? false) {
        return jsonDecode(response.body);
      }
      throw Exception('Unexpected response format: ${response.headers['content-type']}');
    }

    String message = 'Failed to load rankings';
    if (response.headers['content-type']?.contains('application/json') ?? false) {
      try {
        message = jsonDecode(response.body)['message'] ?? message;
      } catch (_) {}
    } else {
      message = 'Server error (${response.statusCode}). Please ensure backend is running.';
    }
    throw Exception(message);
  }

  // Parent: Get Linked Students
  static Future<List<dynamic>> getLinkedStudents() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/parent/students'),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to get linked students',
    );
  }

  // AI Motivator
  static Future<String> getAIBehaviorGuide(
    int studySeconds,
    int distractedSeconds,
    String examGoal,
  ) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/ai/behavior-guide'),
        headers: _headers(token),
        body: jsonEncode({
          'studySeconds': studySeconds,
          'distractedSeconds': distractedSeconds,
          'examGoal': examGoal,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['message'] ?? '';
      }
    } catch (_) {
      return 'Keep pushing. Time is passing. Will you pass too?';
    }
    return 'Guard your time. Your future depends on it.';
  }
}
