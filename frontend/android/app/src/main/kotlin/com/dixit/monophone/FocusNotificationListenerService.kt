package com.dixit.monophone

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * FocusNotificationListenerService - Intercepts and silences notifications.
 *
 * Listens for incoming notification events. If notification silencing is toggled active
 * in settings, it cancels notifications originating from blocked packages during active
 * Pomodoro sessions or limit lockouts.
 */
class FocusNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val TAG = "FocusNotificationSvc"
        var instance: FocusNotificationListenerService? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        val isPomodoroRunning = PomodoroOverlayService.instance?.isRunning == true

        // Read settings directly from SharedPreferences. Flutter SharedPreferences prefixes keys with "flutter."
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val isSilenceEnabled = prefs.getBoolean("flutter.focustube_notification_silence", false)
        val isBlocked = BlockerConfig.blockedPackages.contains(packageName)

        if (isSilenceEnabled && (isPomodoroRunning || isBlocked)) {
            Log.i(TAG, "Silencing notification from $packageName during active focus.")
            cancelNotification(sbn.key)
        }
    }
}
