import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/launcher_state.dart';
import '../../services/task_planner_service.dart';
import 'lego_body.dart';
import 'thought_block.dart';

class LegoUncle extends StatefulWidget {
  const LegoUncle({super.key});

  @override
  State<LegoUncle> createState() => _LegoUncleState();
}

class _LegoUncleState extends State<LegoUncle> {
  String _currentMood = 'contentment';
  String _dialogueText = '';
  bool _showDialogue = false;
  Timer? _dialogueTimer;
  
  // To track completed focus sessions and detect new ones
  int _lastCompletedFocusSessions = 0;
  
  @override
  void initState() {
    super.initState();
    // Initial check will happen on first build via Provider
  }

  @override
  void dispose() {
    _dialogueTimer?.cancel();
    super.dispose();
  }

  void _showDialogueTimed(String text, {int seconds = 5}) {
    _dialogueTimer?.cancel();
    setState(() {
      _dialogueText = text;
      _showDialogue = true;
    });
    _dialogueTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) {
        setState(() {
          _showDialogue = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<LauncherState>(context);
    final planner = state.planner;

    if (planner == null) return const SizedBox.shrink();

    // 1. Calculate Mood Logic
    _updateMoodAndTriggers(state, planner);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Dialogue Overlay
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, right: 16.0),
          child: ThoughtBlock(
            text: _dialogueText,
            isVisible: _showDialogue,
          ),
        ),
        // Lego Uncle Figure
        LegoUncleBody(
          mood: _currentMood,
          scale: 0.5, // Reduced from 0.6 to prevent overflow on dashboard
        ),
      ],
    );
  }

  void _updateMoodAndTriggers(LauncherState state, TaskPlannerService planner) {
    // A. Goal vs Planned
    final today = DateTime.now();
    final todayTasks = planner.tasksForDate(today);
    
    // Calculate total duration of focus/work/general tasks
    int totalPlannedMinutes = 0;
    for (final task in todayTasks) {
      if (task.tag != TaskTag.nonFocus) {
        totalPlannedMinutes += task.durationMinutes;
      }
    }

    // Extract hours from state.lastGoal (e.g. "7 hours")
    int goalHours = 6; // Default
    final m = RegExp(r'(\d+)\s*hours?').firstMatch(state.lastGoal);
    if (m != null) {
      goalHours = int.tryParse(m.group(1)!) ?? 6;
    }
    
    final goalMinutes = goalHours * 60;
    
    String calculatedMood = 'contentment';
    if (totalPlannedMinutes < goalMinutes) {
      calculatedMood = 'anger';
    } else {
      calculatedMood = 'contentment';
    }

    // B. Interactive Triggers
    
    // Trigger 1: Focus Session Complete
    // We check if any task's focus duration reached a milestone.
    final currentPomoCount = state.studySeconds; // Simple proxy for now if direct count isn't available
    // Actually, let's use a better way if possible.
    // In launcher_state.dart: _incrementActiveTaskPomodoro() is called.
    // We can check if any task's completedPomodoros increased.
    int totalCompletedPomos = 0;
    for (final task in planner.tasks) {
      totalCompletedPomos += (task.completedPomodoros as num).toInt();
    }

    if (totalCompletedPomos > _lastCompletedFocusSessions) {
      _lastCompletedFocusSessions = totalCompletedPomos;
      _currentMood = 'appreciation';
      _showDialogueTimed(_getRandomAppreciation());
    }

    // Trigger 2: Missed Task
    // Check if any task is ignored/missed after its scheduled end time
    bool hasMissedTask = false;
    for (final task in todayTasks) {
      if (!task.isCompleted && task.endTime.isBefore(DateTime.now())) {
        hasMissedTask = true;
        break;
      }
    }

    if (hasMissedTask && _currentMood != 'appreciation') {
      calculatedMood = 'anger';
      // Only show dialogue periodically so it's not annoying
      if (!_showDialogue && Random().nextInt(100) < 5) { // 5% chance per build if missed
         _showDialogueTimed(_getRandomScold());
      }
    }

    // Apply mood if not in a temporary "appreciation" state that is currently showing dialogue
    if (_currentMood != 'appreciation' || !_showDialogue) {
      if (_currentMood != calculatedMood) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentMood = calculatedMood);
        });
      }
    }
  }

  String _getRandomAppreciation() {
    final list = [
      "Well done. That session counts.",
      "One brick at a time, son. One brick at a time.",
      "Solid work. The structure is growing.",
      "Keeping it steady. I like that.",
    ];
    return list[Random().nextInt(list.length)];
  }

  String _getRandomScold() {
    final list = [
      "Forgetful again? I thought you said you were 'tracking'...",
      "I see that red incomplete icon. Shame.",
      "The schedule is there for a reason, you know.",
      "Another brick missed? Don't let the wall crumble.",
    ];
    return list[Random().nextInt(list.length)];
  }
}
