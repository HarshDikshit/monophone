package com.dixit.monophone

import java.util.concurrent.atomic.AtomicReference

/**
 * Thread-safe configuration hub that receives blocking rules from Flutter
 * via MethodChannel and exposes them to all native services.
 *
 * Every public field is backed by an AtomicReference so that the
 * [FocusAccessibilityService], [DailyUsageMonitorService], and
 * [BlockerOverlayService] can read the current config without
 * synchronization overhead on their hot paths.
 *
 * ── Flow ──
 * 1. Flutter calls `configureBlockingRules` on the MethodChannel.
 * 2. [MainActivity] deserialises the args and calls [updateFromFlutter].
 * 3. All native services read [instance] fields on their next tick/event.
 */
object BlockerConfig {

    // ── Atomic-backed state ─────────────────────────────────────────────────

    /** Foreground packages whose usage should be accumulated. */
    private val _blockedPackages = AtomicReference<Set<String>>(emptySet())
    val blockedPackages: Set<String> get() = _blockedPackages.get()

    /**
     * Daily limits in minutes, keyed by package name.
     * Example: "com.instagram.android" → 60 (minutes).
     */
    private val _dailyLimitsInMinutes = AtomicReference<Map<String, Int>>(emptyMap())
    val dailyLimitsInMinutes: Map<String, Int> get() = _dailyLimitsInMinutes.get()

    /**
     * Toggle for Smart Reels/Shorts blocker:
     *   true  → Block from the very first Reel/Short video detected. (Toggle A)
     *   false → Allow the first one, then block after the next scroll (Toggle B).
     */
    private val _blockFirstShort = AtomicReference(true)
    val blockFirstShort: Boolean get() = _blockFirstShort.get()

    /** Keywords that, when detected in a browser URL bar, trigger a block. */
    private val _restrictedKeywords = AtomicReference<Set<String>>(emptySet())
    val restrictedKeywords: Set<String> get() = _restrictedKeywords.get()

    /** Hardcoded set of browser packages that the keyword-blocker scans. */
    val supportedBrowserPackages: Set<String> = setOf(
        "com.android.chrome",
        "com.chrome.beta",
        "com.chrome.dev",
        "org.mozilla.firefox",
        "org.mozilla.firefox_beta",
        "com.sec.android.app.sbrowser",          // Samsung Internet
        "com.microsoft.emmx",                    // Microsoft Edge
        "com.brave.browser",
        "com.opera.browser",
        "com.opera.mini.native",
        "com.vivaldi.browser",
        "com.duckduckgo.mobile.android"
    )

    // ── Package-state tracking for Toggle B (allow-first-scroll-then-block) ─

    /**
     * Per-package flag: has the FIRST short-form video been acknowledged?
     * Cleared when the package exits the foreground.
     */
    private val _firstReelAcknowledged = AtomicReference<Map<String, Boolean>>(emptyMap())

    fun isFirstReelAcknowledged(packageName: String): Boolean {
        return _firstReelAcknowledged.get()[packageName] ?: false
    }

    fun setFirstReelAcknowledged(packageName: String, acknowledged: Boolean) {
        val copy = HashMap(_firstReelAcknowledged.get())
        copy[packageName] = acknowledged
        _firstReelAcknowledged.set(copy)
    }

    fun clearFirstReelAcknowledged(packageName: String) {
        val copy = HashMap(_firstReelAcknowledged.get())
        copy.remove(packageName)
        _firstReelAcknowledged.set(copy)
    }

    // ── Snapshot cache for URL keyword scanning ─────────────────────────────

    /**
     * The last URL text we scanned for each browser package.  Avoids
     * re-scanning the same URL text on every accessibility event.
     */
    private val _lastUrlSnapshot = AtomicReference<Map<String, String>>(emptyMap())

    fun getLastUrlSnapshot(packageName: String): String? {
        return _lastUrlSnapshot.get()[packageName]
    }

    fun setLastUrlSnapshot(packageName: String, url: String) {
        val copy = HashMap(_lastUrlSnapshot.get())
        copy[packageName] = url
        _lastUrlSnapshot.set(copy)
    }

    // ── Config update from Flutter ──────────────────────────────────────────

    /**
     * Atomically swap all configuration values.  Called from [MainActivity]
     * when Flutter invokes the `configureBlockingRules` method.
     *
     * @param blockedPackages Set of package names to monitor.
     * @param dailyLimits Map of packageName → daily limit in minutes.
     * @param blockFirstShort True = block 1st reel/short; false = block on scroll.
     * @param restrictedKeywords Keywords to match in browser URL bars.
     */
    fun updateFromFlutter(
        blockedPackages: Set<String>,
        dailyLimits: Map<String, Int>,
        blockFirstShort: Boolean,
        restrictedKeywords: Set<String>
    ) {
        _blockedPackages.set(blockedPackages.toSet())
        _dailyLimitsInMinutes.set(HashMap(dailyLimits))
        _blockFirstShort.set(blockFirstShort)
        _restrictedKeywords.set(restrictedKeywords.toSet())
    }
}