import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/launcher_state.dart';
import '../services/auth_guard.dart';
import '../widgets/social_widgets.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Navigation State for Groups Tab
  // 0: Dashboard, 1: Detail, 2: Configurator (Create/Edit)
  int _groupsTabNavIndex = 0;
  GroupModel? _selectedGroup;
  bool _isConfigEditMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToGroupDetail(GroupModel group) {
    setState(() {
      _selectedGroup = group;
      _groupsTabNavIndex = 1;
    });
  }

  void _navigateToConfigurator({GroupModel? group}) {
    setState(() {
      _selectedGroup = group;
      _isConfigEditMode = group != null;
      _groupsTabNavIndex = 2;
    });
  }

  void _backToGroupsDashboard() {
    setState(() {
      _groupsTabNavIndex = 0;
      _selectedGroup = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Monochromatic Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: MonochromaticTab(
                      text: 'Groups',
                      isSelected: _tabController.index == 0,
                      onTap: () {
                        setState(() => _tabController.index = 0);
                      },
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: MonochromaticTab(
                      text: 'Leaderboard',
                      isSelected: _tabController.index == 1,
                      onTap: () {
                        setState(() => _tabController.index = 1);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(), // Control via state
                children: [
                  _buildGroupsTabNavigator(),
                  _buildLeaderboardTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsTabNavigator() {
    switch (_groupsTabNavIndex) {
      case 1:
        return _SelectedGroupDetailScreen(
          group: _selectedGroup!,
          onBack: _backToGroupsDashboard,
          onEdit: () => _navigateToConfigurator(group: _selectedGroup),
        );
      case 2:
        return _GroupConfiguratorScreen(
          group: _selectedGroup,
          isEditMode: _isConfigEditMode,
          onBack: () {
            if (_isConfigEditMode) {
              setState(() => _groupsTabNavIndex = 1);
            } else {
              _backToGroupsDashboard();
            }
          },
        );
      case 0:
      default:
        return _GroupsDashboardScreen(
          onGroupTap: _navigateToGroupDetail,
          onCreateTap: () => _navigateToConfigurator(),
        );
    }
  }

  Widget _buildLeaderboardTab() {
    return _LeaderboardScreen();
  }
}

// ── Groups Dashboard (Screen 1) ─────────────────────────────────────────────

class _GroupsDashboardScreen extends StatefulWidget {
  final Function(GroupModel) onGroupTap;
  final VoidCallback onCreateTap;

  const _GroupsDashboardScreen({
    required this.onGroupTap,
    required this.onCreateTap,
  });

  @override
  State<_GroupsDashboardScreen> createState() => _GroupsDashboardScreenState();
}

class _GroupsDashboardScreenState extends State<_GroupsDashboardScreen> {
  // Stub data
  List<GroupModel> _myGroups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchGroups();
  }

  Future<void> _fetchGroups() async {
    setState(() => _isLoading = true);
    try {
      final groupsData = await ApiService.getGroups();
      final List<GroupModel> groups = groupsData.map((g) {
        return GroupModel(
          id: g['_id'] ?? g['id'] ?? '',
          name: g['name'] ?? 'Unnamed Group',
          description: g['description'] ?? '',
          category: g['category'] ?? 'General',
          memberCount: (g['members'] as List?)?.length ?? 0,
          lastActivitySnippet: '', // Fetch from activity if needed
          isJoined: true, // They are in this list because it's "my groups"
        );
      }).toList();

      if (mounted) {
        setState(() {
          _myGroups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching groups: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          SectionHeader(
            title: 'Your Groups',
            actionText: '+ Create Group',
            onActionTap: widget.onCreateTap,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Text(
                      'LOADING...',
                      style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  )
                : _myGroups.isEmpty
                    ? const Center(
                        child: Text(
                          'NO GROUPS JOINED',
                          style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchGroups,
                        color: Colors.white,
                        backgroundColor: Colors.black,
                        child: ListView.builder(
                          itemCount: _myGroups.length,
                          itemBuilder: (context, index) {
                            return GroupRowWidget(
                              group: _myGroups[index],
                              onTap: () => widget.onGroupTap(_myGroups[index]),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Group Detail (Screen 2) ────────────────────────────────────────────────

class _SelectedGroupDetailScreen extends StatefulWidget {
  final GroupModel group;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const _SelectedGroupDetailScreen({
    required this.group,
    required this.onBack,
    required this.onEdit,
  });

  @override
  State<_SelectedGroupDetailScreen> createState() => _SelectedGroupDetailScreenState();
}

class _SelectedGroupDetailScreenState extends State<_SelectedGroupDetailScreen> {
  List<GroupMember> _members = [];
  bool _isLoadingMembers = true;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      final membersData = await ApiService.getGroupMembers(widget.group.id);
      final List<GroupMember> members = membersData.map((m) {
        return GroupMember(
          id: m['_id'] ?? m['id'] ?? '',
          name: m['name'] ?? 'Unknown',
          focusStatus: m['isStudying'] == true ? 'Studying' : 'Idle',
          dailyFocusDuration: _formatDuration(m['todayFocusSeconds'] ?? 0),
          weeklyFocusDuration: _formatDuration(m['weeklyFocusSeconds'] ?? 0),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _members = members;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching members: $e");
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return '0m';
    final int sec = seconds is int ? seconds : int.tryParse(seconds.toString()) ?? 0;
    if (sec < 60) return '${sec}s';
    final int mins = sec ~/ 60;
    if (mins < 60) return '${mins}m';
    final int hours = mins ~/ 60;
    final int remainingMins = mins % 60;
    return '${hours}h ${remainingMins}m';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _buildInternalHeader(),
          _buildSubTabBar(),
          Expanded(
            child: TabBarView(
              children: [
                _buildMembersTab(),
                _buildActivityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInternalHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBack,
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.group.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          GestureDetector(
            onTap: widget.onEdit,
            child: const Text(
              'EDIT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabBar() {
    return const TabBar(
      indicatorColor: Colors.white,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white24,
      indicatorWeight: 1,
      dividerColor: Colors.transparent,
      tabs: [
        Tab(text: 'MEMBERS'),
        Tab(text: 'ACTIVITY'),
      ],
    );
  }

  Widget _buildMembersTab() {
    if (_isLoadingMembers) {
      return const Center(
        child: Text(
          'LOADING MEMBERS...',
          style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
        ),
      );
    }
    if (_members.isEmpty) {
      return const Center(
        child: Text(
          'NO MEMBERS FOUND',
          style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _members.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white10),
      itemBuilder: (context, index) {
        final m = _members[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.focusStatus.toUpperCase(),
                      style: TextStyle(
                        color: m.focusStatus == 'Studying' ? Colors.white : Colors.grey[700],
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'This Week: ${m.weeklyFocusDuration}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  Text(
                    'Today: ${m.dailyFocusDuration}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivityTab() {
    return const Center(
      child: Text(
        'ACTIVITY FEED COMING SOON',
        style: TextStyle(color: Colors.white24, fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }
}

// ── Group Configurator (Screen 3) ───────────────────────────────────────────

class _GroupConfiguratorScreen extends StatefulWidget {
  final GroupModel? group;
  final bool isEditMode;
  final VoidCallback onBack;

  const _GroupConfiguratorScreen({
    this.group,
    required this.isEditMode,
    required this.onBack,
  });

  @override
  State<_GroupConfiguratorScreen> createState() => _GroupConfiguratorScreenState();
}

class _GroupConfiguratorScreenState extends State<_GroupConfiguratorScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode && widget.group != null) {
      _nameController.text = widget.group!.name;
      _descController.text = widget.group!.description;
    }
  }

  Future<void> _saveGroup() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (widget.isEditMode) {
        // ApiService doesn't have updateGroup yet. For now just go back.
        widget.onBack();
      } else {
        await ApiService.createGroup(
          _nameController.text,
          'General', // Default category for now
        );
        widget.onBack();
      }
    } catch (e) {
      debugPrint("Error saving group: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: widget.onBack,
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
              Text(
                widget.isEditMode ? 'EDIT GROUP' : 'CREATE GROUP',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
              GestureDetector(
                onTap: _saveGroup,
                child: const Text(
                  'DONE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'GROUP NAME',
              labelStyle: TextStyle(color: Colors.white24, fontSize: 12, fontFamily: 'monospace'),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 24),
          if (_isSaving)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else ...[
            TextField(
              controller: _descController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'DESCRIPTION / RULES',
                labelStyle: TextStyle(color: Colors.white24, fontSize: 12, fontFamily: 'monospace'),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
          ],
          if (widget.isEditMode) ...[
            const SizedBox(height: 48),
            const SectionHeader(title: 'Members'),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: 3,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Member Name', style: TextStyle(color: Colors.white, fontFamily: 'monospace')),
                        GestureDetector(
                          onTap: () {},
                          child: const Text('REMOVE', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Leaderboard (Screens 4 & 5) ─────────────────────────────────────────────

class _LeaderboardScreen extends StatefulWidget {
  @override
  State<_LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<_LeaderboardScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedCategory = 'thisweek'; // 'thisweek' or 'overall'
  List<RankingItem> _rankings = [];
  bool _isLoading = false;
  int _page = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetchNextBatch();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoading) {
          _fetchNextBatch();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchNextBatch({bool reset = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    if (reset) {
      _page = 0;
      _rankings = [];
    }

    try {
      final skip = _rankings.length;
      final category = _selectedCategory == 'thisweek' ? 'thisweek' : 'overall';
      
      final response = await ApiService.getRankings(
        category: category,
        skip: skip,
        limit: _pageSize,
      );

      final List<dynamic> rankingData = response['rankings'] ?? [];
      final List<RankingItem> newData = rankingData.asMap().entries.map((entry) {
        final index = entry.key;
        final map = entry.value;
        return RankingItem(
          rank: skip + index + 1,
          username: map['username'] ?? map['name'] ?? 'Unknown',
          focusDuration: _formatDuration(map['totalFocusSeconds'] ?? 0),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _rankings.addAll(newData);
          _page++;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching rankings: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load rankings: $e')),
        );
      }
    }
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return '0m';
    final int sec = seconds is int ? seconds : int.tryParse(seconds.toString()) ?? 0;
    if (sec < 60) return '${sec}s';
    final int mins = sec ~/ 60;
    if (mins < 60) return '${mins}m';
    final int hours = mins ~/ 60;
    final int remainingMins = mins % 60;
    return '${hours}h ${remainingMins}m';
  }

  void _onCategoryChanged(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
    });
    _fetchNextBatch(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
          child: Row(
            children: [
              _buildCategoryToggle(
                'This Week', 
                _selectedCategory == 'thisweek',
                () => _onCategoryChanged('thisweek'),
              ),
              const SizedBox(width: 16),
              _buildCategoryToggle(
                'Overall', 
                _selectedCategory == 'overall',
                () => _onCategoryChanged('overall'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _rankings.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < _rankings.length) {
                final item = _rankings[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          '#${item.rank}',
                          style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.username,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ),
                      Text(
                        item.focusDuration,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                );
              } else {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: Center(
                    child: Text(
                      'loading...',
                      style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryToggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: active ? Colors.white : Colors.white24,
          fontSize: 11,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          letterSpacing: 1,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
