import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/launcher_state.dart';

class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});

  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  final _codeController = TextEditingController();
  bool _pairing = false;
  String _message = '';

  // Pairing state (if student)
  String _pairingCode = '';
  DateTime? _expiresAt;
  bool _generatingCode = false;

  // Linked student reports (if parent)
  List<dynamic> _reports = [];
  Map<String, dynamic>? _linkedStudentInfo;
  bool _loadingReports = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final state = Provider.of<LauncherState>(context, listen: false);
    final user = state.userProfile;
    if (user == null) return;

    if (user['role'] == 'parent') {
      // Find if student is already linked
      _fetchLinkedStudentReports();
    } else {
      // If student, check if already linked to parent
      if (user['linkedParentId'] != null) {
        setState(() {
          _message = 'Status: Linked to Parent.';
        });
      }
    }
  }

  Future<void> _fetchLinkedStudentReports() async {
    final state = Provider.of<LauncherState>(context, listen: false);
    final user = state.userProfile;
    if (user == null) return;

    // For parent role, find who is linked to us.
    // In our backend, user population has linkedParentId, but we can query parent-reports.
    // If student id is unknown, how does parent fetch?
    // In a real database, parent wants to fetch reports for their linked student.
    // Let's check the student profile. Our backend returns the profile of the logged-in user.
    // Wait, let's write a route helper on the backend or frontend:
    // If user profile has 'linkedStudent' (which we can populate) or we fetch it dynamically.
    // Let's check backend profile schema: the backend populated populate('buddies').
    // Wait, does the backend return linked student under parent profile?
    // No, but the parent can search for linked students or we can fetch a custom endpoint or query by pairing.
    // Actually, in `routes.js`:
    // `/api/parent/reports/:studentId` returns reports.
    // But how does the parent know the studentId?
    // In our api response for `pairParent`, we return the student information:
    // `{ student: { id, name, email } }`.
    // Let's store this linked student ID in the parent's device preferences!
    // Or we can query the backend for all students linked to this parent ID.
    // Let's support both. We can query `/api/user/profile` and look at the populated/linked student?
    // Wait! Let's check the user profile returned by `/api/user/profile`.
    // In `routes.js`, `profile` populated `groupId` and `buddies`, but did it populate linked student?
    // No, but parent can find linked students by making a query or we can implement a call to query students.
    // Let's check: our parent report api is `/api/parent/reports/:studentId`.
    // If the parent has paired, we can save the linkedStudentId in SharedPreferences, so we can fetch reports for that student.
    // Let's write that logic. It's clean, efficient, and robust!
    
    setState(() {
      _loadingReports = true;
      _message = '';
    });

    try {
      // Let's check if we saved student ID in device preferences
      final prefsInst = await SharedPreferences.getInstance();
      String? studentId = prefsInst.getString('linked_student_id');

      if (studentId != null) {
        final reportsData = await ApiService.getParentReport(studentId);
        setState(() {
          _reports = reportsData['activities'] ?? [];
          _linkedStudentInfo = reportsData['student'];
        });
      } else {
        setState(() {
          _message = 'No student linked. Please enter a pairing code below.';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error loading student reports: ${e.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      setState(() {
        _loadingReports = false;
      });
    }
  }

  // Student action: Generate Code
  Future<void> _generateCode() async {
    setState(() {
      _generatingCode = true;
      _message = '';
    });
    try {
      final res = await ApiService.generatePairingCode();
      setState(() {
        _pairingCode = res['pairingCode'];
        if (res['expiresAt'] != null) {
          _expiresAt = DateTime.parse(res['expiresAt']);
        }
      });
    } catch (e) {
      setState(() {
        _message = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _generatingCode = false;
      });
    }
  }

  // Parent action: Pair Code
  Future<void> _pair() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _pairing = true;
      _message = '';
    });

    try {
      final res = await ApiService.pairParent(code);
      if (res['student'] != null) {
        final studentId = res['student']['id'];
        final prefsInst = await SharedPreferences.getInstance();
        await prefsInst.setString('linked_student_id', studentId);
        
        setState(() {
          _message = 'Successfully paired with ${res['student']['name']}!';
          _codeController.clear();
        });
        
        // Refresh reports
        await _fetchLinkedStudentReports();
      } else {
        setState(() {
          _message = res['message'] ?? 'Failed to pair.';
        });
      }
    } catch (e) {
      setState(() {
        _message = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _pairing = false;
      });
    }
  }

  // Push Report via Native Share
  void _shareReport() {
    if (_reports.isEmpty) return;

    final studentName = _linkedStudentInfo?['name'] ?? 'Student';
    final goal = _linkedStudentInfo?['targetGoal'] ?? 'N/A';

    StringBuffer buffer = StringBuffer();
    buffer.writeln('📋 *FOCUS LAUNCHER SUMMARY REPORT*');
    buffer.writeln('Student: $studentName');
    buffer.writeln('Goal: $goal');
    buffer.writeln('===================================');
    buffer.writeln('| Date       | Focus (h:m) | Distracted (h:m) |');
    buffer.writeln('|------------|-------------|------------------|');

    for (var act in _reports) {
      final date = act['date'] ?? 'N/A';
      final study = _formatSeconds(act['totalStudySeconds'] ?? 0);
      final distracted = _formatSeconds(act['totalDistractedSeconds'] ?? 0);
      buffer.writeln('| $date | $study | $distracted |');
    }

    buffer.writeln('===================================');
    buffer.writeln('Generated via Focus Study Launcher.');

    Share.share(buffer.toString(), subject: 'Weekly Focus Report for $studentName');
  }

  String _formatSeconds(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final user = state.userProfile;
    final isParent = user?['role'] == 'parent';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          isParent ? 'PARENT MONITOR' : 'PARENT LINKING',
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: isParent ? _buildParentView() : _buildStudentView(state),
        ),
      ),
    );
  }

  Widget _buildStudentView(LauncherState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CONNECT A PARENT',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 18,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Allow a parent to view your focus progress. Generate a pairing code or QR code and share it with them. They will have read-only access to your daily summary activity.',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 32),
        if (_pairingCode.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Text(
                  _pairingCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'EXPIRES IN: ${_expiresAt != null ? _expiresAt!.difference(DateTime.now()).inMinutes : 15} MINS',
                  style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 24),
                // QR code rendering using qr_flutter
                QrImageView(
                  data: _pairingCode,
                  version: QrVersions.auto,
                  size: 160.0,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.white),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.white),
                  gapless: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
        const Spacer(),
        if (_message.isNotEmpty) ...[
          Text(
            _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 16),
        ],
        GestureDetector(
          onTap: _generatingCode ? null : _generateCode,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white),
            ),
            child: Center(
              child: _generatingCode
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : const Text(
                      'GENERATE PAIRING CODE',
                      style: TextStyle(
                        color: Colors.white,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParentView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_linkedStudentInfo != null) ...[
          // Report Card
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _linkedStudentInfo!['name'].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'GOAL: ${_linkedStudentInfo!['targetGoal'] ?? 'None'}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: _shareReport,
                tooltip: 'Share Markdown Matrix Report',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'DAILY SUMMARY REPORTS (LAST 30 DAYS)',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loadingReports
                ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : _reports.isEmpty
                    ? Center(
                        child: Text(
                          'No reports synced yet.',
                          style: TextStyle(color: Colors.grey[700], fontFamily: 'monospace'),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _reports.length,
                        separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final act = _reports[index];
                          final date = act['date'] ?? '';
                          final studySec = act['totalStudySeconds'] ?? 0;
                          final distractSec = act['totalDistractedSeconds'] ?? 0;
                          final streak = act['streakMaintained'] ?? false;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      date,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      streak ? '⚡ STREAK MAINTAINED' : '🛑 FOCUS TARGET MISSED',
                                      style: TextStyle(
                                        color: streak ? Colors.white38 : Colors.grey[800],
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'STUDY: ${_formatSeconds(studySec)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        Text(
                                          'DISTRACT: ${_formatSeconds(distractSec)}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              ],
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 16),
        ],

        // Pairing logic
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _linkedStudentInfo == null ? 'LINK STUDENT' : 'LINK ANOTHER STUDENT',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'ENTER 6-DIGIT CODE',
                  hintStyle: TextStyle(color: Colors.grey[700], letterSpacing: 2),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_message.isNotEmpty) ...[
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
              ],
              GestureDetector(
                onTap: _pairing ? null : _pair,
                child: Container(
                  height: 40,
                  color: Colors.white,
                  child: Center(
                    child: _pairing
                        ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                        : const Text(
                            'SUBMIT CODE',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
