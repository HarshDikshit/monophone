package com.dixit.monophone

import android.content.Context
import android.content.SharedPreferences

/**
 * Singleton that tracks the currently "temporarily allowed" package and its
 * emergency-use state.
 */
object TempAccessManager {

    /** Package that is currently exempt from blocking. */
    @Volatile
    var tempAllowedPackage: String? = null

    /** System uptime millis when the emergency use window will expire. */
    @Volatile
    var emergencyUseExpiryMs: Long = 0L

    /** SharedPreferences key for tracking daily emergency use counts per app. */
    private const val PREFS_NAME = "emergency_use_tracker"
    private const val DAILY_USED_KEY = "emergency_used_today"

    val isEmergencyUseActive: Boolean
        get() = emergencyUseExpiryMs > 0L &&
                android.os.SystemClock.elapsedRealtime() < emergencyUseExpiryMs

    fun startEmergencyUse(packageName: String, durationMs: Long) {
        tempAllowedPackage = packageName
        emergencyUseExpiryMs = android.os.SystemClock.elapsedRealtime() + durationMs
    }

    fun clearEmergencyUse() {
        tempAllowedPackage = null
        emergencyUseExpiryMs = 0L
    }

    /**
     * Returns the number of emergency uses already consumed today for the given package.
     */
    fun getUsedEmergencyCount(context: Context, packageName: String): Int {
        val prefs = getPrefs(context)
        val todayKey = getTodayKey()
        val map = prefs.getString(DAILY_USED_KEY, "{}") ?: "{}"
        try {
            val json = org.json.JSONObject(map)
            val dayData = json.optJSONObject(todayKey) ?: return 0
            return dayData.optInt(packageName, 0)
        } catch (_: Exception) {
            return 0
        }
    }

    /**
     * Increments the emergency use count for today for the given package.
     */
    fun incrementUsedEmergencyCount(context: Context, packageName: String) {
        val prefs = getPrefs(context)
        val todayKey = getTodayKey()
        val map = prefs.getString(DAILY_USED_KEY, "{}") ?: "{}"
        try {
            val json = org.json.JSONObject(map)
            val dayData = json.optJSONObject(todayKey) ?: org.json.JSONObject()
            dayData.put(packageName, dayData.optInt(packageName, 0) + 1)
            json.put(todayKey, dayData)
            prefs.edit().putString(DAILY_USED_KEY, json.toString()).apply()
        } catch (_: Exception) {}
    }

    /**
     * Returns the max allowed emergency uses for the given package (read from BlockerConfig).
     */
    fun getMaxEmergencyCount(context: Context, packageName: String): Int {
        return BlockerConfig.emergencyUseMaxCounts[packageName] ?: 3
    }

    /**
     * Returns remaining emergency uses for the package.
     */
    fun getRemainingEmergencyCount(context: Context, packageName: String): Int {
        val maxAllowed = getMaxEmergencyCount(context, packageName)
        val used = getUsedEmergencyCount(context, packageName)
        return (maxAllowed - used).coerceAtLeast(0)
    }

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private fun getTodayKey(): String {
        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        return sdf.format(java.util.Date())
    }
}
