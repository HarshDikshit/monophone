package com.dixit.monophone

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat

/**
 * GrayscaleOverlayService
 * ──────────────────────────────────────────────────────────────────────────────
 * Draws a full-screen transparent View over ALL apps (including YouTube,
 * Instagram, etc.) using SYSTEM_ALERT_WINDOW.  The view applies a grayscale
 * ColorMatrixColorFilter via hardware-layer paint, which desaturates every
 * pixel beneath it — making the entire display appear monochrome.
 *
 * This approach works without root or WRITE_SECURE_SETTINGS permission.
 *
 * Lifecycle:
 *  - Start: startForegroundService(Intent(ctx, GrayscaleOverlayService::class.java))
 *  - Stop:  stopService(Intent(ctx, GrayscaleOverlayService::class.java))
 *           OR send action "STOP" via startService(...)
 *
 * Requires:
 *  - android.permission.SYSTEM_ALERT_WINDOW (already granted)
 *  - android.permission.FOREGROUND_SERVICE
 */
class GrayscaleOverlayService : Service() {

    companion object {
        private const val TAG = "GrayscaleOverlay"
        private const val CHANNEL_ID = "GrayscaleOverlayChannel"
        private const val NOTIFICATION_ID = 77
        const val ACTION_STOP = "com.dixit.monophone.GRAYSCALE_STOP"

        /** Singleton flag so Flutter can query state without IPC. */
        var isRunning = false
            private set
    }

    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        showOverlay()
        isRunning = true
        Log.i(TAG, "Grayscale overlay started.")
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        removeOverlay()
        Log.i(TAG, "Grayscale overlay stopped.")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Overlay ───────────────────────────────────────────────────────────────

    private fun showOverlay() {
        if (overlayView != null) return // already showing

        // Grayscale color matrix — luminance-preserving desaturation.
        val grayscale = ColorMatrix().apply { setSaturation(0f) }
        val paint = Paint().apply { colorFilter = ColorMatrixColorFilter(grayscale) }

        val view = object : View(this) {
            init {
                // Hardware layer applies the paint (ColorMatrixColorFilter) to
                // everything rendered beneath this view in the compositor.
                setLayerType(LAYER_TYPE_HARDWARE, paint)
            }
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            // NOT_TOUCHABLE → all touches pass through to apps beneath.
            // NOT_FOCUSABLE → keyboard / IME behaviour unaffected.
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        )

        try {
            windowManager.addView(view, params)
            overlayView = view
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add grayscale overlay: ${e.message}")
            stopSelf()
        }
    }

    private fun removeOverlay() {
        overlayView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
            overlayView = null
        }
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun buildNotification(): Notification {
        val stopIntent = PendingIntent.getService(
            this, 78,
            Intent(this, GrayscaleOverlayService::class.java).apply { action = ACTION_STOP },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Monochrome Mode Active")
            .setContentText("Display is grayscale. Tap to disable.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disable", stopIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Monochrome Mode",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Grayscale overlay active across all apps"
                setSound(null, null)
                setShowBadge(false)
            }
            (getSystemService(NotificationManager::class.java))
                .createNotificationChannel(channel)
        }
    }
}
