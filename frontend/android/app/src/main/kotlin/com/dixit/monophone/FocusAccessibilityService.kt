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

    private fun hasReelPlayerClass(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        val className = node.className?.toString() ?: ""
        if (className.contains("ReelPlayer", ignoreCase = true) || 
            className.contains("ReelWatch", ignoreCase = true) ||
            className.contains("reel.common", ignoreCase = true) ||
            className.contains("ShortsPlayer", ignoreCase = true) ||
            className.contains(".shorts.", ignoreCase = true) ||
            className.contains("ShortsLayout", ignoreCase = true)) {
            return true
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                if (hasReelPlayerClass(child)) {
                    return true
                }
            }
        }
        return false
    }

    private fun isShortsTabSelected(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""
        val className = node.className?.toString() ?: ""
        
        // Check 1: Strict match — text/description is exactly "Shorts" and selected
        val isStrictShorts = text.equals("shorts", ignoreCase = true) || desc.equals("shorts", ignoreCase = true)
        if (isStrictShorts && node.isSelected) {
            return true
        }
        
        // Check 2: Content description or text contains "shorts" (handles localized variants like "Shorts" in nav bar)
        val isShortsText = text.contains("shorts", ignoreCase = true) || desc.contains("shorts", ignoreCase = true)
        if (isShortsText && node.isSelected) {
            return true
        }
        
        // Check 3: This node is in a bottom navigation bar and a child with "shorts" text is selected
        val isBottomNav = className.contains("BottomNavigation", ignoreCase = true) ||
                          className.contains("TabBar", ignoreCase = true) ||
                          className.contains("TabLayout", ignoreCase = true) ||
                          (text.isEmpty() && desc.isEmpty() && node.childCount > 0)
        
        // Check 4: Package resource ID based detection for the Shorts tab
        val viewId = try { node.viewIdResourceName?.toString() ?: "" } catch (_: Exception) { "" }
        val isShortsTabResource = viewId.contains("shorts", ignoreCase = true) && 
                                  (viewId.contains("tab", ignoreCase = true) || node.isSelected)
        
        if (isShortsTabResource) {
            return true
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                if (isShortsTabSelected(child)) {
                    return true
                }
            }
        }
        return false
    }

    private fun checkIfInShortsFeed(packageName: String, event: AccessibilityEvent): Boolean {
        val root = rootInActiveWindow ?: event.source
        if (root != null) {
            try {
                val nodes = extractAllVisibleNodes(root)
                val allContent = nodes.joinToString("\n") { "${it.first} ${it.second}" }.lowercase(java.util.Locale.US)
                
                if (packageName.contains("youtube")) {
                    // Check if Shorts Tab is active or Reel Player class is present
                    val isShortsTabActive = isShortsTabSelected(root)
                    val hasReelActive = hasReelPlayerClass(root)
                    
                    // Signal 1: The official YouTube Shorts player view or specific unique vertical overlay buttons.
                    // The 'dislike' button + 'remix' or 'share' in the vertical player is a very strong signal.
                    // Shorts player buttons usually have content descriptions like "dislike this video", "remix this video".
                    val hasShortsButtons = allContent.contains("dislike") && (allContent.contains("remix") || allContent.contains("comments") || allContent.contains("share"))
                    
                    // Signal 1b: The Shorts player has a unique vertical button layout on the right side.
                    // In the Shorts feed, action buttons (like, comment, share, remix) appear vertically stacked.
                    // This is distinguishable from horizontal button layouts in regular videos.
                    val hasVerticalActions = allContent.contains("like") && 
                                             allContent.contains("comment") && 
                                             allContent.contains("share") &&
                                             !allContent.contains("rotate")  // Exclude fullscreen rotation hints
                    
                    // Signal 2: Shorts player often shows "@channelname" in a distinct format
                    val hasAtMention = allContent.contains("@") && 
                                       allContent.contains("subscribe")
                    
                    // Signal 3: The Shorts player shows a "Shorts" header or title bar
                    val hasShortsHeader = allContent.contains("shorts") && 
                                          (allContent.contains("swipe") || allContent.contains("up"))
                    
                    // Combined strong Shorts signals
                    val hasStrongShortsSignals = isShortsTabActive || 
                                                  hasReelActive || 
                                                  (hasShortsButtons && hasVerticalActions) ||
                                                  (hasAtMention && hasVerticalActions) ||
                                                  hasShortsHeader
                    
                    if (hasStrongShortsSignals) {
                        return true
                    }
                    
                    // Signal 4: Check for markers of the classic Home/Subscriptions feed.
                    // Regular videos show views, time ago, and channel names on screen together.
                    val viewsCount = allContent.split("views").size - 1
                    val agoCount = allContent.split("ago").size - 1
                    
                    // If we see more than one regular video markers, we are almost certainly on a scrolling list (Home/Sub).
                    // We raise the threshold to 2 to prevent a single regular video reference in background from triggering false negatives
                    val hasRegularVideoMarkers = (viewsCount >= 2 || agoCount >= 2)
                    
                    // False positive prevention: If we see main navigation tabs and regular video markers.
                    if (hasRegularVideoMarkers && (allContent.contains("home") || allContent.contains("subscriptions"))) {
                        // Log.v(TAG, "Home/Subscriptions feed detected (views=$viewsCount, ago=$agoCount) - skipping block.")
                        return false
                    }
                    
                    // Fallback: If no strong Shorts signals AND no regular video markers,
                    // check if hasShortsButtons alone is a sufficient signal (without regular video markers)
                    if (hasShortsButtons && !hasRegularVideoMarkers) {
                        return true
                    }
                    
                    // Final fallback: If we have vertical actions AND no regular video markers,
                    // this is likely a Shorts feed (regular feed has horizontal layout)
                    return hasVerticalActions && !hasRegularVideoMarkers
                }
                
                if (packageName.contains("instagram")) {
                    // Instagram Reels signal: 
                    // - "Reels" or "Friends" headers at the top
                    // - "Use template", "Remix this reel", or "Original audio"
                    // - Vertical interaction bar (Like, Comment, Share icons without horizontal spacing of the feed)
                    val isReelicSignal = allContent.contains("use template") || 
                                        allContent.contains("remix this reel") || 
                                        allContent.contains("audio") || // "Original audio" is very common
                                        allContent.startsWith("reels") // The header
                    
                    // Home feed often has "Follow" or specific feed headers.
                    val isHomeFeedMarker = allContent.contains("suggested for you") || 
                                         allContent.contains("search and explore") ||
                                         allContent.contains("camera")
                    
                    // If we clearly see a Reels tab header/signal, it's a Reel.
                    // Image 4/5 show "Reels   Friends" at the top.
                    val isInReelsTab = allContent.contains("reels") && (allContent.contains("friends") || allContent.contains("follow")) && 
                                      (allContent.contains("audio") || allContent.contains("template"))
                    
                    if (isHomeFeedMarker && !isInReelsTab) return false
                    
                    return isReelicSignal || isInReelsTab
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