package com.dixit.monophone

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * Full-screen blocking overlay that appears when a focus rule is triggered.
 *
 * Launched by any blocking engine (FocusAccessibilityService, DailyUsageMonitorService,
 * EmergencyUseTimerService, AppMonitoringService).  Uses SYSTEM_ALERT_WINDOW to
 * display a full-screen view that intercepts all touch input.
 *
 * On this overlay the user can:
 *   - Read the block reason and a motivational quote
 *   - Tap "Emergency Use (5 min)" to temporarily bypass the block
 *   - Tap "Return to Focus" to go back to the launcher
 */
class BlockerOverlayService : Service() {

    companion object {
        private const val CHANNEL_ID = "BlockerOverlayChannel"
        private const val NOTIFICATION_ID = 20
        private const val EMERGENCY_DURATION_MS = 5 * 60 * 1000L
        private const val TAG = "BlockerOverlay"
    }

    private lateinit var windowManager: WindowManager
    private var overlayView: FrameLayout? = null
    private lateinit var params: WindowManager.LayoutParams

    private var blockedPackage: String = ""
    private var blockReason: String = ""

    private val handler = Handler(Looper.getMainLooper())
    private var isShowing = false

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        blockedPackage = intent?.getStringExtra("blockedPackage") ?: ""
        blockReason = intent?.getStringExtra("blockReason") ?: "Focus rule triggered"

