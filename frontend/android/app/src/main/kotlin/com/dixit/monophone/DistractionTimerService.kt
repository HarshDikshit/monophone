package com.dixit.monophone //  Update to your new package name
import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class DistractionTimerService : Service() {

    private val CHANNEL_ID = "DistractionTimerServiceChannel"
    private val NOTIFICATION_ID = 2
    private var durationSeconds = 0
    private val handler = Handler(Looper.getMainLooper())
    private var targetPackage: String = ""

    private val countdownRunnable = object : Runnable {
        override fun run() {
            if (durationSeconds > 0) {
                durationSeconds--
                updateNotification()
                handler.postDelayed(this, 1000)
            } else {
                // Time's up! Force return to launcher
                forceReturnToLauncher()
                stopSelf()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val newTargetPackage = intent?.getStringExtra("packageName") ?: ""
        val newDurationSeconds = intent?.getIntExtra("durationSeconds", 300) ?: 300

        targetPackage = newTargetPackage
        durationSeconds = newDurationSeconds
        TempAccessManager.tempAllowedPackage = targetPackage

        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)

        handler.removeCallbacks(countdownRunnable)
        handler.post(countdownRunnable)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(countdownRunnable)
        TempAccessManager.tempAllowedPackage = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotification(): Notification {
        val minutes = durationSeconds / 60
        val seconds = durationSeconds % 60
        val timeStr = String.format("%02d:%02d", minutes, seconds)

        // Tapping the notification can return to launcher
        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Temporary App Access Active")
            .setContentText("Remaining time for distraction check: $timeStr")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun updateNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification())
    }

    private fun forceReturnToLauncher() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(homeIntent)

        // Multiple safety launches to override fast app resumption loops
        val loopHandler = Handler(Looper.getMainLooper())
        var count = 0
        val forceRunnable = object : Runnable {
            override fun run() {
                if (count < 3) {
                    val intent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    }
                    startActivity(intent)
                    count++
                    loopHandler.postDelayed(this, 500)
                }
            }
        }
        loopHandler.post(forceRunnable)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Distraction Timer Service Channel",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }
}
