# 🚀 Release v2.0.0+3 — Monophone

**Release Date:** June 10, 2026  
**Previous Release:** v1.0.2  
**Build:** `2c39389` → `main`

---

## 🎯 What's New

### 📅 Day Planner — Full Task Scheduling System
Plan your entire day with time-blocked tasks on a visual timeline.

- **24-Hour Timeline View** — Scroll through your day with color-coded task blocks positioned by time, with a live red "now" indicator
- **Month Calendar View** — See your upcoming schedule at a glance with task dots on each day
- **Task Tags** — Categorize tasks as FOCUS (white), WORK (blue), GENERAL (green), or NON-FOCUS (red)
- **Time-Block Scheduling** — Set precise start times and durations for each task
- **Pomodoro Tracking** — Estimate pomodoros per task and track completion counts
- **Weekly Recurrence** — Set tasks to repeat on specific days of the week
- **5-Minute Reminders** — Get notified before each task starts via system notifications
- **Swipe between days** — Navigate to any date with arrow controls or month view tap

### 🧩 Widget Panel — Swipe-Left Customizable Dashboard
Swipe left on the home screen to reveal a powerful widget panel.

- **Clock Widget** — Minimalist time display
- **Analytics Widget** — Quick glance at today's focus stats
- **Scratchpad Widget** — Jot down quick notes and thoughts
- **App Widget Support** — Embed native Android system widgets (weather, calendar, music, etc.)
- **Add / Remove / Reorder** — Fully customizable widget layout
- **Persistent State** — Your widget arrangement survives app restarts

### 🔒 Deep-Focus Blocker System Overhaul
A complete rebuild of the distraction-blocking engine.

- **App Blocking** — Block unproductive apps with customizable block rules
- **Reels/Shorts Block** — One-tap blocking of Instagram Reels, YouTube Shorts, TikTok, Facebook Reels
- **Daily Time Limits** — Set per-app daily time quotas with automatic lockout
- **Emergency Use** — Limited emergency bypasses with configurable max counts
- **Strict Mode** — Hard lock with no bypass option for maximum discipline
- **VPN Content Filter** — System-level content filtering integration
- **Monochrome Mode** — Grayscale overlay to reduce screen appeal
- **Friction Gate** — Breath countdown before opening distraction apps
- **Notification Silencing** — Mute distracting notifications during focus

### 🧘 Pomodoro Timer Overhaul
- **Dual Timer Modes** — Choose between countdown (default) and countup modes
- **Customizable Duration** — Set any focus duration (5-120 minutes)
- **Full-screen Mode** — Immersive timer with no distractions
- **Auto Block** — Distraction apps locked automatically during focus sessions
- **Per-Session Task Tracking** — Attribute focus time to specific study tasks
- **Task Switching** — Switch between active tasks mid-pomodoro without losing time

### 📊 Enhanced Analytics & Social
- **Today / Weekly / Monthly Views** — Detailed focus time breakdown with bar charts
- **Social Loop** — Study with friends; share your focus status and see theirs
- **Parent Dashboard** — Parents can monitor study progress remotely
- **AI Behavior Guide** — Smart suggestions based on your focus patterns
- **Goal Tracking** — Set a "North Star" goal and track progress toward it

### ⚡ Launcher UX Improvements
- **Permissions Dialog** — Guided setup for all required permissions
- **Double-Tap Actions** — Double-tap to lock screen or open app drawer
- **Quick Action Bar** — One-tap access to Plan Day, Pomodoro, Social, Parents, Blocker, Analytics, and Settings
- **App Classification** — Long-press any app to mark as Study or Distraction
- **Search Bar** — Instant filter through your study apps

---

## 🐛 Bug Fixes

- **Focus Time Bleeding** — Fixed critical bug where focus time tracked on one day would carry over to the next day when crossing midnight. Elapsed time now correctly attributes to the day it was spent on.
- **Pomodoro State Recovery** — Timer state now correctly restores from native Android service on app restart
- **Weekly Data Accuracy** — Fixed date-keyed storage to ensure weekly charts show correct per-day values

---

## 🔧 Under the Hood

- **New:** `TaskPlannerService` — Full task planner service with persistence, recurrence, and reminder scheduling
- **New:** `WidgetPanelService` — Widget management with add/remove/reorder capabilities
- **New:** `AppWidgetHostService` — Native Android service for hosting system widgets
- **New:** `BlockerConfig` — Kotlin-native blocker configuration with per-app limits and emergency bypasses
- **New:** `DailyUsageMonitorService` — Real-time app usage tracking with daily limits
- **Improved:** `LauncherState` — Enhanced with cross-day time tracking, pomodoro state management, and task engine
- **Improved:** Backend API — Added social features, parent monitoring, and AI behavior guide endpoints
- **Improved:** Android Manifest — Added permissions for notifications, accessibility, overlay, and usage stats

---

## 📱 Requirements

- Android 7.0+ (API 24)
- Usage Access Permission (for app tracking)
- Notification Permission (for reminders)
- Overlay Permission (for blocker overlays)
- Accessibility Service (optional, for screen lock)

---

## 📦 Installation

Download the APK from the [Releases page](https://github.com/HarshDikshit/monophone/releases) and install on your Android device.

---

## 🙏 Acknowledgments

Built with ❤️ using Flutter + Kotlin  
Focus on what matters. Block what doesn't.