        // Don't show overlay if this package is in emergency-use mode.
        if (blockedPackage.isNotEmpty() &&
            TempAccessManager.isEmergencyUseActive &&
            TempAccessManager.tempAllowedPackage == blockedPackage
        ) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, createNotification())

        // Show the overlay after a brief delay to let the blocked Activity settle.
        handler.postDelayed({
            if (!isShowing) {
                showOverlay()
            }
        }, 200)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isShowing = false
        handler.removeCallbacksAndMessages(null)
        hideOverlay()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Overlay UI ───────────────────────────────────────────────────────────

    private fun showOverlay() {
        if (isShowing) return
        isShowing = true

        val ctx = this
        val dp = resources.displayMetrics.density

        overlayView = FrameLayout(ctx).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        // ── Container — vertical centered layout ─────────────────────────────
        val container = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ).apply {
                setMargins((28 * dp).toInt(), (48 * dp).toInt(), (28 * dp).toInt(), (48 * dp).toInt())
            }
        }
        overlayView?.addView(container)

        // ── Red dot / block indicator ────────────────────────────────────────
        val dot = View(ctx).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF4444"))
                setSize((12 * dp).toInt(), (12 * dp).toInt())
            }
            layoutParams = LinearLayout.LayoutParams(
                (12 * dp).toInt(),
                (12 * dp).toInt()
            ).apply {
                gravity = Gravity.CENTER
                bottomMargin = (20 * dp).toInt()
            }
        }
        container.addView(dot)

        // ── ACCESS BLOCKED header ────────────────────────────────────────────
        container.addView(TextView(ctx).apply {
            text = "ACCESS BLOCKED"
            textSize = 28f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            letterSpacing = 0.04f
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER; bottomMargin = (8 * dp).toInt() }
        })

        // ── Reason label ─────────────────────────────────────────────────────
        container.addView(TextView(ctx).apply {
            text = blockReason
            textSize = 13f
            typeface = Typeface.MONOSPACE
            setTextColor(Color.parseColor("#FF6666"))
            gravity = Gravity.CENTER
            setPadding((16 * dp).toInt(), 0, (16 * dp).toInt(), (32 * dp).toInt())
        })

        // ── Blocked app name with pill background ────────────────────────────
        val appLabel = try {
            val pm = ctx.packageManager
            val info = pm.getApplicationInfo(blockedPackage, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            blockedPackage
        }

        val appPill = TextView(ctx).apply {
            text = appLabel
            textSize = 16f
            typeface = Typeface.MONOSPACE
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding((24 * dp).toInt(), (12 * dp).toInt(), (24 * dp).toInt(), (12 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#22FFFFFF"))
                cornerRadius = (24 * dp)
                setStroke((1 * dp).toInt(), Color.parseColor("#44FFFFFF"))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER; bottomMargin = (40 * dp).toInt() }
        }
        container.addView(appPill)

        // ── Quote card ───────────────────────────────────────────────────────
        val quotes = arrayOf(
            "Deep work is the superpower of the 21st century.",
            "A distracted mind is a defeated mind.",
            "Disconnect to reconnect. Your future self is waiting.",
            "Focus on your North Star.",
            "Short-term distractions yield long-term regrets."
        )
        val quote = quotes[System.currentTimeMillis().toInt() % quotes.size]

        val quoteCard = FrameLayout(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = (48 * dp).toInt() }
            setPadding((20 * dp).toInt(), (20 * dp).toInt(), (20 * dp).toInt(), (20 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#0AFFFFFF"))
                cornerRadius = (12 * dp)
                setStroke((1 * dp).toInt(), Color.parseColor("#11FFFFFF"))
            }
            addView(TextView(ctx).apply {
                text = "\u201C$quote\u201D"
                textSize = 14f
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
                setTextColor(Color.parseColor("#99FFFFFF"))
                gravity = Gravity.CENTER
                setLineSpacing(0f, 1.4f)
            })
        }
        container.addView(quoteCard)

        // ── Spacer ───────────────────────────────────────────────────────────
        container.addView(LinearLayout(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        })

        // ── Emergency Use button ─────────────────────────────────────────────
        val emergencyBtn = Button(ctx).apply {
            text = "EMERGENCY USE (5 min)"
            textSize = 14f
            typeface = Typeface.MONOSPACE
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#33FF4444"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (52 * dp).toInt()
            ).apply { bottomMargin = (12 * dp).toInt() }
            setOnClickListener { onEmergencyUse() }
        }
        container.addView(emergencyBtn)

        // ── Return to Focus button ───────────────────────────────────────────
        val focusBtn = Button(ctx).apply {
            text = "RETURN TO FOCUS"
            textSize = 14f
            typeface = Typeface.MONOSPACE
            setTextColor(Color.BLACK)
            setBackgroundColor(Color.WHITE)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (52 * dp).toInt()
            ).apply { bottomMargin = (8 * dp).toInt() }
            setOnClickListener { onReturnToFocus() }
        }
        container.addView(focusBtn)

        // ── Window params: full screen, intercepts touch ─────────────────────
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.FILL }

        try {
            windowManager.addView(overlayView!!, params)
        } catch (e: Exception) {
            stopSelf()
        }
    }

    private fun hideOverlay() {
        if (overlayView != null && overlayView?.parent != null) {
            try {
                windowManager.removeView(overlayView)
            } catch (_: Exception) {}
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private fun onEmergencyUse() {
        if (blockedPackage.isEmpty()) {
            onReturnToFocus()
            return
        }

        TempAccessManager.startEmergencyUse(blockedPackage, EMERGENCY_DURATION_MS)

        val timerIntent = Intent(this, EmergencyUseTimerService::class.java).apply {
            putExtra("packageName", blockedPackage)
            putExtra("durationMs", EMERGENCY_DURATION_MS)
            putExtra("blockReason", blockReason)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(timerIntent)
        } else {
            startService(timerIntent)
        }

        try {
            MainActivity.channel?.invokeMethod("onEmergencyUseStarted", mapOf(
                "packageName" to blockedPackage,
                "durationMs" to EMERGENCY_DURATION_MS
            ))
        } catch (_: Exception) {}

        stopSelf()
    }

    private fun onReturnToFocus() {
        val homeIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(homeIntent)
        stopSelf()
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this, 21,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Blocked: $blockReason")
            .setContentText("Tap to return to focus")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Blocker Overlay",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { setSound(null, null) }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}