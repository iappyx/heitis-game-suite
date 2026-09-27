package com.iappyx.heitisgames

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class NetworkKeepAliveService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Game Suite")
            .setContentText("Game in progress")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .build()

        // Can throw on Android 12+ (ForegroundServiceStartNotAllowedException)
        // or 14+ (SecurityException); keep running as a plain service then.
        try {
            startForeground(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w("GameSuite", "startForeground failed", e)
        }

        // onStartCommand runs for every startService() call (WakeLock.acquire()
        // is called at every game start) — create the locks once and only
        // (re)acquire them when not held, so no lock instances leak.

        // Prevent CPU from sleeping — keeps Dart isolate running
        try {
            val wl = wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "GameSuite::NetworkLock"
            ).also {
                it.setReferenceCounted(false)
                wakeLock = it
            }
            // Re-acquiring a non-reference-counted lock just renews the timeout.
            wl.acquire(4 * 60 * 60 * 1000L) // max 4 hours
        } catch (e: Exception) {
            Log.w("GameSuite", "WakeLock failed", e)
        }

        val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager

        // Prevent WiFi radio from sleeping — keeps TCP socket alive
        try {
            val wfl = wifiLock ?: wm.createWifiLock(
                WifiManager.WIFI_MODE_FULL,    // FULL allows PSM; HIGH_PERF was unnecessary
                "GameSuite::WifiLock"
            ).also {
                it.setReferenceCounted(false)
                wifiLock = it
            }
            if (!wfl.isHeld) wfl.acquire()
        } catch (e: Exception) {
            Log.w("GameSuite", "WifiLock failed", e)
        }

        // Keep receiving multicast discovery beacons (e.g. rediscovery during
        // a reconnect) while a session runs, also with the app in the background.
        try {
            val ml = multicastLock ?: wm.createMulticastLock("GameSuite::SessionMulticastLock")
                .also {
                    it.setReferenceCounted(false)
                    multicastLock = it
                }
            if (!ml.isHeld) ml.acquire()
        } catch (e: Exception) {
            Log.w("GameSuite", "MulticastLock failed", e)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (e: Exception) {}
        try { wifiLock?.let { if (it.isHeld) it.release() } } catch (e: Exception) {}
        try { multicastLock?.let { if (it.isHeld) it.release() } } catch (e: Exception) {}
        wakeLock = null
        wifiLock = null
        multicastLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "Game Session",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Active multiplayer game session" }
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "game_session"
        const val NOTIFICATION_ID = 1
    }
}
