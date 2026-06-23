import 'package:flutter/material.dart';

// ── Models ──────────────────────────────────────────────────────────────────

class GroupModel {
  final String id;
  final String name;
  final String description;
  final String category;
  final int memberCount;
  final String lastActivitySnippet;
  final bool isJoined;
  final List<GroupMember> members;

  GroupModel({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.memberCount,
    this.lastActivitySnippet = '',
    this.isJoined = false,
    this.members = const [],
  });
}

class GroupMember {
  final String id;
  final String name;
  final String focusStatus; // e.g., "Studying", "Idle"
  final String dailyFocusDuration;
  final String weeklyFocusDuration;
  final String? profileImageUrl;

  GroupMember({
    required this.id,
    required this.name,
    this.focusStatus = 'Idle',
    this.dailyFocusDuration = '0m',
    this.weeklyFocusDuration = '0m',
    this.profileImageUrl,
  });
}

class RankingItem {
  final int rank;
  final String username;
  final String focusDuration;
  final String? profileImageUrl;

  RankingItem({
    required this.rank,
    required this.username,
    required this.focusDuration,
    this.profileImageUrl,
  });
}

// ── Widgets ─────────────────────────────────────────────────────────────────

class MonochromaticTab extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const MonochromaticTab({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          text.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontFamily: 'monospace',
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1.5,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class GroupRowWidget extends StatelessWidget {
  final GroupModel group;
  final VoidCallback onTap;

  const GroupRowWidget({
    super.key,
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Row(
          children: [
            // Placeholder for icon/image if needed, but keeping it text-first
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (group.lastActivitySnippet.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      group.lastActivitySnippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '• ${group.memberCount} members',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onActionTap;
  final String? actionText;

  const SectionHeader({
    super.key,
    required this.title,
    this.onActionTap,
    this.actionText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontFamily: 'monospace',
          ),
        ),
        if (onActionTap != null && actionText != null)
          GestureDetector(
            onTap: onActionTap,
            child: Text(
              actionText!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
                decoration: TextDecoration.underline,
              ),
            ),
          ),
      ],
    );
  }
}
