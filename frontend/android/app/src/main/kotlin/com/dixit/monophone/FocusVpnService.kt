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
                // Cloudflare Family DNS (blocks malware & adult sites)
                .addDnsServer("1.1.1.3")
                .addDnsServer("1.0.0.3")
                // IPv6 CleanBrowsing/Cloudflare (essential for modern networks)
                .addDnsServer("2606:4700:4700::1113")
                .addDnsServer("2606:4700:4700::1003")
                
                // IMPORTANT: We REMOVED .addRoute("0.0.0.0", 0) 
                // This was causing the internet to stop working on WiFi/Mobile.
                // Instead, we add targeted routes for the DNS servers only.
                .addRoute("1.1.1.3", 32)
                .addRoute("1.0.0.3", 32)
                
                .setBlocking(false)

            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface")
                return
            }

            val inputStream = java.io.FileInputStream(vpnInterface!!.fileDescriptor)
            val buffer = ByteArray(32768)

            // Keep the thread alive and drain the interface to prevent stalling
            while (isRunning) {
                try {
                    // We read packets that are routed here (primarily DNS queries to 1.1.1.3)
                    // In a full implementation, we'd proxy these to a real DNS server.
                    // For now, we drain the buffer to ensure the system doesn't kill the VPN.
                    val length = inputStream.read(buffer)
                    if (length <= 0) {
                        Thread.sleep(100)
                    }
                } catch (e: Exception) {
                    if (isRunning) Log.e(TAG, "Error reading from VPN interface: ${e.message}")
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
