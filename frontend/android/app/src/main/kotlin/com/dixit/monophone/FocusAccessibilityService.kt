package com.dixit.monophone

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Enhanced Accessibility Service for granular blocker enforcement.
 */
class FocusAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "FocusAccessibilitySvc"
        
        var instance: FocusAccessibilityService? = null
            private set

        private const val BLOCK_COOLDOWN_MS = 15_000L

        /** Increased sensitivity: Scan more frequently (200ms). */
        private const val SCAN_COOLDOWN_MS = 200L

        /** Signals used to detect a transition to the next video. */
        private val NEXT_VIDEO_SIGNAL_CLASSES = setOf(
            "androidx.viewpager.widget.ViewPager",
            "androidx.viewpager2.widget.ViewPager2",
            "android.widget.SeekBar",
            "com.google.android.apps.youtube.app.extensions.reel.common.ReelPlayerRootView",
            "android.widget.AbsListView",
            "android.widget.ListView",
            "androidx.recyclerview.widget.RecyclerView"
        )

        private const val EVENT_TYPES = (
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
            AccessibilityEvent.TYPE_VIEW_SCROLLED
        )

        private val lastBlockTime = mutableMapOf<String, Long>()
        private val lastScanTime = mutableMapOf<String, Long>()
        private val lastDetectedFeedTime = mutableMapOf<String, Long>()
        private val lastBackActionTime = mutableMapOf<String, Long>()
        /** Tracking when the user first entered a Reels/Shorts feed. */
        private val feedStartTime = mutableMapOf<String, Long>()
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        Log.i(TAG, "FocusAccessibilityService connected.")
        instance = this
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_SCROLLED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 50
        }
        this.serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return
        val eventType = event.eventType
        
        Log.v(TAG, "EVENT: ${AccessibilityEvent.eventTypeToString(eventType)} pk=$packageName class=${event.className}")
        
        if (packageName == "com.dixit.monophone") {
            lastBlockTime.clear()
        }

        val isShortsBlockActive = BlockerConfig.isShortsBlockEnabled(packageName)
        val isAppFullyBlocked = BlockerConfig.blockedPackages.contains(packageName)

        if (isShortsBlockActive || isAppFullyBlocked) {
            if (isReelsShortsPackage(packageName)) {
                if (BlockerOverlayService.isCurrentlyShowing) return

                val now = System.currentTimeMillis()
                val lastScan = lastScanTime[packageName] ?: 0L
                if (now - lastScan < SCAN_COOLDOWN_MS) return
                
                val lastBack = lastBackActionTime[packageName] ?: 0L
                if (now - lastBack < 2500L) {
                    Log.v(TAG, "Post-back cooldown for $packageName")
                    return
                }

                lastScanTime[packageName] = now
                if (isShortsBlockActive) {
                    Log.v(TAG, "Scanning for Reels/Shorts content in $packageName")
                    scanForReelsShorts(packageName, event)
                } else {
                    Log.v(TAG, "Shorts block disabled for $packageName, skipping scan.")
                }
            }

            if (isAppFullyBlocked) {
                val isLimitExceeded = UsageTracker.isLimitExceeded(packageName)
                if (isLimitExceeded) {
                    triggerBlockerOverlay(packageName, "Daily usage limit exceeded")
                }
            }
        }
    }

    override fun onInterrupt() { Log.w(TAG, "Service interrupted.") }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    private fun isReelsShortsPackage(packageName: String): Boolean {
        val pkg = packageName.lowercase(java.util.Locale.US)
        return pkg.contains("instagram") || pkg.contains("youtube") ||
                pkg.contains("tiktok") || pkg.contains("facebook") ||
                pkg.contains("shorts") || pkg.contains("reels")
    }

    private fun isVideoSwipeEvent(event: AccessibilityEvent): Boolean {
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) return true
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            val cls = event.className?.toString() ?: ""
            return NEXT_VIDEO_SIGNAL_CLASSES.any { cls.contains(it) }
        }
        return false
    }

    private fun scanForReelsShorts(packageName: String, event: AccessibilityEvent) {
        val now = System.currentTimeMillis()
        val lastBlock = lastBlockTime[packageName] ?: 0L
        if (now - lastBlock < BLOCK_COOLDOWN_MS) return

        val isInFeed = checkIfInShortsFeed(packageName, event)
        if (isInFeed) {
            lastDetectedFeedTime[packageName] = now
            if (feedStartTime[packageName] == null) {
                feedStartTime[packageName] = now
                Log.d(TAG, "User ENTERED feed for $packageName at $now")
            }
        }

        val wasRecentlyInFeed = (now - (lastDetectedFeedTime[packageName] ?: 0L)) < 5000L
        val isSwipe = isVideoSwipeEvent(event)
        val isScrollInFeed = isInFeed || (isSwipe && wasRecentlyInFeed)

        if (isScrollInFeed) {
            val allowOne = BlockerConfig.shouldAllowOneShort(packageName)
            if (allowOne) {
                // Determine if we should block the swipe.
                // Accuracy Fix: We allow the first video to exist.
                // If we've been in the feed for > 1.5s, any swipe event triggers the block.
                val sessionStartTime = feedStartTime[packageName] ?: now
                val timeInFeed = now - sessionStartTime
                
                if (isSwipe && timeInFeed > 1500L) {
                    Log.i(TAG, "Swipe detected after $timeInFeed ms in 'Allow 1' mode — BLOCKING.")
                    triggerBlockerOverlay(packageName, "Reels/Shorts blocked. Stay focused.")
                    lastBlockTime[packageName] = now
                    // Keep feedStartTime to prevent re-triggering during the block transition
                } else {
                    Log.v(TAG, "Allowing video (timeInFeed=$timeInFeed ms, isSwipe=$isSwipe)")
                }
            } else {
                Log.i(TAG, "Instant block for $packageName.")
                triggerBlockerOverlay(packageName, "Reels/Shorts blocked. Stay focused.")
                lastBlockTime[packageName] = now
            }
        } else if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            Log.d(TAG, "Navigation away from $packageName — resetting feed timer.")
            feedStartTime.remove(packageName)
            BlockerConfig.clearFirstReelAcknowledged(packageName)
        }
    }

    private fun checkIfInShortsFeed(packageName: String, event: AccessibilityEvent): Boolean {
        val root = rootInActiveWindow ?: event.source
        if (root != null) {
            try {
                val nodes = extractAllVisibleNodes(root)
                val allContent = nodes.joinToString("\n") { "${it.first} ${it.second}" }.lowercase(java.util.Locale.US)
                
                if (packageName.contains("youtube")) {
                    // Signal 1: The official YouTube Shorts player view or specific unique vertical overlay buttons.
                    // The 'dislike' button + 'remix' or 'share' in the vertical player is a very strong signal.
                    // Shorts player buttons usually have content descriptions like "dislike this video", "remix this video".
                    val hasShortsButtons = allContent.contains("dislike") && (allContent.contains("remix") || allContent.contains("comments") || allContent.contains("share"))
                    
                    // Signal 2: Check for markers of the classic Home/Subscriptions feed.
                    // Regular videos show views, time ago, and channel names on screen together.
                    val viewsCount = allContent.split("views").size - 1
                    val agoCount = allContent.split("ago").size - 1
                    
                    // If we see more than one regular video markers, we are almost certainly on a scrolling list (Home/Sub).
                    val hasRegularVideoMarkers = (viewsCount >= 1 || agoCount >= 1)
                    
                    // False positive prevention: If we see main navigation tabs and regular video markers.
                    if (hasRegularVideoMarkers && (allContent.contains("home") || allContent.contains("subscriptions"))) {
                        // Log.v(TAG, "Home/Subscriptions feed detected (views=$viewsCount, ago=$agoCount) - skipping block.")
                        return false
                    }
                    
                    // Additional check: Shorts player is usually full screen, so we won't see view counts for NEXT/PREVIOUS videos in the scan.
                    return hasShortsButtons && !hasRegularVideoMarkers
                }
                
                if (packageName.contains("instagram")) {
                    // Instagram Reels signal: 
                    // - "Reels" text at the top (usually a Tab title or header)
                    // - "Use template" or "Remix this reel"
                    val isReelsTab = allContent.contains("use template") || allContent.contains("remix this reel")
                    val isHomeFeed = allContent.contains("suggested for you") || allContent.contains("search and explore")
                    
                    if (isHomeFeed && !allContent.contains("use template")) return false
                    
                    return isReelsTab
                }
                
                if (packageName.contains("tiktok")) return true
                if (packageName.contains("facebook") && allContent.contains("reels")) return true
                
            } catch (_: Exception) {}
        }
        return false
    }

    private fun extractAllVisibleNodes(node: AccessibilityNodeInfo): List<Pair<String, String>> {
        val list = mutableListOf<Pair<String, String>>()
        fun traverse(n: AccessibilityNodeInfo?) {
            if (n == null) return
            if (n.isVisibleToUser) {
                val txt = n.text?.toString() ?: ""
                val desc = n.contentDescription?.toString() ?: ""
                if (txt.isNotEmpty() || desc.isNotEmpty()) {
                    list.add(Pair(txt, desc))
                }
            }
            for (i in 0 until n.childCount) traverse(n.getChild(i))
        }
        traverse(node)
        return list
    }

    private fun triggerBlockerOverlay(packageName: String, reason: String) {
        val intent = Intent(this, BlockerOverlayService::class.java).apply {
            putExtra("blockedPackage", packageName)
            putExtra("blockReason", reason)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startService(intent)
    }

    fun lockScreen(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        }
        return false
    }

    /**
     * Performs a DOUBLE BACK gesture with a short delay for reliability.
     */
    fun performBackAction(packageName: String): Boolean {
        Log.i(TAG, "Triggering delayed double-back for $packageName.")
        lastBackActionTime[packageName] = System.currentTimeMillis()
        performGlobalAction(GLOBAL_ACTION_BACK)
        
        mainHandler.postDelayed({
            Log.d(TAG, "Second back gesture firing now.")
            performGlobalAction(GLOBAL_ACTION_BACK)
        }, 200) // 200ms delay between backs
        
        return true
    }
}