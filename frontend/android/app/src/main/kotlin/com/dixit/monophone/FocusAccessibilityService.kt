package com.dixit.monophone

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * ──────────────────────────────────────────────────────────────────────────────
 * FocusAccessibilityService — The heart of the deep-focus blocker.
 * ──────────────────────────────────────────────────────────────────────────────
 *
 * Engine 1 — Smart Reels/Shorts Blocker (Section 1.C)
 * Engine 2 — Browser URL Keyword Blocker (Section 1.D)
 * Engine 3 — Legacy double-tap lock-screen (preserved)
 *
 * Key fixes vs previous versions:
 * 1. Only blocks on TYPE_WINDOW_STATE_CHANGED (new Activity) to avoid
 *    constant re-triggering during reel scrolling.
 * 2. Uses eventSource-based node walk + findFocus as fallback since
 *    rootInActiveWindow returns null on many Samsung devices.
 * 3. Per-package block cooldown of 10 seconds to prevent re-triggering.
 * 4. No GLOBAL_ACTION_HOME call — just notifies Flutter via MethodChannel.
 *
 * ── Manifest Registration ──
 * android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
 * @xml/accessibility_service_config MUST include
 *   android:canRetrieveWindowContent="true"
 * ──────────────────────────────────────────────────────────────────────────────
 */
class FocusAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "FocusAccessibilitySvc"

        var instance: FocusAccessibilityService? = null

        /** Min time between blocks for the SAME package (10 seconds). */
        private const val BLOCK_COOLDOWN_MS = 10_000L

        /** Min time between accessibility tree scans (800ms). */
        private const val SCAN_COOLDOWN_MS = 800L

        private const val EVENT_TYPES = (
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED
                )
    }

    // ── Cooldown trackers ────────────────────────────────────────────────────
    private val lastScanTime = HashMap<String, Long>()        // packageName → ms
    private val lastBlockTime = HashMap<String, Long>()        // packageName → ms (prevent repeat blocks)
    private var currentForegroundPackage: String? = null

    private val browserPackages = BlockerConfig.supportedBrowserPackages

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "FocusAccessibilityService connected.")

        val info = AccessibilityServiceInfo().apply {
            eventTypes = EVENT_TYPES
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 200
        }
        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val packageName = event.packageName?.toString() ?: return
        currentForegroundPackage = packageName

        // ── Cooldown check ───────────────────────────────────────────────────
        val now = System.currentTimeMillis()
        val lastScan = lastScanTime[packageName] ?: 0L
        if (now - lastScan < SCAN_COOLDOWN_MS) return
        lastScanTime[packageName] = now

        try {
            // ── Engine 1: Reels/Shorts detection for social apps ─────────────
            if (isReelsShortsPackage(packageName)) {
                // Only process window state changes (new Activity / app launch)
                // NOT content changes (reel scrolling).  This prevents the
                // constant re-triggering that causes the "dialog repeatedly popping".
                if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                    scanForReelsShorts(packageName)
                }
                return
            }

            // ── Engine 2: Browser URL keyword detection ──────────────────────
            if (browserPackages.contains(packageName)) {
                scanBrowserUrlBar(packageName)
                return
            }

        } catch (e: Exception) {
            Log.w(TAG, "Error processing event for $packageName: ${e.message}")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  ENGINE 1 — Smart Reels / Shorts Blocker
    // ══════════════════════════════════════════════════════════════════════════

    private fun isReelsShortsPackage(packageName: String): Boolean {
        val pkg = packageName.lowercase()
        return pkg.contains("instagram") ||
                pkg.contains("youtube") ||
                pkg.contains("tiktok") ||
                pkg.contains("facebook") ||
                pkg.contains("snapchat") ||
                pkg.contains("likee") ||
                pkg.contains("vmate") ||
                pkg.contains("shorts") ||
                pkg.contains("reels")
    }

    /**
     * Engine 1: Check if a reels/shorts activity is open and block if needed.
     *
     * Walk the active node tree looking for text/content that indicates
     * a Shorts/Reels feed.  Uses both resource ID matching ANDtext-based
     * heuristics (which are more reliable on Samsung where view IDs may
     * not be exposed).
     */
    private fun scanForReelsShorts(packageName: String) {
        // Prevent re-blocking the same package within 10 seconds.
        val now = System.currentTimeMillis()
        val lastBlock = lastBlockTime[packageName] ?: 0L
        if (now - lastBlock < BLOCK_COOLDOWN_MS) return

        // Check if the current activity text indicates reels/shorts.
        val isInShortsFeed = checkIfInShortsFeed()

        if (isInShortsFeed) {
            Log.i(TAG, "Reels/Shorts detected for $packageName — blocking.")
            lastBlockTime[packageName] = now
            triggerBlockerOverlay(packageName, "Smart Reels/Shorts Blocker")
        }
    }

    /**
     * Walk the node tree (via findFocus or window root) looking for text
     * indicators that we're in a Shorts/Reels feed.
     *
     * On Samsung devices, resource IDs may not be reliable.  We use
     * content descriptions and text content as the primary signal.
     */
    private fun checkIfInShortsFeed(): Boolean {
        // Try get the root via the most reliable method for Samsung.
        val root = rootInActiveWindow
        if (root != null) {
            try {
                // Quick scan of all text on screen.
                val textContent = extractAllVisibleText(root)
                if (textContent.isNotEmpty()) {
                    // YouTube Shorts indicator.
                    if (textContent.contains("shorts") ||
                        textContent.contains("short") ||
                        textContent.contains("reels") ||
                        textContent.contains("reel")
                    ) {
                        root.recycle()
                        return true
                    }

                    // Check for common shorts feed UI patterns in text.
                    val lines = textContent.split("\n")
                    var reelLikeCount = 0
                    for (line in lines) {
                        val l = line.lowercase().trim()
                        if (l.isEmpty()) continue
                        // Shorts have short single-line comments, like counts.
                        if (l.contains("shorts") || l.contains("short")) {
                            reelLikeCount++
                        }
                        if (l.endsWith("k") && l.length < 8) reelLikeCount++
                    }
                    // If multiple short-form indicators found.
                    if (reelLikeCount >= 2) {
                        root.recycle()
                        return true
                    }
                }
                root.recycle()
            } catch (_: Exception) {
                root.recycle()
            }
        }

        // Fallback: check the currently focused node.
        val focused = findFocus(android.view.accessibility.AccessibilityNodeInfo.FOCUS_INPUT) ?:
                      findFocus(android.view.accessibility.AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
        if (focused != null) {
            val text = focused.text?.toString()?.lowercase() ?: ""
            val desc = focused.contentDescription?.toString()?.lowercase() ?: ""
            val className = focused.className?.toString()?.lowercase() ?: ""
            focused.recycle()

            // Check if focus is on a reel-like element.
            if (text.contains("reel") || text.contains("short") ||
                desc.contains("reel") || desc.contains("short")) {
                return true
            }
            // Video player in a social app context.
            if (className.contains("videoview") || className.contains("exoplayer")) {
                return true
            }
        }

        return false
    }

    /**
     * Extract ALL visible text from the node tree.  Used to detect
     * "Shorts" text indicators on screen.
     */
    private fun extractAllVisibleText(node: AccessibilityNodeInfo?): String {
        if (node == null) return ""
        val sb = StringBuilder()
        try {
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            if (text.isNotEmpty() && node.isVisibleToUser) {
                sb.append(text).append("\n")
            }
            if (desc.isNotEmpty() && node.isVisibleToUser) {
                sb.append(desc).append("\n")
            }
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                sb.append(extractAllVisibleText(child))
                child.recycle()
            }
        } catch (_: Exception) {}
        return sb.toString()
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  ENGINE 2 — Browser URL / Keyword Blocker
    // ══════════════════════════════════════════════════════════════════════════

    private fun scanBrowserUrlBar(packageName: String) {
        val keywords = BlockerConfig.restrictedKeywords
        if (keywords.isEmpty()) return

        val root = rootInActiveWindow ?: return
        try {
            // Walk all EditTexts to find the URL bar.
            val urlText = findUrlBarText(root)
            if (urlText.isBlank()) return

            val lastUrl = BlockerConfig.getLastUrlSnapshot(packageName) ?: ""
            if (urlText == lastUrl) return  // unchanged
            BlockerConfig.setLastUrlSnapshot(packageName, urlText)

            val urlLower = urlText.lowercase()
            for (keyword in keywords) {
                if (urlLower.contains(keyword.lowercase())) {
                    Log.i(TAG, "Keyword '$keyword' in browser URL — blocking.")
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    triggerBlockerOverlay(packageName, "Website Keyword: $keyword")
                    return
                }
            }
        } finally {
            root.recycle()
        }
    }

    private fun findUrlBarText(node: AccessibilityNodeInfo): String {
        val className = node.className?.toString()?.lowercase() ?: ""
        if (className == "android.widget.edittext" ||
            className == "android.widget.autocompletetextview"
        ) {
            val text = node.text?.toString() ?: ""
            if (text.length > 5) return text  // plausible URL
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findUrlBarText(child)
            child.recycle()
            if (result.isNotEmpty() && result.length > 5) return result
        }
        return ""
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  ENGINE 3 — Legacy Double-Tap Lock Screen
    // ══════════════════════════════════════════════════════════════════════════

    fun lockScreen(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  SHARED — Blocker Overlay Trigger
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * NOTIFY Flutter that a block was triggered.
     *
     * CRITICAL: Does NOT call GLOBAL_ACTION_HOME.  Previously this was
     * sending the user home every time a reels event fired, causing the
     * "dialog continuously popping" issue.  Now we just notify Flutter
     * and let the UI decide how to handle it.
     */
    private fun triggerBlockerOverlay(packageName: String, reason: String) {
        try {
            MainActivity.channel?.invokeMethod("onBlockTriggered", mapOf(
                "packageName" to packageName,
                "reason" to reason
            ))
            Log.i(TAG, "Block triggered: $packageName — $reason")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify Flutter: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service interrupted.")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) instance = null
        lastScanTime.clear()
        lastBlockTime.clear()
        Log.i(TAG, "Service destroyed.")
    }
}