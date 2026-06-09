import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/launcher_state.dart';
import '../services/auth_guard.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Buddies ────────────────────────────────────────────────────────────────
  final _buddyEmailController = TextEditingController();
  List<dynamic> _buddies = [];
  bool _loadingBuddies = false;
  String _buddyError = '';

  // ── Groups ─────────────────────────────────────────────────────────────────
  final _groupNameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _groupSearchController = TextEditingController();
  List<dynamic> _groups = [];
  bool _loadingGroups = false;
  String _groupError = '';
  // search / debounce
  Timer? _groupSearchDebounce;
  bool _isGroupSearch = false; // true = showing search results

  // ── Leaderboard ────────────────────────────────────────────────────────────
  List<dynamic> _rankings = [];
  bool _loadingRankings = false;
  bool _loadingMoreRankings = false;
  bool _hasMoreRankings = true;
  String _rankingsError = '';
  String _cacheTtlInfo = '';
  String _rankCategory = 'overall'; // 'overall' | 'weekly'
  int _rankSkip = 0;
  static const int _rankLimit = 20;
  final ScrollController _rankScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_handleTabChange);
    _rankScrollCtrl.addListener(_onRankScroll);
    _checkAuthThenLoad();
  }

  Future<void> _checkAuthThenLoad() async {
    await requireAuth(
      context,
      onAuthenticated: () {
        _fetchBuddies();
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buddyEmailController.dispose();
    _groupNameController.dispose();
    _categoryController.dispose();
    _groupSearchController.dispose();
    _groupSearchDebounce?.cancel();
    _rankScrollCtrl.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    switch (_tabController.index) {
      case 0:
        _fetchBuddies();
        break;
      case 1:
        _fetchGroups();
        break;
      case 2:
        _resetAndFetchRankings();
        break;
    }
  }

  // ── Buddies logic ──────────────────────────────────────────────────────────
  Future<void> _fetchBuddies() async {
    setState(() {
      _loadingBuddies = true;
      _buddyError = '';
    });
    try {
      _buddies = await ApiService.getBuddiesStatus();
    } catch (e) {
      _buddyError = e.toString().replaceAll('Exception: ', '');
    } finally {
      setState(() => _loadingBuddies = false);
    }
  }

  Future<void> _addBuddy() async {
    final email = _buddyEmailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _loadingBuddies = true;
      _buddyError = '';
    });
    try {
      final res = await ApiService.addBuddy(email);
      if (res['buddies'] != null) {
        _buddyEmailController.clear();
        await _fetchBuddies();
        if (mounted) {
          await Provider.of<LauncherState>(
            context,
            listen: false,
          ).fetchUserProfile();
        }
      } else {
        setState(() => _buddyError = res['message'] ?? 'Failed to add buddy');
      }
    } catch (e) {
      setState(() => _buddyError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _loadingBuddies = false);
    }
  }

  // ── Groups logic ───────────────────────────────────────────────────────────
  Future<void> _fetchGroups() async {
    setState(() {
      _loadingGroups = true;
      _groupError = '';
      _isGroupSearch = false;
      _groupSearchController.clear();
    });
    try {
      _groups = await ApiService.getGroups();
    } catch (e) {
      _groupError = e.toString().replaceAll('Exception: ', '');
    } finally {
      setState(() => _loadingGroups = false);
    }
  }

  void _onGroupSearchChanged(String query) {
    _groupSearchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _fetchGroups();
      return;
    }
    _groupSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      _runGroupSearch(query.trim());
    });
  }

  Future<void> _runGroupSearch(String query) async {
    setState(() {
      _loadingGroups = true;
      _groupError = '';
      _isGroupSearch = true;
    });
    try {
      _groups = await ApiService.searchGroups(query);
    } catch (e) {
      _groupError = e.toString().replaceAll('Exception: ', '');
    } finally {
      setState(() => _loadingGroups = false);
    }
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    final cat = _categoryController.text.trim();
    if (name.isEmpty || cat.isEmpty) return;
    setState(() {
      _loadingGroups = true;
      _groupError = '';
    });
    try {
      await ApiService.createGroup(name, cat);
      _groupNameController.clear();
      _categoryController.clear();
      await _fetchGroups();
    } catch (e) {
      setState(() => _groupError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _loadingGroups = false);
    }
  }

  Future<void> _joinGroup(String groupId) async {
    setState(() {
      _loadingGroups = true;
      _groupError = '';
    });
    try {
      final res = await ApiService.joinGroup(groupId);
      if (res['group'] != null) {
        await _fetchGroups();
        if (mounted) {
          await Provider.of<LauncherState>(
            context,
            listen: false,
          ).fetchUserProfile();
        }
      } else {
        setState(() => _groupError = res['message'] ?? 'Failed to join group.');
      }
    } catch (e) {
      setState(() => _groupError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _loadingGroups = false);
    }
  }

  // Opens the members bottom-sheet for a group
  void _openGroupMembers(
    String groupId,
    String groupName,
    String? currentUserId,
    bool isAdmin,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const Border(top: BorderSide(color: Colors.white12, width: 1)),
      builder: (ctx) => _MembersSheet(
        groupId: groupId,
        groupName: groupName,
        currentUserId: currentUserId,
        isAdmin: isAdmin,
        onEvict: () {
          Navigator.pop(ctx);
          _fetchGroups();
          Provider.of<LauncherState>(context, listen: false).fetchUserProfile();
        },
      ),
    );
  }

  // ── Leaderboard logic ──────────────────────────────────────────────────────
  void _onRankScroll() {
    if (_rankScrollCtrl.position.pixels >=
            _rankScrollCtrl.position.maxScrollExtent - 120 &&
        !_loadingMoreRankings &&
        _hasMoreRankings) {
      _loadMoreRankings();
    }
  }

  Future<void> _resetAndFetchRankings() async {
    _rankSkip = 0;
    _hasMoreRankings = true;
    _rankings = [];
    setState(() {
      _loadingRankings = true;
      _rankingsError = '';
      _cacheTtlInfo = '';
    });
    try {
      final data = await ApiService.getRankings(
        category: _rankCategory,
        skip: 0,
        limit: _rankLimit,
      );
      final list = (data['rankings'] ?? []) as List;
      _rankings = list;
      _rankSkip = list.length;
      _hasMoreRankings = list.length >= _rankLimit;
      final ttlSec = ((data['ttl'] ?? 900000) as int) ~/ 1000;
      final mins = ttlSec ~/ 60;
      _cacheTtlInfo = (data['cached'] == true)
          ? 'Cached — refreshes in $mins min'
          : 'Live query computed';
    } catch (e) {
      _rankingsError = e.toString().replaceAll('Exception: ', '');
    } finally {
      setState(() => _loadingRankings = false);
    }
  }

  Future<void> _loadMoreRankings() async {
    setState(() => _loadingMoreRankings = true);
    try {
      final data = await ApiService.getRankings(
        category: _rankCategory,
        skip: _rankSkip,
        limit: _rankLimit,
      );
      final list = (data['rankings'] ?? []) as List;
      setState(() {
        _rankings.addAll(list);
        _rankSkip += list.length;
        _hasMoreRankings = list.length >= _rankLimit;
      });
    } catch (_) {
    } finally {
      setState(() => _loadingMoreRankings = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final user = state.userProfile;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'SOCIAL LOOP',
          style: TextStyle(
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            letterSpacing: 1,
          ),
          tabs: const [
            Tab(text: 'BUDDIES'),
            Tab(text: 'GROUPS'),
            Tab(text: 'LEADERBOARD'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildBuddiesTab(user),
            _buildGroupsTab(user),
            _buildLeaderboardTab(user),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────── BUDDIES TAB ──────────────────────────────
  Widget _buildBuddiesTab(Map<String, dynamic>? user) {
    final count = (user?['buddies'] as List?)?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MY BUDDIES ($count/5)',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white30,
                  size: 20,
                ),
                onPressed: _fetchBuddies,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loadingBuddies
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 1.5,
                    ),
                  )
                : _buddies.isEmpty
                ? Center(
                    child: Text(
                      'No buddies linked yet. Max 5.',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _buddies.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (_, i) {
                      final b = _buddies[i];
                      final name = b['name'] ?? 'Buddy';
                      final status = b['currentStatus'] ?? {};
                      final activity = status['activity'] ?? 'Idle';
                      final isStudying = status['isStudying'] ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.toString().toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isStudying ? '⚡ STUDYING' : '🛑 IDLE',
                                  style: TextStyle(
                                    color: isStudying
                                        ? Colors.white
                                        : Colors.grey[700],
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isStudying
                                      ? Colors.white24
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                activity.toString().toUpperCase(),
                                style: TextStyle(
                                  color: isStudying
                                      ? Colors.white
                                      : Colors.grey[600],
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_buddyError.isNotEmpty) ...[
            Text(
              _buddyError,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (count < 5) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _buddyEmailController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'ADD BUDDY BY EMAIL',
                      hintStyle: TextStyle(
                        color: Colors.grey[800],
                        letterSpacing: 1.5,
                        fontSize: 12,
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _addBuddy,
                    child: Container(
                      height: 36,
                      color: Colors.white,
                      child: const Center(
                        child: Text(
                          'ADD BUDDY',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────── GROUPS TAB ───────────────────────────────
  Widget _buildGroupsTab(Map<String, dynamic>? user) {
    final currentGroupId = user?['groupId']?['_id'] ?? user?['groupId'];
    final currentUserId = user?['_id']?.toString();
    final creatorId = user?['groupId']?['creatorId']?.toString();
    final isAdmin =
        currentUserId != null &&
        creatorId != null &&
        currentUserId == creatorId;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ACCOUNTABILITY ROOMS',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white30,
                  size: 20,
                ),
                onPressed: _fetchGroups,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Search bar ──
          TextField(
            controller: _groupSearchController,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'SEARCH ROOMS…',
              hintStyle: TextStyle(
                color: Colors.grey[800],
                letterSpacing: 1.5,
                fontSize: 11,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: Colors.white24,
                size: 18,
              ),
              suffixIcon: _groupSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white24,
                        size: 16,
                      ),
                      onPressed: () {
                        _groupSearchController.clear();
                        _fetchGroups();
                      },
                    )
                  : null,
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white12),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white38),
              ),
            ),
            onChanged: _onGroupSearchChanged,
          ),
          const SizedBox(height: 16),

          // ── Groups list ──
          Expanded(
            child: _loadingGroups
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 1.5,
                    ),
                  )
                : _groups.isEmpty
                ? Center(
                    child: Text(
                      _isGroupSearch
                          ? 'No rooms match your search.'
                          : 'No public focus rooms available.',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _groups.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (_, i) {
                      final gp = _groups[i];
                      final id = gp['_id']?.toString() ?? '';
                      final name = gp['groupName'] ?? 'Focus Crew';
                      final cat = gp['category'] ?? 'General';
                      final members = gp['memberCount'] ?? 0;
                      final isJoined = currentGroupId?.toString() == id;

                      return GestureDetector(
                        onTap: isJoined
                            ? () => _openGroupMembers(
                                id,
                                name.toString(),
                                currentUserId,
                                isAdmin,
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          name.toString().toUpperCase(),
                                          style: TextStyle(
                                            color: isJoined
                                                ? Colors.white
                                                : Colors.grey[400],
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (isJoined) ...[
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.people_outline,
                                            color: Colors.white24,
                                            size: 14,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${cat.toString().toUpperCase()}  ·  $members/50',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              isJoined
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white54,
                                        ),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                        ),
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: members >= 50
                                          ? null
                                          : () => _joinGroup(id),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                          horizontal: 12,
                                        ),
                                        color: members >= 50
                                            ? Colors.transparent
                                            : Colors.white,
                                        child: Text(
                                          members >= 50 ? 'FULL' : 'JOIN',
                                          style: TextStyle(
                                            color: members >= 50
                                                ? Colors.grey[700]
                                                : Colors.black,
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (_groupError.isNotEmpty) ...[
            Text(
              _groupError,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Create room ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _groupNameController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    hintText: 'ROOM NAME',
                    hintStyle: TextStyle(
                      color: Colors.grey[800],
                      letterSpacing: 1.5,
                      fontSize: 11,
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _categoryController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    hintText: 'CATEGORY (e.g. UPSC, GATE)',
                    hintStyle: TextStyle(
                      color: Colors.grey[800],
                      letterSpacing: 1.5,
                      fontSize: 11,
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _createGroup,
                  child: Container(
                    height: 36,
                    color: Colors.white,
                    child: const Center(
                      child: Text(
                        'CREATE ROOM',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────── LEADERBOARD TAB ─────────────────────────────
  Widget _buildLeaderboardTab(Map<String, dynamic>? user) {
    final myId = user?['_id']?.toString();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Category toggle ──
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_rankCategory != 'overall') {
                      setState(() => _rankCategory = 'overall');
                      _resetAndFetchRankings();
                    }
                  },
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: _rankCategory == 'overall'
                          ? Colors.white
                          : Colors.transparent,
                      border: Border.all(
                        color: _rankCategory == 'overall'
                            ? Colors.white
                            : Colors.white12,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'OVERALL',
                        style: TextStyle(
                          color: _rankCategory == 'overall'
                              ? Colors.black
                              : Colors.grey[600],
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_rankCategory != 'weekly') {
                      setState(() => _rankCategory = 'weekly');
                      _resetAndFetchRankings();
                    }
                  },
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: _rankCategory == 'weekly'
                          ? Colors.white
                          : Colors.transparent,
                      border: Border.all(
                        color: _rankCategory == 'weekly'
                            ? Colors.white
                            : Colors.white12,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'THIS WEEK',
                        style: TextStyle(
                          color: _rankCategory == 'weekly'
                              ? Colors.black
                              : Colors.grey[600],
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white30,
                  size: 20,
                ),
                onPressed: _resetAndFetchRankings,
              ),
            ],
          ),
          if (_cacheTtlInfo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _cacheTtlInfo,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 12),

          // ── Rankings list ──
          Expanded(
            child: _loadingRankings
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 1.5,
                    ),
                  )
                : _rankingsError.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _rankingsError,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _resetAndFetchRankings,
                          child: const Text(
                            'RETRY',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              letterSpacing: 1.5,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : _rankings.isEmpty
                ? Center(
                    child: Text(
                      'No rankings yet.',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _rankScrollCtrl,
                    itemCount:
                        _rankings.length +
                        (_loadingMoreRankings ? 1 : 0) +
                        (!_hasMoreRankings && _rankings.isNotEmpty ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (_, index) {
                      if (index == _rankings.length) {
                        return _loadingMoreRankings
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 1.5,
                                  ),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    '— END OF LIST —',
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              );
                      }

                      final item = _rankings[index];
                      final rank = index + 1;
                      final name = item['name'] ?? 'User';
                      final goal = item['targetGoal'] ?? '';
                      final score = item['globalScore'] ?? 0;
                      final itemId = item['_id']?.toString();
                      final isMe = itemId != null && itemId == myId;

                      final rankColor = rank == 1
                          ? const Color(0xFFFFD700)
                          : rank == 2
                          ? const Color(0xFFC0C0C0)
                          : rank == 3
                          ? const Color(0xFFCD7F32)
                          : (isMe ? Colors.white : Colors.grey[800]!);

                      return Container(
                        color: isMe
                            ? Colors.white.withOpacity(0.04)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 38,
                                  child: Text(
                                    '#${rank.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      color: rankColor,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          name.toString().toUpperCase(),
                                          style: TextStyle(
                                            color: isMe
                                                ? Colors.white
                                                : Colors.grey[300],
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                            fontWeight: isMe
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 6),
                                          const Text(
                                            'YOU',
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontFamily: 'monospace',
                                              fontSize: 9,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (goal.toString().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        goal.toString().toUpperCase(),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 9,
                                          fontFamily: 'monospace',
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            Text(
                              'PTS: $score',
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.grey[600],
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: isMe
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── MEMBERS BOTTOM SHEET ────────────────────────────
class _MembersSheet extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? currentUserId;
  final bool isAdmin;
  final VoidCallback? onEvict;

  const _MembersSheet({
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
    required this.isAdmin,
    this.onEvict,
  });

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  List<dynamic> _members = [];
  bool _loading = true;
  String _error = '';
  String? _evictingId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      _members = await ApiService.getGroupMembers(widget.groupId);
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _evict(String targetUserId, String name) async {
    setState(() => _evictingId = targetUserId);
    try {
      final res = await ApiService.removeGroupMember(targetUserId);
      if (res['message'] != null) {
        setState(
          () =>
              _members.removeWhere((m) => m['_id']?.toString() == targetUserId),
        );
        widget.onEvict?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black,
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      }
    } finally {
      setState(() => _evictingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 36, height: 2, color: Colors.white24),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'MEMBERS RANKED BY FOCUS',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontFamily: 'monospace',
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                if (widget.isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'ADMIN',
                      style: TextStyle(
                        color: Colors.white54,
                        fontFamily: 'monospace',
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    )
                  : _error.isNotEmpty
                  ? Center(
                      child: Text(
                        _error,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : _members.isEmpty
                  ? Center(
                      child: Text(
                        'No members found.',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: _members.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white10),
                      itemBuilder: (_, i) {
                        final m = _members[i];
                        final memberId = m['_id']?.toString() ?? '';
                        final name = m['name'] ?? 'Member';
                        final score = m['globalScore'] ?? 0;
                        final rank = i + 1;
                        final isMe = memberId == widget.currentUserId;
                        final isEvicting = _evictingId == memberId;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '#$rank',
                                    style: TextStyle(
                                      color: rank <= 3
                                          ? Colors.white
                                          : Colors.grey[700],
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.toString().toUpperCase(),
                                        style: TextStyle(
                                          color: isMe
                                              ? Colors.white
                                              : Colors.grey[400],
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          fontWeight: isMe
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      Text(
                                        'PTS: $score',
                                        style: const TextStyle(
                                          color: Colors.white24,
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              // Admin evict button
                              if (widget.isAdmin && !isMe)
                                GestureDetector(
                                  onTap: isEvicting
                                      ? null
                                      : () => _evict(memberId, name.toString()),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.red.withOpacity(0.4),
                                      ),
                                    ),
                                    child: isEvicting
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              color: Colors.red,
                                              strokeWidth: 1.5,
                                            ),
                                          )
                                        : const Text(
                                            'EVICT',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontFamily: 'monospace',
                                              fontSize: 10,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
