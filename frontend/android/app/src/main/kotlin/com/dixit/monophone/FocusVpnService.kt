package com.dixit.monophone

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * FocusVpnService - An Android local VPN service that acts as the Adult Content Shield.
 *
 * Configures a loopback VPN interface routing name resolution to Cloudflare Family DNS
 * (1.1.1.3 and 1.0.0.3) and CleanBrowsing DNS (185.228.168.168) which automatically filters
 * explicit material, adult websites, and gambling portals.
 */
class FocusVpnService : VpnService(), Runnable {
    companion object {
        private const val TAG = "FocusVpnService"
        var instance: FocusVpnService? = null
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    private var isRunning = false

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == "STOP") {
            stopVpn()
            stopSelf()
            return START_NOT_STICKY
        }

        startVpn()
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }

    private fun startVpn() {
        if (vpnThread != null) return
        isRunning = true
        vpnThread = Thread(this, "FocusVpnThread").apply { start() }
        Log.i(TAG, "VPN Service started.")
    }

    private fun stopVpn() {
        isRunning = false
        vpnThread?.interrupt()
        vpnThread = null
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface: ${e.message}")
        }
        vpnInterface = null
        Log.i(TAG, "VPN Service stopped.")
    }

    override fun run() {
        try {
            val builder = Builder()
                .setSession("FocusVpnContentFilter")
                .addAddress("10.0.0.2", 32)
                .addRoute("0.0.0.0", 0) // Route all IPv4 traffic
                .addDnsServer("1.1.1.3") // Cloudflare Family DNS (blocks malware & adult sites)
                .addDnsServer("1.0.0.3") // Cloudflare Family DNS secondary
                .addDnsServer("185.228.168.168") // CleanBrowsing Family Filter (extra safety)
                .setBlocking(true)

            vpnInterface = builder.establish()

            // Keep the thread alive
            while (isRunning) {
                try {
                    Thread.sleep(1000)
                } catch (e: InterruptedException) {
                    break
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error running VPN thread: ${e.message}")
        } finally {
            stopVpn()
        }
    }
}
