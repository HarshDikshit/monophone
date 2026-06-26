package com.dixit.monophone

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.RemoteViews
import android.widget.TextView
import androidx.core.app.NotificationCompat

class PomodoroOverlayService : Service() {

    companion object {
        var instance: PomodoroOverlayService? = null
        
        const val ACTION_START = "com.dixit.monophone.START"
        const val ACTION_PLAY_PAUSE = "com.dixit.monophone.PLAY_PAUSE"
        const val ACTION_STOP = "com.dixit.monophone.STOP"
        const val ACTION_SKIP_BREAK = "com.dixit.monophone.SKIP_BREAK"
        
        const val STATE_FOCUS = "FOCUS"
        const val STATE_BREAK = "BREAK"
    }

    private val CHANNEL_ID = "PomodoroOverlayServiceChannel"
    private val NOTIFICATION_ID = 3

    private lateinit var windowManager: WindowManager
    private var overlayView: FrameLayout? = null
    private lateinit var params: WindowManager.LayoutParams

    // Timer state
    var isRunning = false
    var isPaused = false
    var elapsedSeconds = 0
    var taskName = "Focus Block"
    var taskId: String? = null
    
    private val handler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() {
            if (isRunning && !isPaused) {
                elapsedSeconds++
                notifyTick()
                updateExpandedUI()
                updateNotification()
            }
            handler.postDelayed(this, 1000)
        }
    }

    // Expanded pill views
    private lateinit var pillContainer: FrameLayout
    private lateinit var expandedRoot: LinearLayout
    private lateinit var playPauseBtn: ImageButton
    private lateinit var stopBtn: ImageButton
    private lateinit var collapseBtn: ImageButton
    private lateinit var timerText: TextView
    private lateinit var subtitleText: TextView

    // Collapsed (shrunk) view — thin tab on left edge
    private lateinit var collapsedRoot: LinearLayout
    private lateinit var expandBtn: ImageButton
    private var isCollapsed = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        setupViews()
        handler.post(tickRunnable)
    }

    var autoStartBreak = true
    var autoStartNextPomodoro = true
    var soundEnabled = true
    var vibrationEnabled = true

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                taskName = intent.getStringExtra("taskName") ?: "Focus Block"
                taskId = intent.getStringExtra("taskId")
                val startAt = intent.getIntExtra("elapsedSeconds", 0)
                soundEnabled = intent.getBooleanExtra("soundEnabled", true)
                vibrationEnabled = intent.getBooleanExtra("vibrationEnabled", true)
                isRunning = true
                isPaused = false
                isCollapsed = false
                elapsedSeconds = startAt
                
                showOverlay()
                updateExpandedUI()
                startForeground(NOTIFICATION_ID, createNotification())
                notifyStateChanged()
            }
            ACTION_PLAY_PAUSE -> {
                isPaused = !isPaused
                updateExpandedUI()
                updateNotification()
                notifyStateChanged()
            }
            ACTION_STOP -> {
                stopFocusTimer(manual = true)
            }
            ACTION_SKIP_BREAK -> {
                stopFocusTimer(manual = true)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        isPaused = false
        handler.removeCallbacks(tickRunnable)
        hideOverlay()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private var mediaPlayer: MediaPlayer? = null

    private fun playAlertSound() {
        if (!soundEnabled) return
        try {
            mediaPlayer?.release()
            val afd = applicationContext.resources.openRawResourceFd(R.raw.alert)
            mediaPlayer = MediaPlayer().apply {
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .build()
                )
                isLooping = false
                prepare()
                start()
                handler.postDelayed({
                    try {
                        if (isPlaying) { stop(); release() }
                    } catch (_: Exception) {}
                }, 3000)
                setOnCompletionListener { release() }
            }
        } catch (_: Exception) {}
    }

    private fun vibrate() {
        if (!vibrationEnabled) return
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION") vibrator.vibrate(500)
            }
        } catch (_: Exception) {}
    }

    private fun handleTimerComplete() {}

    private fun stopFocusTimer(manual: Boolean) {
        isRunning = false
        isPaused = false
        
        val arguments = mapOf(
            "status" to "STOPPED",
            "elapsedSeconds" to elapsedSeconds,
            "taskName" to taskName,
            "taskId" to taskId,
            "manual" to manual
        )
        handler.post {
            try {
                MainActivity.channel?.invokeMethod("onFocusStateChanged", arguments)
            } catch (_: Exception) {}
            stopSelf()
        }
    }

    // --- Communication with Flutter ---
    private fun notifyTick() {
        val arguments = mapOf(
            "elapsedSeconds" to elapsedSeconds,
            "isPaused" to isPaused
        )
        try {
            MainActivity.channel?.invokeMethod("onFocusTick", arguments)
        } catch (_: Exception) {}
    }

    private fun notifyStateChanged() {
        val status = if (isPaused) "PAUSED" else "FOCUSING"
        val arguments = mapOf(
            "status" to status,
            "elapsedSeconds" to elapsedSeconds,
            "isPaused" to isPaused,
            "taskName" to taskName,
            "taskId" to taskId
        )
        try {
            MainActivity.channel?.invokeMethod("onFocusStateChanged", arguments)
        } catch (_: Exception) {}
    }

    // ============================================================
    //  UI — Two-State: Expanded Pill  ||  Collapsed Tab (left edge)
    // ============================================================
    private fun setupViews() {
        val ctx = this
        overlayView = FrameLayout(ctx)
        val dp = resources.displayMetrics.density

        // ── Expanded Pill ──
        expandedRoot = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val pillWidth = (260 * dp).toInt()  // reduced from 300 to 260
            val pillHeight = (52 * dp).toInt()
            layoutParams = FrameLayout.LayoutParams(pillWidth, pillHeight)
            background = createRoundedRectDrawable(
                Color.parseColor("#FF000000"),
                Color.parseColor("#3DFFFFFF"),
                (1 * dp).toInt(),
                (18 * dp)
            )
            setPadding((6 * dp).toInt(), 0, (4 * dp).toInt(), 0)
            visibility = View.VISIBLE
        }

        // Row contents
        // Left: Play/Pause
        playPauseBtn = ImageButton(ctx).apply {
            val btnSize = (34 * dp).toInt()  // slightly smaller
            layoutParams = LinearLayout.LayoutParams(btnSize, btnSize).apply {
                rightMargin = (4 * dp).toInt()
            }
            background = createCircleDrawable(
                Color.parseColor("#1AFFFFFF"),
                Color.parseColor("#40FFFFFF"),
                (1 * dp).toInt()
            )
            scaleType = android.widget.ImageView.ScaleType.CENTER
            setPadding(0, 0, 0, 0)
            setImageDrawable(createPlayDrawable(Color.WHITE, (20 * dp()).toInt()))
            setOnClickListener {
                isPaused = !isPaused
                updateExpandedUI()
                updateNotification()
                notifyStateChanged()
            }
        }
        expandedRoot.addView(playPauseBtn)

        // Middle: Timer Column (task name above, timer + subtitle below)
        val timerColumn = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            gravity = Gravity.CENTER_VERTICAL
        }
        // Task name label — truncated to 8 chars with "..."
        val taskLabel = TextView(ctx).apply {
            setTextColor(Color.parseColor("#AAFFFFFF"))  // slightly dimmer white
            textSize = 9f
            typeface = Typeface.MONOSPACE
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            // Store reference for dynamic updates
            setTag("taskLabel")
        }
        timerColumn.addView(taskLabel)

        timerText = TextView(ctx).apply {
            setTextColor(Color.WHITE)
            textSize = 15f  // slightly smaller
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            text = "00:00"
        }
        timerColumn.addView(timerText)
        subtitleText = TextView(ctx).apply {
            setTextColor(Color.parseColor("#8AFFFFFF"))
            textSize = 8f
            typeface = Typeface.MONOSPACE
            text = "Time focused"
        }
        timerColumn.addView(subtitleText)
        expandedRoot.addView(timerColumn)

        // Stop button (square with rounded corners, white "■" stop icon)
        stopBtn = ImageButton(ctx).apply {
            val btnSize = (32 * dp).toInt()
            layoutParams = LinearLayout.LayoutParams(btnSize, btnSize).apply {
                leftMargin = (4 * dp).toInt()
                rightMargin = (4 * dp).toInt()
            }
            background = createRoundedRectDrawable(
                Color.parseColor("#1AFFFFFF"),
                Color.parseColor("#40FFFFFF"),
                (1 * dp).toInt(),
                (6 * dp)
            )
            scaleType = android.widget.ImageView.ScaleType.CENTER
            setPadding(0, 0, 0, 0)
            setImageDrawable(createStopDrawable(Color.WHITE, (18 * dp()).toInt()))
            setOnClickListener {
                stopFocusTimer(manual = true)
            }
        }
        expandedRoot.addView(stopBtn)

        // Collapse button (thin "—" minimize icon)
        collapseBtn = ImageButton(ctx).apply {
            val btnSize = (26 * dp).toInt()
            layoutParams = LinearLayout.LayoutParams(btnSize, btnSize).apply {
                leftMargin = (2 * dp).toInt()
            }
            background = null
            scaleType = android.widget.ImageView.ScaleType.CENTER
            setPadding(0, 0, 0, 0)
            setImageDrawable(createMinimizeDrawable(Color.WHITE, (16 * dp()).toInt()))
            setOnClickListener {
                collapseOverlay()
            }
        }
        expandedRoot.addView(collapseBtn)

        // ── Collapsed View (thin tab on left edge with ">" arrow) ──
        collapsedRoot = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            val tabW = (28 * dp).toInt()
            val tabH = (60 * dp).toInt()
            layoutParams = FrameLayout.LayoutParams(tabW, tabH)
            background = createRoundedRectDrawable(
                Color.parseColor("#FF000000"),
                Color.parseColor("#3DFFFFFF"),
                (1 * dp).toInt(),
                (0 * dp) // no rounded corners on left edge — flush against screen edge
            ).apply {
                // Round only the right corners so it sticks flush to left edge
                cornerRadii = floatArrayOf(0f, 0f, (10 * dp), (10 * dp), (10 * dp), (10 * dp), 0f, 0f)
            }
            visibility = View.GONE
            setPadding((4 * dp).toInt(), (6 * dp).toInt(), (2 * dp).toInt(), (6 * dp).toInt())
        }
        expandBtn = ImageButton(ctx).apply {
            val btnSize = (22 * dp).toInt()
            layoutParams = LinearLayout.LayoutParams(btnSize, btnSize)
            background = null
            scaleType = android.widget.ImageView.ScaleType.CENTER
            setPadding(0, 0, 0, 0)
            setImageDrawable(createExpandArrowDrawable(Color.WHITE, (18 * dp()).toInt()))
            setOnClickListener {
                expandOverlay()
            }
        }
        collapsedRoot.addView(expandBtn)

        // Add both views to overlay
        overlayView?.addView(expandedRoot)
        overlayView?.addView(collapsedRoot)

        // Window params
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 150
        }

        // Dragging — shared for both states
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f

        val dragListener = View.OnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - initialTouchX
                    val deltaY = event.rawY - initialTouchY
                    params.x = initialX + deltaX.toInt()
                    params.y = initialY + deltaY.toInt()
                    overlayView?.let { windowManager.updateViewLayout(it, params) }
                    true
                }
                MotionEvent.ACTION_UP -> true
                else -> false
            }
        }
        expandedRoot.setOnTouchListener(dragListener)
        collapsedRoot.setOnTouchListener(dragListener)
    }

    private fun collapseOverlay() {
        isCollapsed = true
        expandedRoot.visibility = View.GONE
        collapsedRoot.visibility = View.VISIBLE
        // Snap to left edge
        params.x = 0
        overlayView?.let { windowManager.updateViewLayout(it, params) }
    }

    private fun expandOverlay() {
        isCollapsed = false
        collapsedRoot.visibility = View.GONE
        expandedRoot.visibility = View.VISIBLE
        updateExpandedUI()
        // Keep X position from collapsed state (snapped to left)
        params.x = 0
        overlayView?.let { windowManager.updateViewLayout(it, params) }
    }

    private fun showOverlay() {
        if (overlayView != null && overlayView?.parent == null) {
            windowManager.addView(overlayView, params)
        }
    }

    private fun hideOverlay() {
        if (overlayView != null && overlayView?.parent != null) {
            windowManager.removeView(overlayView)
        }
    }

    fun updateExpandedUI() {
        val hours = elapsedSeconds / 3600
        val minutes = (elapsedSeconds % 3600) / 60
        val secs = elapsedSeconds % 60
        val timeStr = if (hours > 0) String.format("%02d:%02d:%02d", hours, minutes, secs)
                      else String.format("%02d:%02d", minutes, secs)
        
        timerText.text = timeStr
        subtitleText.text = if (isPaused) "Paused" else "Time focused"
        
        // Update task label — truncate to 8 chars with "..."
        val taskLabel = expandedRoot.findViewWithTag<TextView>("taskLabel")
        if (taskLabel != null) {
            val fullName = if (isPaused) taskName else taskName
            taskLabel.text = if (fullName.length > 8) fullName.substring(0, 8) + "..." else fullName
        }
        
        // Replace the drawable properly — center the icon
        playPauseBtn.setImageDrawable(null)
        if (isPaused) {
            playPauseBtn.setImageDrawable(createPlayDrawable(Color.WHITE, (22 * dp()).toInt()))
        } else {
            playPauseBtn.setImageDrawable(createPauseDrawable(Color.WHITE, (22 * dp()).toInt()))
        }
    }

    private fun dp(): Float = resources.displayMetrics.density

    // ============================================================
    //  Custom Vector Drawables (Canvas-drawn)
    // ============================================================

    private fun createPlayDrawable(color: Int, size: Int): android.graphics.drawable.Drawable {
        return object : android.graphics.drawable.Drawable() {
            override fun draw(canvas: android.graphics.Canvas) {
                val cx = bounds.exactCenterX()
                val cy = bounds.exactCenterY()
                val s = Math.min(bounds.width(), bounds.height()) * 0.45f
                val path = android.graphics.Path().apply {
                    moveTo(cx - s * 0.35f, cy - s * 0.55f)
                    lineTo(cx - s * 0.35f, cy + s * 0.55f)
                    lineTo(cx + s * 0.6f, cy)
                    close()
                }
                val p = android.graphics.Paint().apply {
                    this.color = color
                    isAntiAlias = true
                    style = android.graphics.Paint.Style.FILL
                }
                canvas.drawPath(path, p)
            }
            override fun setAlpha(alpha: Int) {}
            override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
            @Deprecated("Deprecated in Java")
            override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    private fun createPauseDrawable(color: Int, size: Int): android.graphics.drawable.Drawable {
        return object : android.graphics.drawable.Drawable() {
            override fun draw(canvas: android.graphics.Canvas) {
                val cx = bounds.exactCenterX()
                val cy = bounds.exactCenterY()
                val s = Math.min(bounds.width(), bounds.height()) * 0.40f
                val barW = s * 0.28f
                val gap = s * 0.15f
                val halfH = s * 0.5f
                val p = android.graphics.Paint().apply {
                    this.color = color
                    isAntiAlias = true
                    style = android.graphics.Paint.Style.FILL
                }
                val r = 2f
                // Left bar
                canvas.drawRoundRect(
                    cx - barW - gap / 2f, cy - halfH,
                    cx - gap / 2f, cy + halfH, r, r, p
                )
                // Right bar
                canvas.drawRoundRect(
                    cx + gap / 2f, cy - halfH,
                    cx + barW + gap / 2f, cy + halfH, r, r, p
                )
            }
            override fun setAlpha(alpha: Int) {}
            override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
            @Deprecated("Deprecated in Java")
            override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    private fun createStopDrawable(color: Int, size: Int): android.graphics.drawable.Drawable {
        return object : android.graphics.drawable.Drawable() {
            override fun draw(canvas: android.graphics.Canvas) {
                val cx = bounds.exactCenterX()
                val cy = bounds.exactCenterY()
                val s = Math.min(bounds.width(), bounds.height()) * 0.35f
                val p = android.graphics.Paint().apply {
                    this.color = color
                    isAntiAlias = true
                    style = android.graphics.Paint.Style.FILL
                }
                canvas.drawRoundRect(cx - s, cy - s, cx + s, cy + s, 3f, 3f, p)
            }
            override fun setAlpha(alpha: Int) {}
            override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
            @Deprecated("Deprecated in Java")
            override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    private fun createMinimizeDrawable(color: Int, size: Int): android.graphics.drawable.Drawable {
        return object : android.graphics.drawable.Drawable() {
            override fun draw(canvas: android.graphics.Canvas) {
                val cx = bounds.exactCenterX()
                val cy = bounds.exactCenterY()
                val w = Math.min(bounds.width(), bounds.height()) * 0.50f
                val p = android.graphics.Paint().apply {
                    this.color = color
                    isAntiAlias = true
                    strokeWidth = 2.5f
                    style = android.graphics.Paint.Style.STROKE
                    strokeCap = android.graphics.Paint.Cap.ROUND
                }
                canvas.drawLine(cx - w, cy, cx + w, cy, p)
            }
            override fun setAlpha(alpha: Int) {}
            override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
            @Deprecated("Deprecated in Java")
            override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    private fun createExpandArrowDrawable(color: Int, size: Int): android.graphics.drawable.Drawable {
        return object : android.graphics.drawable.Drawable() {
            override fun draw(canvas: android.graphics.Canvas) {
                val cx = bounds.exactCenterX()
                val cy = bounds.exactCenterY()
                val s = Math.min(bounds.width(), bounds.height()) * 0.35f
                val p = android.graphics.Paint().apply {
                    this.color = color
                    isAntiAlias = true
                    strokeWidth = 2.5f
                    style = android.graphics.Paint.Style.STROKE
                    strokeCap = android.graphics.Paint.Cap.ROUND
                }
                // ">" arrow pointing right
                canvas.drawLine(cx - s * 0.3f, cy - s * 0.6f, cx + s * 0.5f, cy, p)
                canvas.drawLine(cx - s * 0.3f, cy + s * 0.6f, cx + s * 0.5f, cy, p)
            }
            override fun setAlpha(alpha: Int) {}
            override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
            @Deprecated("Deprecated in Java")
            override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    // --- Notification ---
    private fun createNotification(): Notification {
        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        val contentIntent = PendingIntent.getActivity(
            this, 10,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }, immutableFlag
        )

        val playPausePendingIntent = PendingIntent.getService(
            this, 11,
            Intent(this, PomodoroOverlayService::class.java).apply { action = ACTION_PLAY_PAUSE },
            immutableFlag
        )

        val stopPendingIntent = PendingIntent.getService(
            this, 12,
            Intent(this, PomodoroOverlayService::class.java).apply { action = ACTION_STOP },
            immutableFlag
        )

        val remoteViews = RemoteViews(packageName, R.layout.custom_pomodoro_notification)
        val bigRemoteViews = RemoteViews(packageName, R.layout.custom_pomodoro_notification_expanded)

        val hours = elapsedSeconds / 3600
        val minutes = (elapsedSeconds % 3600) / 60
        val seconds = elapsedSeconds % 60
        val timeStr = if (hours > 0) String.format("%02d:%02d:%02d", hours, minutes, seconds)
                      else String.format("%02d:%02d", minutes, seconds)

        val statusText = if (isPaused) "PAUSED" else "FOCUSING"
        val displayTaskName = taskName

        remoteViews.setTextViewText(R.id.task_title, displayTaskName.uppercase())
        bigRemoteViews.setTextViewText(R.id.task_title, displayTaskName.uppercase())
        try {
            bigRemoteViews.setTextViewText(resources.getIdentifier("status_text", "id", packageName), statusText)
        } catch (_: Exception) {}

        remoteViews.setTextViewText(R.id.timer_text, timeStr)
        bigRemoteViews.setTextViewText(R.id.timer_text, timeStr)

        val timerColor = when {
            isPaused -> Color.parseColor("#FF9800")
            else -> Color.parseColor("#FF5722")
        }
        remoteViews.setTextColor(R.id.timer_text, timerColor)
        bigRemoteViews.setTextColor(R.id.timer_text, timerColor)

        val playPauseIcon = if (isPaused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause
        remoteViews.setImageViewResource(R.id.btn_play_pause, playPauseIcon)
        bigRemoteViews.setImageViewResource(R.id.btn_play_pause, playPauseIcon)

        remoteViews.setOnClickPendingIntent(R.id.btn_play_pause, playPausePendingIntent)
        remoteViews.setOnClickPendingIntent(R.id.btn_stop, stopPendingIntent)
        bigRemoteViews.setOnClickPendingIntent(R.id.btn_play_pause, playPausePendingIntent)
        bigRemoteViews.setOnClickPendingIntent(R.id.btn_stop, stopPendingIntent)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_logo)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setSilent(true)
            .setCustomContentView(remoteViews)
            .setCustomBigContentView(bigRemoteViews)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .build()
    }

    fun updateNotification() {
        if (!isRunning && !isPaused) return
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, createNotification())
        } catch (_: Exception) {}
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Pomodoro Timer",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Persistent Pomodoro timer notification"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createCircleDrawable(color: Int, strokeColor: Int, strokeWidth: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(strokeWidth, strokeColor)
        }
    }

    private fun createRoundedRectDrawable(color: Int, strokeColor: Int, strokeWidth: Int, cornerRadius: Float): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            setStroke(strokeWidth, strokeColor)
            setCornerRadius(cornerRadius)
        }
    }
}