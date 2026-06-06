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
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import com.dixit.monophone.db.UsageDatabase
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ──────────────────────────────────────────────────────────────────────────────
 * DailyUsageMonitorService — Per-package foreground-time accumulator.
 * ──────────────────────────────────────────────────────────────────────────────
 *
 * Foreground service that polls [UsageStatsManager] every 5 seconds, increments
 * per-package accumulated seconds in the local SQLite database, and checks daily
 * limits.  When a limit is exceeded, launches [BlockerOverlayService].
 *
 * ── Battery Efficiency ──
 * • Poll interval: 5 seconds (vs 1s in old AppMonitoringService).
 * • In-memory accumulator flushed to DB every 30 seconds.
 * • If [BlockerConfig.blockedPackages] is empty, exits early.
 * ──────────────────────────────────────────────────────────────────────────────
 */
class DailyUsageMonitorService : Service() {

    companion object {
        private const val TAG = "DailyUsageMonitor"
        private const val CHANNEL_ID = "DailyUsageMonitorChannel"
        private const val NOTIFICATION_ID = 10
        private const val POLL_INTERVAL_MS = 5000L
        private const val FLUSH_INTERVAL_MS = 30_000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false

    /** In-memory accumulator: packageName → seconds accumulated since last DB flush. */
    private val pendingAccumulator = HashMap<String, Int>()

    /** Timestamp (SystemClock.elapsedRealtime) of the last UsageEvents query. */
    private var lastQueryTime = 0L

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            pollUsageStats()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    private val flushRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            flushAccumulatedUsage()
            handler.postDelayed(this, FLUSH_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, createNotification())

        isRunning = true
        lastQueryTime = SystemClock.elapsedRealtime()
        pendingAccumulator.clear()

        handler.post(pollRunnable)
        handler.post(flushRunnable)

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(pollRunnable)
        handler.removeCallbacks(flushRunnable)
        flushAccumulatedUsage()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Core polling ─────────────────────────────────────────────────────────

    private fun pollUsageStats() {
        val blockedPackages = BlockerConfig.blockedPackages
        if (blockedPackages.isEmpty()) return

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = SystemClock.elapsedRealtime()
        val realtimeNow = System.currentTimeMillis()
        val realtimeLastQuery = realtimeNow - (now - lastQueryTime)

        val packagesSeen = HashSet<String>()

        try {
            val usageEvents = usageStatsManager.queryEvents(realtimeLastQuery, realtimeNow)
            val event = UsageEvents.Event()

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                    event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND ||
                    event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                    event.eventType == UsageEvents.Event.ACTIVITY_PAUSED
                ) {
                    val pkg = event.packageName ?: continue
                    if (blockedPackages.contains(pkg)) {
                        packagesSeen.add(pkg)
                    }
                }
            }

            val elapsedMs = now - lastQueryTime
            val elapsedSec = (elapsedMs / 1000).toInt()

            for (pkg in packagesSeen) {
                pendingAccumulator[pkg] = (pendingAccumulator[pkg] ?: 0) + elapsedSec
            }

        } catch (e: SecurityException) {
            stopSelf()
        } catch (_: Exception) {}

        lastQueryTime = now
        checkLimitExceeded()
    }

    // ── DB Flush ─────────────────────────────────────────────────────────────

    private fun flushAccumulatedUsage() {
        if (pendingAccumulator.isEmpty()) return

        val date = todayDateString()
        val database = UsageDatabase.getInstance(this)
        val dao = database.dailyUsageDao()

        val snapshot: Map<String, Int>
        synchronized(pendingAccumulator) {
            snapshot = HashMap(pendingAccumulator)
            pendingAccumulator.clear()
        }

        UsageDatabase.databaseWriteExecutor.execute {
            for ((pkg, seconds) in snapshot) {
                try {
                    dao.incrementUsage(pkg, date, seconds)
                } catch (_: Exception) {}
            }
            // After flush, check limits from DB.
            checkLimitExceededFromDb(dao, date)
        }
    }

    // ── Limit enforcement ────────────────────────────────────────────────────

    private fun checkLimitExceeded() {
        val limits = BlockerConfig.dailyLimitsInMinutes
        if (limits.isEmpty()) return

        for ((pkg, pendingSec) in pendingAccumulator) {
            val limitSec = (limits[pkg] ?: return) * 60
            if (pendingSec >= limitSec) {
                triggerBlockForPackage(pkg, "Daily usage limit exceeded")
                return
            }
        }
    }

    private fun checkLimitExceededFromDb(dao: com.dixit.monophone.db.DailyUsageDao, date: String) {
        val limits = BlockerConfig.dailyLimitsInMinutes
        if (limits.isEmpty()) return

        try {
            val allUsage = dao.getAllUsageForDate(date)
            for (usage in allUsage) {
                val limitSec = (limits[usage.packageName] ?: continue) * 60
                if (usage.accumulatedSeconds >= limitSec) {
                    triggerBlockForPackage(usage.packageName, "Daily usage limit exceeded")
                    return
                }
            }
        } catch (_: Exception) {}
    }

    private fun triggerBlockForPackage(packageName: String, reason: String) {
        if (TempAccessManager.isEmergencyUseActive &&
            TempAccessManager.tempAllowedPackage == packageName
        ) {
            return
        }

        val intent = Intent(this, BlockerOverlayService::class.java).apply {
            putExtra("blockedPackage", packageName)
            putExtra("blockReason", reason)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(intent)

        try {
            MainActivity.channel?.invokeMethod("onBlockTriggered", mapOf(
                "packageName" to packageName,
                "reason" to reason
            ))
        } catch (_: Exception) {}
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this, 20,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Focus Blocker Active")
            .setContentText("Monitoring ${BlockerConfig.blockedPackages.size} apps")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Daily Usage Monitor",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setSound(null, null)
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun todayDateString(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return sdf.format(Date())
    }
}