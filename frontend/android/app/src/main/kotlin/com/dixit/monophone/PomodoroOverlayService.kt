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
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RemoteViews
import android.widget.TextView
import androidx.core.app.NotificationCompat

class PomodoroOverlayService : Service() {

    companion object {
        var instance: PomodoroOverlayService? = null
        
        const val ACTION_START = "com.dixit.monophone.START"
        const val ACTION_PLAY_PAUSE = "com.dixit.monophone.PLAY_PAUSE"
        const val ACTION_STOP = "com.dixit.monophone.STOP"
        
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
    var isBreak = false
    var secondsRemaining = 25 * 60
    var totalDurationSeconds = 25 * 60
    var taskName = "Focus Block"
    
    // Debounce: update notification every 5 ticks to avoid rapid-fire NotificationManager.notify() crashes
    private var notificationTickCounter = 0

    private val handler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() {
            if (isRunning && !isPaused) {
                if (secondsRemaining > 0) {
                    secondsRemaining--
                    notifyTick()
                } else {
                    handleTimerComplete()
                }
                updateUI()
                notificationTickCounter++
                if (notificationTickCounter >= 5) {
                    notificationTickCounter = 0
                    updateNotification()
                }
            }
            handler.postDelayed(this, 1000)
        }
    }

    // Views
    private var isExpanded = false
    private lateinit var shrunkView: LinearLayout
    private lateinit var expandedView: LinearLayout
    
    private lateinit var shrunkText: TextView
    
    private lateinit var expHeader: TextView
    private lateinit var expTaskText: TextView
    private lateinit var expProgress: ProgressBar
    private lateinit var expTimeText: TextView
    private lateinit var expPlayPauseBtn: Button
    private lateinit var expStopBtn: Button

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        setupViews()
        handler.post(tickRunnable)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                taskName = intent.getStringExtra("taskName") ?: "Focus Block"
                val duration = intent.getIntExtra("durationSeconds", 25 * 60)
                secondsRemaining = duration
                totalDurationSeconds = duration
                isBreak = intent.getBooleanExtra("isBreak", false)
                isRunning = true
                isPaused = false
                
