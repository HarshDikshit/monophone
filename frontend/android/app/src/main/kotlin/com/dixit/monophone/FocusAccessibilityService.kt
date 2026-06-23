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

        if (BlockerConfig.blockedPackages.contains(packageName)) {
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
                scanForReelsShorts(packageName, event)
                return
            }

            val isLimitExceeded = UsageTracker.isLimitExceeded(packageName)
            if (isLimitExceeded) {
                triggerBlockerOverlay(packageName, "Daily usage limit exceeded")
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
            // Reset the feed session if user really navigates away.
            Log.d(TAG, "Navigation away from $packageName — resetting feed timer.")
            feedStartTime.remove(packageName)
            BlockerConfig.clearFirstReelAcknowledged(packageName)
        }
    }

    private fun checkIfInShortsFeed(packageName: String, event: AccessibilityEvent): Boolean {
        var root = rootInActiveWindow ?: event.source
        if (root != null) {
            try {
                val text = extractAllVisibleText(root).lowercase(java.util.Locale.US)
                if (packageName.contains("youtube")) {
                    if (text.contains("dislike") || text.contains("remix")) return true
                    if (text.contains("home") && text.contains("subscriptions")) return false
                }
                if (packageName.contains("instagram")) {
                    if (text.contains("reels tray container") || text.contains("original audio")) return false
                    if ((text.contains("reels") && text.contains("friends")) || text.contains("use template") || text.contains("remix this reel")) return true
                }
            } catch (_: Exception) {}
        }
        return false
    }

    private fun extractAllVisibleText(node: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        fun traverse(n: AccessibilityNodeInfo?) {
            if (n == null) return
            if (n.isVisibleToUser) {
                n.text?.toString()?.takeIf { it.isNotEmpty() }?.let { sb.append(it).append("\n") }
                n.contentDescription?.toString()?.takeIf { it.isNotEmpty() }?.let { sb.append(it).append("\n") }
            }
            for (i in 0 until n.childCount) traverse(n.getChild(i))
        }
        traverse(node)
        return sb.toString()
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