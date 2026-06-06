package com.dixit.monophone

/**
 * Singleton that tracks the currently "temporarily allowed" package and its
 * emergency-use state.
 *
 * ── Usage ──
 *
 * **Emergency Use (5-minute bypass):**
 * 1. [EmergencyUseTimerService] sets [tempAllowedPackage] and [emergencyUseExpiryMs].
 * 2. [AppMonitoringService] / [FocusAccessibilityService] skip blocking checks
 *    while the foreground package matches [tempAllowedPackage].
 * 3. When [EmergencyUseTimerService] expires, it clears these fields and
 *    re-launches [BlockerOverlayService].
 *
 * **Distraction Timer (legacy):**
 * [DistractionTimerService] (or the new [EmergencyUseTimerService]) sets
 * [tempAllowedPackage] and clears it on destroy.
 */
object TempAccessManager {

    /** Package that is currently exempt from blocking. */
    @Volatile
    var tempAllowedPackage: String? = null

    /**
     * System uptime millis (SystemClock.elapsedRealtime()) when the emergency
     * use window will expire.  0L if no emergency use is active.
     */
    @Volatile
    var emergencyUseExpiryMs: Long = 0L

    /**
     * Returns true if an emergency use window is currently active and has
     * not yet expired.
     */
    val isEmergencyUseActive: Boolean
        get() = emergencyUseExpiryMs > 0L &&
                android.os.SystemClock.elapsedRealtime() < emergencyUseExpiryMs

    /**
     * Initialise an emergency-use window.
     *
     * @param packageName The package to exempt.
     * @param durationMs Duration in milliseconds (typically 5 minutes = 300_000L).
     */
    fun startEmergencyUse(packageName: String, durationMs: Long) {
        tempAllowedPackage = packageName
        emergencyUseExpiryMs = android.os.SystemClock.elapsedRealtime() + durationMs
    }

    /** Clear the emergency-use state (called when the timer expires or is cancelled). */
    fun clearEmergencyUse() {
        tempAllowedPackage = null
        emergencyUseExpiryMs = 0L
    }
}