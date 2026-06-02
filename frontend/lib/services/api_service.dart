import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // The production API URL is injected at build time.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.6:5000/api',
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
  }

  static Map<String, String> _headers(String? token) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Auth: Register
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
    return jsonDecode(response.body);
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
    }
    return data;
  }

  // User Profile
  static Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
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
    int totalDistractedSeconds,
  ) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/activity/sync'),
      headers: _headers(token),
      body: jsonEncode({
        'date': date,
        'totalStudySeconds': totalStudySeconds,
        'totalDistractedSeconds': totalDistractedSeconds,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to sync activity',
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

  // Rankings: Category-based Skip/Limit paginated
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
      return jsonDecode(response.body);
    }
    throw Exception(
      jsonDecode(response.body)['message'] ?? 'Failed to load rankings',
    );
  }

  // AI Motivator Headline
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
      // Offline fallback string in case backend fails
      return 'Keep pushing. Time is passing. Will you pass too?';
    }
    return 'Guard your time. Your future depends on it.';
  }
}
