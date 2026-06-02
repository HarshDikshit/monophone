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
            // Bypass block if the app is currently temporarily allowed
            if (currentForegroundApp == TempAccessManager.tempAllowedPackage) {
                return
            }
            // Blocked app is in the foreground! Intercept and launch Launcher back
            val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(launchIntent)
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