                showOverlay()
                updateUI()
                startForeground(NOTIFICATION_ID, createNotification())
                notifyStateChanged()
            }
            ACTION_PLAY_PAUSE -> {
                isPaused = !isPaused
                updateUI()
                updateNotification()
                notifyStateChanged()
            }
            ACTION_STOP -> {
                stopPomodoro()
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

    private fun handleTimerComplete() {
        // Play click / sound / vibration notification
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Vibrator pattern or warning
        
        if (!isBreak) {
            // Focus ended -> Start break
            isBreak = true
            secondsRemaining = 5 * 60
            taskName = "Break Time"
        } else {
            // Break ended -> Start focus
            isBreak = false
            secondsRemaining = 25 * 60
            taskName = "Focus Block"
        }
        
        notifyStateChanged()
    }

    private fun stopPomodoro() {
        isRunning = false
        isPaused = false
        // Calculate elapsed focus seconds before destroying the service
        val elapsedSeconds = if (!isBreak) (totalDurationSeconds - secondsRemaining) else 0
        val arguments = mapOf(
            "status" to "STOPPED",
            "secondsRemaining" to secondsRemaining,
            "isBreak" to isBreak,
            "isPaused" to false,
            "taskName" to taskName,
            "elapsedSeconds" to elapsedSeconds
        )
        // Post to main looper to ensure Flutter channel call completes before stopSelf
        handler.post {
            try {
                MainActivity.channel?.invokeMethod("onPomodoroStateChanged", arguments)
            } catch (_: Exception) {}
            stopSelf()
        }
    }

    // --- Communication with Flutter ---
    private fun notifyTick() {
        val arguments = mapOf(
            "secondsRemaining" to secondsRemaining,
            "isBreak" to isBreak,
            "isPaused" to isPaused
        )
        try {
            MainActivity.channel?.invokeMethod("onPomodoroTick", arguments)
        } catch (_: Exception) {}
    }

    private fun notifyStateChanged(customStatus: String? = null) {
        val status = customStatus ?: if (isPaused) "PAUSED" else if (isBreak) "BREAK" else "FOCUSING"
        val elapsed = if (!isBreak) (totalDurationSeconds - secondsRemaining) else 0
        val arguments = mapOf(
            "status" to status,
            "secondsRemaining" to secondsRemaining,
            "isBreak" to isBreak,
            "isPaused" to isPaused,
            "taskName" to taskName,
            "elapsedSeconds" to elapsed
        )
        try {
            MainActivity.channel?.invokeMethod("onPomodoroStateChanged", arguments)
        } catch (_: Exception) {}
    }

    // --- UI Layout programmatically ---
    private fun setupViews() {
        val ctx = this
        overlayView = FrameLayout(ctx)
        
        val dp = resources.displayMetrics.density
        
        // 1. Shrunk View Layout
        shrunkView = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            val size = (65 * dp).toInt()
            layoutParams = FrameLayout.LayoutParams(size, size)
            background = createCircleDrawable(Color.parseColor("#80000000"), Color.WHITE, (2 * dp).toInt())
            
            shrunkText = TextView(ctx).apply {
                setTextColor(Color.WHITE)
                textSize = 11f
                typeface = Typeface.MONOSPACE
                gravity = Gravity.CENTER
            }
            addView(shrunkText)
        }
        
        // 2. Expanded View Layout
        expandedView = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val w = (220 * dp).toInt()
            val h = (150 * dp).toInt()
            layoutParams = FrameLayout.LayoutParams(w, h)
            background = createRoundedRectDrawable(Color.parseColor("#F2000000"), Color.WHITE, (2 * dp).toInt(), 8 * dp)
            setPadding((12 * dp).toInt(), (8 * dp).toInt(), (12 * dp).toInt(), (8 * dp).toInt())
            visibility = View.GONE
            
            // Header Row with status and shrink button
            val headerRow = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                gravity = Gravity.CENTER_VERTICAL
            }

            expHeader = TextView(ctx).apply {
                setTextColor(Color.GRAY)
                textSize = 10f
                typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                text = "POMODORO"
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            headerRow.addView(expHeader)

            val shrinkBtn = Button(ctx).apply {
                text = "-"
                textSize = 12f
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.TRANSPARENT)
                val btnSize = (24 * dp).toInt()
                layoutParams = LinearLayout.LayoutParams(btnSize, btnSize)
                setPadding(0, 0, 0, 0)
                setOnClickListener {
                    toggleExpandedState()
                }
            }
            headerRow.addView(shrinkBtn)
            addView(headerRow)
            
            // Task text
            expTaskText = TextView(ctx).apply {
                setTextColor(Color.WHITE)
                textSize = 13f
                typeface = Typeface.MONOSPACE
                setSingleLine()
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = taskName
                setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
            }
            addView(expTaskText)
            
            // Horizontal progress bar
            expProgress = ProgressBar(ctx, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = 25 * 60
                progress = 0
                progressDrawable = GradientDrawable().apply {
                    setColor(Color.parseColor("#33FFFFFF"))
                    cornerRadius = 2 * dp
                }
                setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
            }
            // Add progress bar styling programmatically or keep default
            addView(expProgress)
            
            // Time remaining text
            expTimeText = TextView(ctx).apply {
                setTextColor(Color.WHITE)
                textSize = 14f
                typeface = Typeface.MONOSPACE
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, (2 * dp).toInt(), 0, (6 * dp).toInt())
            }
            addView(expTimeText)
            
            // Row of Buttons
            val btnRow = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            }
            
            expPlayPauseBtn = Button(ctx).apply {
                text = "PAUSE"
                typeface = Typeface.MONOSPACE
                textSize = 10f
                setTextColor(Color.BLACK)
                setBackgroundColor(Color.WHITE)
                layoutParams = LinearLayout.LayoutParams(0, (32 * dp).toInt(), 1f).apply {
                    rightMargin = (4 * dp).toInt()
                }
                setOnClickListener {
                    isPaused = !isPaused
                    updateUI()
                    updateNotification()
                    notifyStateChanged()
                }
            }
            btnRow.addView(expPlayPauseBtn)
            
            expStopBtn = Button(ctx).apply {
                text = "STOP"
                typeface = Typeface.MONOSPACE
                textSize = 10f
                setTextColor(Color.WHITE)
                background = createRoundedRectDrawable(Color.TRANSPARENT, Color.WHITE, (1 * dp).toInt(), 2 * dp)
                layoutParams = LinearLayout.LayoutParams(0, (32 * dp).toInt(), 1f).apply {
                    leftMargin = (4 * dp).toInt()
                }
                setOnClickListener {
                    stopPomodoro()
                }
            }
            btnRow.addView(expStopBtn)
            
            addView(btnRow)
        }
        
        overlayView?.addView(shrunkView)
        overlayView?.addView(expandedView)
        
        // Window parameters
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
        
        // Dragging & Tapping gesture handling
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var touchStartTime = 0L
        
        val touchListener = View.OnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    touchStartTime = System.currentTimeMillis()
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
                MotionEvent.ACTION_UP -> {
                    val deltaX = event.rawX - initialTouchX
                    val deltaY = event.rawY - initialTouchY
                    val elapsed = System.currentTimeMillis() - touchStartTime
                    if (elapsed < 200 && (deltaX * deltaX + deltaY * deltaY) < 100) {
                        toggleExpandedState()
                    }
                    true
                }
                else -> false
            }
        }
        
        shrunkView.setOnTouchListener(touchListener)
        // Header is also draggable in expanded view
        expHeader.setOnTouchListener(touchListener)
    }

    private fun toggleExpandedState() {
        isExpanded = !isExpanded
        if (isExpanded) {
            shrunkView.visibility = View.GONE
            expandedView.visibility = View.VISIBLE
        } else {
            expandedView.visibility = View.GONE
            shrunkView.visibility = View.VISIBLE
        }
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

    private fun updateUI() {
        val minutes = secondsRemaining / 60
        val seconds = secondsRemaining % 60
        val timeStr = String.format("%02d:%02d", minutes, seconds)
        
        shrunkText.text = "[$timeStr]"
        
        expHeader.text = if (isBreak) "BREAK TIME" else "FOCUSING"
        expTaskText.text = taskName
        expTimeText.text = timeStr
        
        val totalSec = if (isBreak) 5 * 60 else 25 * 60
        expProgress.max = totalSec
        expProgress.progress = totalSec - secondsRemaining
        
        expPlayPauseBtn.text = if (isPaused) "PLAY" else "PAUSE"
    }

    // --- Notification Panel System ---
    private fun createNotification(): Notification {
        // ── Pending intents ───────────────────────────────────────────────────
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

        // ── State label ───────────────────────────────────────────────────────
        val stateLabel = when {
            isPaused -> "PAUSED"
            isBreak  -> "BREAK TIME"
            else     -> "FOCUS TO-DO"
        }
        val contentText = "$stateLabel  ·  ${taskName.uppercase()}".take(50)

        // ── Display the current remaining time in mm:ss format ────────────
        val timeText = formatTime(secondsRemaining)
        val contentTextWithTime = if (isPaused) {
            "Paused · $timeText"
        } else {
            "$timeText · $stateLabel"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(contentText)
            .setContentText(contentTextWithTime)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .addAction(android.R.drawable.ic_media_play,
                if (isPaused) "Resume" else "Pause", playPausePendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)

        return builder.build()
    }

    private fun formatTime(seconds: Int): String {
        return String.format("%02d:%02d", seconds / 60, seconds % 60)
    }

    private fun updateNotification() {
        // Guard: don't crash if the service is being torn down
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
                "Pomodoro Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    // Drawable utilities
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
