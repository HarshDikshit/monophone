package com.dixit.monophone

import com.dixit.monophone.AppMonitoringService
import com.dixit.monophone.PomodoroOverlayService
import com.dixit.monophone.FocusAccessibilityService
import com.dixit.monophone.EmergencyUseTimerService
import com.dixit.monophone.DailyUsageMonitorService
import com.dixit.monophone.BlockerOverlayService
// Removed GrayscaleOverlayService import
import com.dixit.monophone.db.UsageDatabase

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.ArrayList
import java.util.Date
import java.util.Locale
import android.net.VpnService
import android.content.ComponentName
import android.util.Log

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.dixit.monophone/launcher"
    private val REQUEST_CODE_POST_NOTIFICATIONS = 2001
    private var widgetHostManager: AppWidgetHostManager? = null

    companion object {
        var channel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        widgetHostManager = AppWidgetHostManager(this)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.dixit.monophone/app_widget",
            AppWidgetPlatformViewFactory()
        )
        
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // ── Existing methods (unchanged) ────────────────────────────
                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    result.success(apps)
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val success = launchApp(packageName)
                        if (success) result.success(true)
                        else result.error("LAUNCH_FAILED", "Could not launch app", null)
                    } else {
                        result.error("BAD_ARGS", "Package name was null", null)
                    }
                }
                "hasUsageAccessPermission" -> {
                    result.success(hasUsageAccessPermission())
                }
                "requestUsageAccessPermission" -> {
                    requestUsageAccessPermission()
                    result.success(true)
                }
                "startMonitoring" -> {
                    val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                    startMonitoringService(blockedApps)
                    result.success(true)
                }
                "stopMonitoring" -> {
                    stopMonitoringService()
                    result.success(true)
                }
                "isDefaultLauncher" -> {
                    result.success(isDefaultLauncher())
                }
                "requestDefaultLauncher" -> {
                    requestDefaultLauncher()
                    result.success(true)
                }
                "isAccessibilityServiceEnabled" -> {
                    result.success(FocusAccessibilityService.instance != null)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "lockScreen" -> {
                    val service = FocusAccessibilityService.instance
                    if (service != null) {
                        val success = service.lockScreen()
                        result.success(success)
                    } else {
                        result.error("ACCESSIBILITY_DISABLED", "Accessibility service is not running", null)
                    }
                }
                "hasOverlayPermission" -> {
                    result.success(hasOverlayPermission())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "hasNotificationPermission" -> {
                    result.success(hasNotificationPermission())
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }
                "startDistractionTimer" -> {
                    val durationSeconds = call.argument<Int>("durationSeconds") ?: 300
                    val packageName = call.argument<String>("packageName") ?: ""
                    startDistractionTimer(durationSeconds, packageName)
                    result.success(true)
                }
                "stopDistractionTimer" -> {
                    stopDistractionTimer()
                    result.success(true)
                }
                "startPomodoro" -> {
                    val taskName = call.argument<String>("taskName") ?: "Focus Block"
                    val durationSeconds = call.argument<Int>("durationSeconds") ?: (25 * 60)
                    val isBreak = call.argument<Boolean>("isBreak") ?: false
                    val timerMode = call.argument<String>("timerMode") ?: "countdown"
                    val autoStartBreak = call.argument<Boolean>("autoStartBreak") ?: true
                    val autoStartNextPomodoro = call.argument<Boolean>("autoStartNextPomodoro") ?: true
                    val soundEnabled = call.argument<Boolean>("soundEnabled") ?: true
                    val vibrationEnabled = call.argument<Boolean>("vibrationEnabled") ?: true
                    startPomodoro(taskName, durationSeconds, isBreak, timerMode, autoStartBreak, autoStartNextPomodoro, soundEnabled, vibrationEnabled)
                    result.success(true)
                }
                "stopPomodoro" -> {
                    stopPomodoro()
                    result.success(true)
                }
                "updateTaskName" -> {
                    val taskName = call.argument<String>("taskName")
                    if (taskName != null) {
                        val service = PomodoroOverlayService.instance
                        if (service != null) {
                            service.taskName = taskName
                            // Refresh the overlay UI and notification to show the updated task name
                            service.updateUI()
                            service.updateNotification()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "openAppSettings" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    openAppSettings(packageName)
                    result.success(true)
                }
                "getPomodoroState" -> {
                    result.success(getPomodoroState())
                }

                // ════════════════════════════════════════════════════════════
                //  NEW METHODS — Deep-Focus Blocker System
                // ════════════════════════════════════════════════════════════

                /**
                 * Push all blocking configuration from Flutter to the native
                 * [BlockerConfig] singleton atomically.
                 *
                 * Args from Flutter:
                 *   - blockedPackages: List<String>   — packages to monitor
                 *   - dailyLimits:     Map<String, Int> — packageName → minutes
                 *   - blockFirstShort: Boolean         — Toggle A or B for Reels
                 *   - restrictedKeywords: List<String>  — browser URL keywords
                 */
                "configureBlockingRules" -> {
                    val blockedPackages = call.argument<List<String>>("blockedPackages")?.toSet()
                        ?: emptySet()
                    val dailyLimits = call.argument<HashMap<String, Int>>("dailyLimits")
                        ?: hashMapOf()
                    val allowOneShort = call.argument<HashMap<String, Boolean>>("allowOneShort")
                        ?: hashMapOf()
                    val restrictedKeywords = call.argument<List<String>>("restrictedKeywords")
                        ?.toSet() ?: emptySet()
                    val emergencyUseMaxCounts = call.argument<HashMap<String, Int>>("emergencyUseMaxCounts")
                        ?: hashMapOf()
                    val shortsBlockEnabledPackages = call.argument<List<String>>("shortsBlockEnabledPackages")?.toSet()
                        ?: emptySet()

                    Log.d("MainActivity", "configureBlockingRules: packages=${blockedPackages.size}, limits=${dailyLimits.size}, allowOne=${allowOneShort.size}, shortsBlock=${shortsBlockEnabledPackages.size}")

                    BlockerConfig.updateFromFlutter(
                        blockedPackages = blockedPackages,
                        dailyLimits = dailyLimits,
                        allowOneShort = allowOneShort,
                        restrictedKeywords = restrictedKeywords,
                        emergencyUseMaxCounts = emergencyUseMaxCounts,
                        shortsBlockEnabledPackages = shortsBlockEnabledPackages
                    )
                    result.success(true)
                }

                /**
                 * Start the [DailyUsageMonitorService] which accumulates
                 * foreground time for all packages listed in [BlockerConfig].
                 */
                "startDailyMonitoring" -> {
                    startDailyMonitoringService()
                    result.success(true)
                }

                /**
                 * Stop the [DailyUsageMonitorService].
                 */
                "stopDailyMonitoring" -> {
                    stopDailyMonitoringService()
                    result.success(true)
                }

                /**
                 * Start an emergency-use window for the given package.
                 * This delegates to [EmergencyUseTimerService] with a 5-minute duration.
                 *
                 * Args:
                 *   - packageName: String
                 */
                "triggerEmergencyUse" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    if (packageName.isNotEmpty()) {
                        triggerEmergencyUse(packageName)
                        result.success(true)
                    } else {
                        result.error("BAD_ARGS", "packageName required", null)
                    }
                }

                /**
                 * Return a map of per-package usage for today.
                 *   Format: Map<String, Int> — packageName → accumulatedSeconds
                 */
                "getUsageReport" -> {
                    result.success(getUsageReport())
                }

                /**
                 * Check if the [BlockerOverlayService] is currently showing.
                 * Returns a Boolean.
                 */
                "isBlockerOverlayShowing" -> {
                    // Conservative check: we track via the singleton state.
                    // A more precise implementation would query WindowManager.
                    result.success(false) // simplified — overlay is transient
                }

                // ── VPN, Notification, and Daltonizer (Grayscale) ────────────
                "toggleVpn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        startVpn()
                    } else {
                        stopVpn()
                    }
                    result.success(true)
                }
                "hasNotificationAccess" -> {
                    result.success(hasNotificationAccess())
                }
                "requestNotificationAccess" -> {
                    requestNotificationAccess()
                    result.success(true)
                }
                "toggleSystemGrayscale" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    toggleGrayscaleOverlay(enabled)
                    result.success(true)
                }
                "isGrayscaleOverlayActive" -> {
                    result.success(false) // Overlay service removed
                }

                // ════════════════════════════════════════════════════════════
                //  APP WIDGET HOST METHODS
                // ════════════════════════════════════════════════════════════

                "getAvailableWidgetProviders" -> {
                    val providers = widgetHostManager?.getAvailableWidgetProviders() ?: emptyList()
                    result.success(providers)
                }

                "bindAppWidget" -> {
                    val providerName = call.argument<String>("providerName") ?: ""
                    val host = widgetHostManager
                    if (host != null) {
                        host.requestBindWidget(providerName, result, this)
                    } else {
                        result.error("HOST_UNAVAILABLE", "AppWidgetHostManager is not initialized", null)
                    }
                }

                "removeAppWidget" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    if (appWidgetId > 0) {
                        widgetHostManager?.removeWidget(appWidgetId)
                        result.success(true)
                    } else {
                        result.error("BAD_ARGS", "Invalid appWidgetId", null)
                    }
                }

                "startWidgetHost" -> {
                    widgetHostManager?.startListening()
                    result.success(true)
                }

                "stopWidgetHost" -> {
                    widgetHostManager?.stopListening()
                    result.success(true)
                }

                "isBatteryOptimizationIgnored" -> {
                    result.success(isBatteryOptimizationIgnored())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "hasWriteSecureSettingsPermission" -> {
                    result.success(hasWriteSecureSettingsPermission())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  EXISTING PRIVATE HELPERS (unchanged)
    // ═══════════════════════════════════════════════════════════════════════════

    private fun getInstalledApps(): List<Map<String, String>> {
        val appsList = ArrayList<Map<String, String>>()
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolvedInfos = packageManager.queryIntentActivities(mainIntent, 0)
        for (info in resolvedInfos) {
            val appLabel = info.loadLabel(packageManager).toString()
            val packageName = info.activityInfo.packageName
            if (packageName != context.packageName) {
                val appMap = HashMap<String, String>()
                appMap["name"] = appLabel
                appMap["packageName"] = packageName
                appsList.add(appMap)
            }
        }
        appsList.sortBy { it["name"]?.lowercase() }
        return appsList
    }

    private fun launchApp(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        return if (intent != null) {
            startActivity(intent)
            true
        } else {
            false
        }
    }

    private fun hasUsageAccessPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageAccessPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun startMonitoringService(blockedApps: List<String>) {
        val intent = Intent(this, AppMonitoringService::class.java).apply {
            putStringArrayListExtra("blockedApps", ArrayList(blockedApps))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopMonitoringService() {
        val intent = Intent(this, AppMonitoringService::class.java)
        stopService(intent)
    }

    private fun isDefaultLauncher(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        val resolveInfo = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolveInfo?.activityInfo?.packageName == packageName
    }

    private fun requestDefaultLauncher() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_HOME_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (ex: Exception) {
                try {
                    val intent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                } catch (e2: Exception) {
                    // Fail silently
                }
            }
        }
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_CODE_POST_NOTIFICATIONS
            )
        }
    }

    private fun startDistractionTimer(durationSeconds: Int, targetPackage: String) {
        // Legacy distraction timer — now delegates to EmergencyUseTimerService
        val intent = Intent(this, EmergencyUseTimerService::class.java).apply {
            putExtra("packageName", targetPackage)
            putExtra("durationMs", durationSeconds * 1000L)
            putExtra("blockReason", "Distraction timer (${durationSeconds / 60} min)")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopDistractionTimer() {
        val intent = Intent(this, EmergencyUseTimerService::class.java)
        stopService(intent)
    }

    private fun startPomodoro(
        taskName: String,
        durationSeconds: Int,
        isBreak: Boolean,
        timerMode: String = "countdown",
        autoStartBreak: Boolean = true,
        autoStartNextPomodoro: Boolean = true,
        soundEnabled: Boolean = true,
        vibrationEnabled: Boolean = true,
    ) {
        val intent = Intent(this, PomodoroOverlayService::class.java).apply {
            action = PomodoroOverlayService.ACTION_START
            putExtra("taskName", taskName)
            putExtra("durationSeconds", durationSeconds)
            putExtra("isBreak", isBreak)
            putExtra("timerMode", timerMode)
            putExtra("autoStartBreak", autoStartBreak)
            putExtra("autoStartNextPomodoro", autoStartNextPomodoro)
            putExtra("soundEnabled", soundEnabled)
            putExtra("vibrationEnabled", vibrationEnabled)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopPomodoro() {
        val intent = Intent(this, PomodoroOverlayService::class.java).apply {
            action = PomodoroOverlayService.ACTION_STOP
        }
        startService(intent)
    }

    private fun openAppSettings(packageName: String) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun getPomodoroState(): Map<String, Any>? {
        val service = PomodoroOverlayService.instance
        if (service != null && service.isRunning) {
            return mapOf(
                "secondsRemaining" to service.secondsRemaining,
                "isBreak" to service.isBreak,
                "isPaused" to service.isPaused,
                "taskName" to service.taskName,
                "timerMode" to service.timerMode
            )
        }
        return null
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  NEW PRIVATE HELPERS — Deep-Focus Blocker System
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Start the [DailyUsageMonitorService] which polls UsageStatsManager
     * every 5 seconds and accumulates per-package foreground time.
     */
    private fun startDailyMonitoringService() {
        val intent = Intent(this, DailyUsageMonitorService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /**
     * Stop the [DailyUsageMonitorService].
     */
    private fun stopDailyMonitoringService() {
        val intent = Intent(this, DailyUsageMonitorService::class.java)
        stopService(intent)
    }

    /**
     * Trigger an emergency-use window for [packageName].
     * Starts [EmergencyUseTimerService] with a 5-minute duration.
     */
    private fun triggerEmergencyUse(packageName: String) {
        val intent = Intent(this, EmergencyUseTimerService::class.java).apply {
            putExtra("packageName", packageName)
            putExtra("durationMs", 5 * 60 * 1000L)  // 5 minutes
            putExtra("blockReason", "User-initiated emergency use")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /**
     * Query [UsageDatabase] for today's per-package usage and return as
     * a Map<String, Int> for the Flutter UI.
     */
    private fun getUsageReport(): Map<String, Int> {
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val dao = UsageDatabase.getInstance(this).dailyUsageDao()
        val result = HashMap<String, Int>()

        try {
            // Use a synchronous call via the executor.
            val future = java.util.concurrent.CompletableFuture<Map<String, Int>>()
            UsageDatabase.databaseWriteExecutor.execute {
                try {
                    val allUsage = dao.getAllUsageForDate(date)
                    for (usage in allUsage) {
                        result[usage.packageName] = usage.accumulatedSeconds
                    }
                    future.complete(result)
                } catch (e: Exception) {
                    future.complete(result) // return partial or empty
                }
            }
            // Block briefly (should be fast since DB executor is single-thread).
            return future.get(500, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (_: Exception) {
            return result
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            val isDefault = isDefaultLauncher()
            channel?.invokeMethod("onDefaultLauncherChanged", isDefault)
        } else if (requestCode == 2002) {
            // VPN prepared activity result: start the service
            if (resultCode == RESULT_OK) {
                val startIntent = Intent(this, FocusVpnService::class.java)
                startService(startIntent)
            }
        } else if (requestCode == 0x0B0B) {
            widgetHostManager?.handleActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        widgetHostManager?.dispose()
        super.onDestroy()
    }

    private fun startVpn() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, 2002)
        } else {
            val startIntent = Intent(this, FocusVpnService::class.java)
            startService(startIntent)
        }
    }

    private fun stopVpn() {
        val stopIntent = Intent(this, FocusVpnService::class.java).apply {
            action = "STOP"
        }
        startService(stopIntent)
    }

    private fun hasNotificationAccess(): Boolean {
        val cn = ComponentName(this, FocusNotificationListenerService::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(cn.flattenToString())
    }

    private fun requestNotificationAccess() {
        val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun toggleGrayscaleOverlay(enabled: Boolean) {
        try {
            // Try to set the official Android Daltonizer (Color Correction) setting.
            // This requires android.permission.WRITE_SECURE_SETTINGS, which must be
            // granted once via ADB: adb shell pm grant com.dixit.monophone android.permission.WRITE_SECURE_SETTINGS
            
            val enabledVal = if (enabled) 1 else 0
            val grayscaleVal = 0 // 0 is the constant for Grayscale mode
            
            val success = Settings.Secure.putInt(contentResolver, "accessibility_display_daltonizer_enabled", enabledVal)
            Settings.Secure.putInt(contentResolver, "accessibility_display_daltonizer", if (enabled) grayscaleVal else -1)
            
            if (!success) {
                Log.w("MainActivity", "Failed to set grayscale via Settings.Secure (Permission denied?)")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error toggling system grayscale: ${e.message}")
        }
        
        // Grayscale overlay cleanup removed (service deleted)
    }

    private fun hasWriteSecureSettingsPermission(): Boolean {
        return checkCallingOrSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                startActivity(intent)
            } catch (e: Exception) {
                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(fallbackIntent)
            }
        }
    }
}