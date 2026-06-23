package com.dixit.monophone

import java.util.concurrent.atomic.AtomicReference

/**
 * Thread-safe singleton that holds the current day's live usage metrics.
 * Updated by [DailyUsageMonitorService] and read by [FocusAccessibilityService] 
 * and [BlockerOverlayService] for real-time limit enforcement.
 */
object UsageTracker {

    /** 
     * Live accumulated seconds today, keyed by package name.
     * This combines the persistent DB total + the current session's live count.
     */
    private val _liveUsageSeconds = AtomicReference<Map<String, Int>>(emptyMap())
    
    var liveUsageSeconds: Map<String, Int>
        get() = _liveUsageSeconds.get()
        set(value) = _liveUsageSeconds.set(HashMap(value))

    /**
     * Update the live count for a specific package.
     */
    fun updateLiveUsage(packageName: String, totalSeconds: Int) {
        val current = HashMap(_liveUsageSeconds.get())
        current[packageName] = totalSeconds
        _liveUsageSeconds.set(current)
    }

    /**
     * Core helper: Check if [packageName] has exceeded its daily limit
     * configured in [BlockerConfig].
     */
    fun isLimitExceeded(packageName: String): Boolean {
        // Skip check for the launcher itself or system UI
        if (packageName == "com.dixit.monophone" || 
            packageName == "com.android.systemui"
        ) return false

        // Check if an emergency use window is active
        if (TempAccessManager.isEmergencyUseActive && 
            TempAccessManager.tempAllowedPackage == packageName
        ) return false

        val limits = BlockerConfig.dailyLimitsInMinutes
        val limitMin = limits[packageName] ?: return false
        val limitSec = limitMin * 60

        val usedSec = _liveUsageSeconds.get()[packageName] ?: 0
        return usedSec >= limitSec
    }
}
