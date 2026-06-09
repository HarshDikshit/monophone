package com.dixit.monophone

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.Build
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
        if (packageName == "com.dixit.monophone") {
            lastBlockTime.clear()
        }
        currentForegroundPackage = packageName

        // ── Enforce strict mode settings/uninstall block ─────────────────────
        if (isStrictModeActive()) {
            if (packageName == "com.android.settings" ||
                packageName == "com.google.android.packageinstaller" ||
                packageName == "com.android.packageinstaller"
            ) {
                Log.w(TAG, "Strict mode is active. Intercepting settings/uninstall attempt.")
                performGlobalAction(GLOBAL_ACTION_HOME)
                return
            }
        }

        // ── Cooldown check ───────────────────────────────────────────────────
        val now = System.currentTimeMillis()
        val lastScan = lastScanTime[packageName] ?: 0L
        if (now - lastScan < SCAN_COOLDOWN_MS) return
        lastScanTime[packageName] = now

        try {
            // ── Engine 1: Reels/Shorts detection for social apps ─────────────
            if (isReelsShortsPackage(packageName)) {
                // Fire on both WINDOW_STATE_CHANGED (new Activity / app launch)
                // AND WINDOW_CONTENT_CHANGED (in-app tab navigation like
                // YouTube's Shorts tab appearing without Activity change).
                // The per-package SCAN_COOLDOWN_MS (800ms) above already
                // prevents excessive re-scanning on scroll events.
                scanForReelsShorts(packageName)
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

    private fun isStrictModeActive(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val isStrict = prefs.getBoolean("flutter.focustube_strict_mode", false)
        if (!isStrict) return false
        val lockUntilStr = prefs.getString("flutter.focustube_lock_until", "") ?: ""
        if (lockUntilStr.isNotEmpty()) {
            try {
                // ISO date parsing
                val date = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).parse(lockUntilStr)
                if (date != null && System.currentTimeMillis() < date.time) {
                    return true
                }
            } catch (_: Exception) {}
        }
        return isStrict
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
        // Check if the reels/shorts blocker is actually enabled in BlockerConfig.
        // If no blocked packages are configured yet, skip.
        // (BlockerConfig is populated when Flutter calls configureBlockingRules).
        // We still check even when blockedPackages is empty because the user
        // might have set the blockReelsShorts flag via SharedPreferences directly.
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val blockReelsEnabled = prefs.getBoolean("flutter.focustube_block_reels_shorts", false)
        if (!blockReelsEnabled) return

        // Prevent re-blocking the same package within 10 seconds.
        val now = System.currentTimeMillis()
        val lastBlock = lastBlockTime[packageName] ?: 0L
        if (now - lastBlock < BLOCK_COOLDOWN_MS) return

        // Check if the current activity text indicates reels/shorts.
        val isInShortsFeed = checkIfInShortsFeed(packageName)

        if (isInShortsFeed) {
            // Respect the blockFirstShort toggle:
            //   true  (Toggle A) → block even the very first short
            //   false (Toggle B) → let the first one play; block on the next
            val blockFirst = BlockerConfig.blockFirstShort
            val alreadyAcknowledged = BlockerConfig.isFirstReelAcknowledged(packageName)

            if (!blockFirst && !alreadyAcknowledged) {
                // Allow the first one — just mark it acknowledged.
                BlockerConfig.setFirstReelAcknowledged(packageName, true)
                Log.i(TAG, "First reel/short allowed for $packageName (Toggle B).")
                return
            }

            Log.i(TAG, "Reels/Shorts detected for $packageName — blocking.")
            lastBlockTime[packageName] = now
            triggerBlockerOverlay(packageName, "Smart Reels/Shorts Blocker")
        } else {
            // User navigated away from the shorts feed — reset the Toggle B flag.
            BlockerConfig.clearFirstReelAcknowledged(packageName)
        }
    }

    /**
     * Walk the node tree (via findFocus or window root) looking for text
     * indicators that we're in a Shorts/Reels feed.
     *
     * On Samsung devices, resource IDs may not be reliable.  We use
     * content descriptions and text content as the primary signal.
     */
    private fun checkIfInShortsFeed(packageName: String): Boolean {
        // Try get the root via the most reliable method for Samsung.
        val root = rootInActiveWindow
        if (root != null) {
            try {
                // Quick scan of all text on screen.
                val textContent = extractAllVisibleText(root).lowercase(java.util.Locale.US)
                if (textContent.isNotEmpty()) {
                    if (packageName.contains("youtube")) {
                        // Avoid blocking main home screens
                        val isHomeScreen = textContent.contains("home") && textContent.contains("subscriptions")
                        if (isHomeScreen) {
                            root.recycle()
                            return false
                        }

                        // Shorts watch layout elements: Dislike, Remix, Share
                        val hasShortsPlayerText = textContent.contains("dislike") &&
                                textContent.contains("remix") &&
                                (textContent.contains("share") || textContent.contains("comments"))
                        
                        if (hasShortsPlayerText) {
                            root.recycle()
                            return true
                        }
                    }

                    if (packageName.contains("instagram")) {
                        val isHomeScreen = textContent.contains("search") && textContent.contains("profile")
                        if (isHomeScreen) {
                            root.recycle()
                            return false
                        }

                        val isInReels = textContent.contains("reel") || textContent.contains("reels")
                        if (isInReels) {
                            root.recycle()
                            return true
                        }
                    }

                    // Predefined simple match
                    if (textContent.contains("shorts") || textContent.contains("reels")) {
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
            val text = focused.text?.toString()?.lowercase(java.util.Locale.US) ?: ""
            val desc = focused.contentDescription?.toString()?.lowercase(java.util.Locale.US) ?: ""
            val className = focused.className?.toString()?.lowercase(java.util.Locale.US) ?: ""
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
     *
     * SAFETY: Hard-capped at [maxDepth] levels deep to prevent
     * StackOverflowError on apps (e.g. YouTube) with 200+ nested ViewGroups.
     * Also caps total output at 4096 chars to avoid excessive string allocation.
     */
    private fun extractAllVisibleText(
        node: AccessibilityNodeInfo?,
        depth: Int = 0,
        maxDepth: Int = 12
    ): String {
        if (node == null || depth > maxDepth) return ""
        val sb = StringBuilder()
        try {
            if (sb.length > 4096) return sb.toString() // cap to avoid OOM
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            if (text.isNotEmpty() && node.isVisibleToUser) {
                sb.append(text).append("\n")
            }
            if (desc.isNotEmpty() && node.isVisibleToUser) {
                sb.append(desc).append("\n")
            }
            for (i in 0 until node.childCount) {
                if (sb.length > 4096) break
                val child = node.getChild(i) ?: continue
                val childText = extractAllVisibleText(child, depth + 1, maxDepth)
                child.recycle()
                sb.append(childText)
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
     * Start [BlockerOverlayService] directly from the accessibility service.
     *
     * CRITICAL FIX: Previously this only notified Flutter via MethodChannel,
     * but the Flutter side had no handler for "onBlockTriggered", so the block
     * was silently swallowed.  Now we start the overlay service directly so it
     * works even when Flutter/MainActivity is not in the foreground.
     *
     * We also perform GLOBAL_ACTION_BACK to pull the user out of the shorts
     * feed before the overlay appears, preventing the "shorts playing behind
     * the overlay" visual glitch.
     */
    private fun triggerBlockerOverlay(packageName: String, reason: String) {
        try {
            // Navigate away from the shorts screen first.
            performGlobalAction(GLOBAL_ACTION_BACK)

            // Start the full-screen blocking overlay.
            val overlayIntent = Intent(this, BlockerOverlayService::class.java).apply {
                putExtra("blockedPackage", packageName)
                putExtra("blockReason", reason)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(overlayIntent)
            } else {
                startService(overlayIntent)
            }

            // Also notify Flutter (best-effort) so analytics/UI can update.
            try {
                MainActivity.channel?.invokeMethod("onBlockTriggered", mapOf(
                    "packageName" to packageName,
                    "reason" to reason
                ))
            } catch (_: Exception) {}

            Log.i(TAG, "Block triggered: $packageName — $reason")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to trigger blocker overlay: ${e.message}")
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