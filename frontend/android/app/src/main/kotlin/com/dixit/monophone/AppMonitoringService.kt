package com.dixit.monophone

import android.app.*
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.util.ArrayList

class AppMonitoringService : Service() {

    private val CHANNEL_ID = "AppMonitoringServiceChannel"
    private var isRunning = false
    private val handler = Handler(Looper.getMainLooper())
    private var blockedApps: List<String> = emptyList()
    private val monitorRunnable = object : Runnable {
        override fun run() {
            if (isRunning) {
                checkForegroundApp()
                handler.postDelayed(this, 1000) // Check every second
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val appList = intent?.getStringArrayListExtra("blockedApps")
        if (appList != null) {
            blockedApps = appList
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Focus Mode Enabled")
            .setContentText("Hard lock is active. Stay focused on your goals.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        startForeground(1, notification)
        isRunning = true
        handler.post(monitorRunnable)

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(monitorRunnable)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    /**
     * Check which app is in the foreground.  If it's a blocked app, immediately
     * re-launch our MainActivity (the launcher home screen) to intercept the user.
     *
     * This is the ROCK-SOLID way to block apps on Android because:
     * 1. UsageStatsManager works on every Android version since API 21.
     * 2. It does NOT require accessibility service.
     * 3. It is the same mechanism Samsung/OneUI itself uses for app usage stats.
     *
     * For Reels/Shorts blocking specifically: since these are activities within
     * the parent app (Instagram, YouTube, TikTok), we block the whole app.
     * This is more aggressive than UI-based blocking but it WORKS reliably.
     */
    private fun checkForegroundApp() {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 10000 // Query last 10 seconds

        val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
        val event = UsageEvents.Event()
        var currentForegroundApp: String? = null

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                currentForegroundApp = event.packageName
            }
        }

        if (currentForegroundApp != null && blockedApps.contains(currentForegroundApp)) {
            // Bypass block if the app is currently temporarily allowed (Emergency Use)
            if (currentForegroundApp == TempAccessManager.tempAllowedPackage) {
                return
            }
            // Also bypass if we're in emergency use mode for this package
            if (TempAccessManager.isEmergencyUseActive &&
                TempAccessManager.tempAllowedPackage == currentForegroundApp) {
                return
            }
            // Blocked app is in the foreground! Intercept and launch Launcher back.
            val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                )
            }
            startActivity(launchIntent)

            // Notify Flutter to update the UI / show block dialog.
            try {
                MainActivity.channel?.invokeMethod("onBlockTriggered", mapOf(
                    "packageName" to (currentForegroundApp ?: ""),
                    "reason" to "Blocked app launch"
                ))
            } catch (_: Exception) {}
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Focus Mode Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }
}
