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
    var isBreak = false
    var secondsRemaining = 25 * 60
    var totalDurationSeconds = 25 * 60
    var taskName = "Focus Block"
    var timerMode = "countdown" // "countdown" or "countup"
    
    private val handler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() {
            if (isRunning && !isPaused) {
                if (timerMode == "countup") {
                    // COUNT-UP: secondsRemaining = elapsed seconds (counts up from 0, never stops)
                    secondsRemaining++
                    updateUI()
                    notifyTick()
                } else {
                    // COUNTDOWN: secondsRemaining = remaining (counts down to 0)
                    if (secondsRemaining > 0) {
                        secondsRemaining--
                        notifyTick()
                    } else {
                        handleTimerComplete()
                    }
                    updateUI()
                }
                // Always update notification every tick for persistent display
                updateNotification()
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
                timerMode = intent.getStringExtra("timerMode") ?: "countdown"
                totalDurationSeconds = duration
                isBreak = intent.getBooleanExtra("isBreak", false)
                isRunning = true
                isPaused = false
                
                if (timerMode == "countup") {
                    secondsRemaining = 0  // start at 0, counts up (elapsed)
                } else {
                    secondsRemaining = duration  // start at duration, counts down
                }
                
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
            ACTION_SKIP_BREAK -> {
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
        // Count-up mode never auto-completes — user must stop manually
        if (timerMode == "countup") return
        
        if (!isBreak) {
            // Focus ended -> Start break
            isBreak = true
            secondsRemaining = 5 * 60
            taskName = "Break Time"
        } else {
            // Break ended -> Start focus
            isBreak = false
            secondsRemaining = totalDurationSeconds
            taskName = "Focus Block"
        }
        
        notifyStateChanged()
    }

    private fun stopPomodoro() {
        isRunning = false
        isPaused = false
        val elapsedSeconds = if (!isBreak) {
            if (timerMode == "countup") secondsRemaining  // elapsed = current value
            else (totalDurationSeconds - secondsRemaining)
        } else 0
        
        val arguments = mapOf(
            "status" to "STOPPED",
            "secondsRemaining" to secondsRemaining,
            "isBreak" to isBreak,
            "isPaused" to false,
            "taskName" to taskName,
            "elapsedSeconds" to elapsedSeconds
        )
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
        val elapsed = if (!isBreak) {
            if (timerMode == "countup") secondsRemaining else (totalDurationSeconds - secondsRemaining)
        } else 0
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
        
        expHeader.text = if (isBreak) "BREAK TIME" else if (timerMode == "countup") "∞ COUNT UP" else "FOCUSING"
        expTaskText.text = taskName
        expTimeText.text = timeStr
        
        // Progress bar: in count-up mode cap at 100 min for visual reference
        val totalSec = if (timerMode == "countup") 100 * 60 else if (isBreak) 5 * 60 else totalDurationSeconds
        expProgress.max = totalSec
        expProgress.progress = if (timerMode == "countup") (secondsRemaining % totalSec) else (totalSec - secondsRemaining)
        
        expPlayPauseBtn.text = if (isPaused) "PLAY" else "PAUSE"
    }

    // --- Custom Persistent Notification using RemoteViews ---
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

        // Build custom notification layout using RemoteViews
        val remoteViews = RemoteViews(packageName, R.layout.custom_pomodoro_notification)

        // --- Update text fields: secondsRemaining is always the display value ---
        // - countdown: secondsRemaining = remaining
        // - countup:   secondsRemaining = elapsed
        val minutes = secondsRemaining / 60
        val seconds = secondsRemaining % 60
        val timeStr = String.format("%02d:%02d", minutes, seconds)

        // Task title
        remoteViews.setTextViewText(R.id.task_title,
            if (isBreak) "BREAK TIME" else taskName.uppercase())

        // Timer text
        remoteViews.setTextViewText(R.id.timer_text, timeStr)

        // Timer color based on state
        if (isBreak) {
            remoteViews.setTextColor(R.id.timer_text, Color.parseColor("#4CAF50"))
        } else if (isPaused) {
            remoteViews.setTextColor(R.id.timer_text, Color.parseColor("#FF9800"))
        } else {
            remoteViews.setTextColor(R.id.timer_text, Color.parseColor("#FF5722"))
        }

        // --- Update icon based on play/pause state ---
        remoteViews.setImageViewResource(R.id.btn_play_pause,
            if (isPaused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause)

        // --- Set click intents ---
        remoteViews.setOnClickPendingIntent(R.id.btn_play_pause, playPausePendingIntent)
        remoteViews.setOnClickPendingIntent(R.id.btn_stop, stopPendingIntent)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setSilent(true)
            .setCustomContentView(remoteViews)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())

        return builder.build()
    }

    private fun updateNotification() {
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