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
        private const val POLL_INTERVAL_MS = 2000L   // 2-second poll — enough for reliable foreground detection
        private const val FLUSH_INTERVAL_MS = 30_000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false

    /**
     * In-memory accumulator: packageName → MILLISECONDS accumulated since last DB flush.
     * Using ms internally avoids integer-truncation loss when poll interval < 1s.
     */
    private val pendingAccumulatorMs = HashMap<String, Long>()

    /** In-memory total accumulated today tracker (in SECONDS) to check limits instantly. */
    private val totalAccumulatedToday = HashMap<String, Int>()
    private var lastFlushedDate: String? = null
    private var activeForegroundApp: String? = null

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
        pendingAccumulatorMs.clear()

        loadInitialUsageData()
        initializeActiveForegroundApp()

        handler.post(pollRunnable)
        handler.post(flushRunnable)

        return START_STICKY
    }

    private fun loadInitialUsageData() {
        val date = todayDateString()
        val database = UsageDatabase.getInstance(this)
        val dao = database.dailyUsageDao()

        UsageDatabase.databaseWriteExecutor.execute {
            try {
                val allUsage = dao.getAllUsageForDate(date)
                synchronized(totalAccumulatedToday) {
                    totalAccumulatedToday.clear()
                    for (usage in allUsage) {
                        totalAccumulatedToday[usage.packageName] = usage.accumulatedSeconds
                    }
                    // Update shared tracker with initial values
                    UsageTracker.liveUsageSeconds = HashMap(totalAccumulatedToday)
                }
            } catch (_: Exception) {}
        }
    }

    private fun initializeActiveForegroundApp() {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 30000 // Query last 30 seconds
        try {
            val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
            val event = UsageEvents.Event()
            var lastForeground: String? = null
            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                    event.eventType == UsageEvents.Event.ACTIVITY_RESUMED
                ) {
                    lastForeground = event.packageName
                } else if (event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND ||
                           event.eventType == UsageEvents.Event.ACTIVITY_PAUSED
                ) {
                    if (lastForeground == event.packageName) {
                        lastForeground = null
                    }
                }
            }
            activeForegroundApp = lastForeground
        } catch (_: Exception) {}
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
        // Collect all packages that have any configured limit OR are in the blocked set.
        // Do NOT return early if the set is empty — limits may still be populated.
        val blockedPackages = BlockerConfig.blockedPackages
        val limitedPackages = BlockerConfig.dailyLimitsInMinutes.keys
        val monitoredPackages = blockedPackages + limitedPackages
        if (monitoredPackages.isEmpty()) return

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = SystemClock.elapsedRealtime()
        val realtimeNow = System.currentTimeMillis()
        val realtimeLastQuery = realtimeNow - (now - lastQueryTime)

        // Reset the date if midnight has passed
        val currentDate = todayDateString()
        if (lastFlushedDate != null && lastFlushedDate != currentDate) {
            synchronized(totalAccumulatedToday) { 
                totalAccumulatedToday.clear()
                UsageTracker.liveUsageSeconds = emptyMap()
            }
            pendingAccumulatorMs.clear()
        }
        lastFlushedDate = currentDate

        // Detect the current foreground app using MOVE_TO_FOREGROUND events.
        var detectedForeground: String? = activeForegroundApp

        try {
            val usageEvents = usageStatsManager.queryEvents(realtimeLastQuery, realtimeNow)
            val event = UsageEvents.Event()

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND,
                    UsageEvents.Event.ACTIVITY_RESUMED -> {
                        detectedForeground = event.packageName
                    }
                    UsageEvents.Event.MOVE_TO_BACKGROUND,
                    UsageEvents.Event.ACTIVITY_PAUSED -> {
                        if (detectedForeground == event.packageName) {
                            detectedForeground = null
                        }
                    }
                }
            }
        } catch (e: SecurityException) {
            stopSelf()
            return
        } catch (_: Exception) {}

        activeForegroundApp = detectedForeground

        // Accumulate elapsed time in MILLISECONDS to avoid integer-truncation loss.
        val elapsedMs = now - lastQueryTime
        lastQueryTime = now

        val foreground = activeForegroundApp
        if (foreground != null && monitoredPackages.contains(foreground) && elapsedMs > 0L) {
            pendingAccumulatorMs[foreground] =
                (pendingAccumulatorMs[foreground] ?: 0L) + elapsedMs

            // Convert accumulated ms → whole seconds and update in-memory total.
            val totalMs = pendingAccumulatorMs[foreground] ?: 0L
            val wholeSec = (totalMs / 1000L).toInt()
            if (wholeSec > 0) {
                synchronized(totalAccumulatedToday) {
                    // totalAccumulatedToday holds the DB baseline + live accumulated whole-seconds.
                    // We track how many seconds we have already added from pendingAccumulatorMs
                    // to avoid double-counting on each poll tick.
                    val prevLive = ((pendingAccumulatorMs[foreground]!! - elapsedMs) / 1000L).toInt()
                    val newlyAdded = wholeSec - prevLive
                    if (newlyAdded > 0) {
                        totalAccumulatedToday[foreground] =
                            (totalAccumulatedToday[foreground] ?: 0) + newlyAdded
                        
                        // Push live update to shared tracker
                        UsageTracker.updateLiveUsage(foreground, totalAccumulatedToday[foreground]!!)
                    }
                }
            }
        }

        // Check limits immediately against the accurate in-memory total.
        checkLimitExceeded()
    }

    // ── DB Flush ─────────────────────────────────────────────────────────────

    private fun flushAccumulatedUsage() {
        if (pendingAccumulatorMs.isEmpty()) return

        val date = todayDateString()
        val database = UsageDatabase.getInstance(this)
        val dao = database.dailyUsageDao()

        // Convert ms → whole seconds before writing to DB.
        val snapshot: Map<String, Int>
        synchronized(pendingAccumulatorMs) {
            snapshot = pendingAccumulatorMs.mapValues { (_, ms) -> (ms / 1000L).toInt() }
                .filter { (_, s) -> s > 0 }
            pendingAccumulatorMs.clear()
        }
        if (snapshot.isEmpty()) return

        UsageDatabase.databaseWriteExecutor.execute {
            for ((pkg, seconds) in snapshot) {
                try {
                    dao.incrementUsage(pkg, date, seconds)
                } catch (_: Exception) {}
            }
            // After flush, reload the DB totals into memory and re-check limits.
            try {
                val allUsage = dao.getAllUsageForDate(date)
                synchronized(totalAccumulatedToday) {
                    for (usage in allUsage) {
                        totalAccumulatedToday[usage.packageName] = usage.accumulatedSeconds
                    }
                    UsageTracker.liveUsageSeconds = HashMap(totalAccumulatedToday)
                }
            } catch (_: Exception) {}
            checkLimitExceededFromDb(dao, date)
        }
    }

    // ── Limit enforcement ────────────────────────────────────────────────────

    private fun checkLimitExceeded() {
        val limits = BlockerConfig.dailyLimitsInMinutes
        if (limits.isEmpty()) return

        val currentForeground = activeForegroundApp ?: return

        // Only enforce if the current foreground app has exceeded its limit.
        // (Limits for background apps are enforced in checkLimitExceededFromDb when
        //  the user actually opens those apps next time.)
        val limitMin = limits[currentForeground] ?: return
        val limitSec = limitMin * 60

        val accumulatedSec = synchronized(totalAccumulatedToday) {
            totalAccumulatedToday[currentForeground] ?: 0
        }

        if (accumulatedSec >= limitSec) {
            triggerBlockForPackage(currentForeground, "Daily usage limit exceeded")
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
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

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