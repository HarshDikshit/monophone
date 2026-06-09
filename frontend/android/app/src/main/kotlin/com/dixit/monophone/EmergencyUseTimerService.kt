package com.dixit.monophone

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/**
 * ──────────────────────────────────────────────────────────────────────────────
 * EmergencyUseTimerService — Strict 5-minute emergency-use countdown.
 * ──────────────────────────────────────────────────────────────────────────────
 *
 * This service replaces the simplified [DistractionTimerService] and enforces
 * the strict emergency-use protocol:
 *
 *   1. On start, sets [TempAccessManager.startEmergencyUse] to exempt the
 *      target package from all blocking checks.
 *   2. Runs a precise 1-second-tick countdown for the full duration (5 minutes).
 *   3. Shows a persistent foreground notification with remaining time.
 *   4. When the countdown reaches ZERO:
 *      a. Clears [TempAccessManager.clearEmergencyUse] to re-enable blocking.
 *      b. Launches [BlockerOverlayService] to re-lock the screen.
 *      c. Sends GLOBAL_ACTION_HOME to bring the launcher to the foreground.
 *      d. Calls stopSelf().
 *
 * ── Key Behaviour ──
 * • The service is START_NOT_STICKY — once it stops, it stops for good.
 * • The notification includes a "Cancel Emergency" action that allows the user
 *   to voluntarily end the emergency window early (which also re-locks).
 * • The timer uses SystemClock.elapsedRealtime() for drift-free counting.
 * ──────────────────────────────────────────────────────────────────────────────
 */
class EmergencyUseTimerService : Service() {

    companion object {
        private const val TAG = "EmergencyUseTimer"
        private const val CHANNEL_ID = "EmergencyUseTimerChannel"
        private const val NOTIFICATION_ID = 30
        private const val TICK_INTERVAL_MS = 1000L       // 1 second
    }

    private var targetPackage: String = ""
    private var totalDurationMs: Long = 5 * 60 * 1000L   // default 5 min
    private var remainingMs: Long = 5 * 60 * 1000L
    private var blockReason: String = ""
    private var expiryRealtimeMs: Long = 0L               // SystemClock.elapsedRealtime() + totalDurationMs

    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return

            val now = android.os.SystemClock.elapsedRealtime()
            remainingMs = expiryRealtimeMs - now

            if (remainingMs <= 0) {
                // ── EXPIRED — Re-lock immediately ───────────────────────────
                onTimerExpired()
                return
            }

            // Update notification with remaining time.
            updateNotification()

            // Send tick to Flutter for UI display.
            notifyFlutterTick()

            handler.postDelayed(this, TICK_INTERVAL_MS)
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        targetPackage = intent?.getStringExtra("packageName") ?: ""
        totalDurationMs = intent?.getLongExtra("durationMs", 5 * 60 * 1000L) ?: 5 * 60 * 1000L
        blockReason = intent?.getStringExtra("blockReason") ?: "Emergency use"

        if (targetPackage.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }

        // Initialise the expiry timestamp.
        expiryRealtimeMs = android.os.SystemClock.elapsedRealtime() + totalDurationMs
        remainingMs = totalDurationMs
        isRunning = true

        // Start foreground notification.
        startForeground(NOTIFICATION_ID, createNotification())

        // Start ticking.
        handler.post(tickRunnable)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(tickRunnable)
        TempAccessManager.clearEmergencyUse()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Timer expiration ─────────────────────────────────────────────────────

    /**
     * Called when the countdown reaches zero.  Enforces the re-lock:
     *
     * 1. Clear the emergency-use exemption so the app is blocked again.
     * 2. Launch [BlockerOverlayService] to show the block screen.
     * 3. Send GLOBAL_ACTION_HOME via accessibility service (if available) or
     *    launch the launcher activity directly.
     * 4. Notify Flutter.
     * 5. Stop this service.
     */
    private fun onTimerExpired() {
        isRunning = false
        TempAccessManager.clearEmergencyUse()

        // Notify Flutter that the emergency window has expired.
        try {
            MainActivity.channel?.invokeMethod("onEmergencyUseExpired", mapOf(
                "packageName" to targetPackage
            ))
        } catch (_: Exception) {}

        // ── Re-launch blocker overlay ────────────────────────────────────────
        val overlayIntent = Intent(this, BlockerOverlayService::class.java).apply {
            putExtra("blockedPackage", targetPackage)
            putExtra("blockReason", "Emergency use expired — $blockReason")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(overlayIntent)
        } else {
            startService(overlayIntent)
        }

        // ── Return to home ───────────────────────────────────────────────────
        try {
            val accessibilityService = FocusAccessibilityService.instance
            if (accessibilityService != null) {
                // Use the accessibility service to perform GLOBAL_ACTION_HOME,
                // which is more reliable than launching an Intent.
                accessibilityService.performGlobalAction(
                    android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME
                )
            } else {
                // Fallback: launch the launcher activity.
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(homeIntent)
            }
        } catch (_: Exception) {}

        // ── Safety: repeat home launch 3 times to override app resumption ────
        val safetyHandler = Handler(Looper.getMainLooper())
        var safetyCount = 0
        val safetyRunnable = object : Runnable {
            override fun run() {
                if (safetyCount < 3) {
                    try {
                        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        }
                        startActivity(homeIntent)
                    } catch (_: Exception) {}
                    safetyCount++
                    safetyHandler.postDelayed(this, 500)
                }
            }
        }
        safetyHandler.post(safetyRunnable)

        // Stop the service.
        stopSelf()
    }

    // ── Cancel emergency early (called from notification action) ─────────────

    /**
     * Allow the user to cancel the emergency window early, which also
     * triggers the same re-lock behaviour as expiration.
     */
    private fun cancelEmergency() {
        onTimerExpired()
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotification(): Notification {
        val minutes = remainingMs / 60000
        val seconds = (remainingMs % 60000) / 1000
        val timeStr = String.format("%02d:%02d", minutes, seconds)

        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        // Cancel action.
        val cancelIntent = PendingIntent.getService(
            this, 31,
            Intent(this, EmergencyUseTimerService::class.java).apply {
                action = "CANCEL_EMERGENCY"
            },
            immutableFlag
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Emergency Use Active")
            .setContentText("$timeStr remaining for ${targetPackage}")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelIntent)
            .build()
    }

    private fun updateNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, createNotification())
        } catch (_: Exception) {}
    }

    private fun notifyFlutterTick() {
        try {
            MainActivity.channel?.invokeMethod("onEmergencyUseTick", mapOf(
                "packageName" to targetPackage,
                "remainingMs" to remainingMs
            ))
        } catch (_: Exception) {}
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Emergency Use Timer",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setSound(null, null)
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}