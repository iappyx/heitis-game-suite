package com.iappyx.heitisgames

import android.content.Intent
import android.net.wifi.WifiManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.iappyx.heitisgames/wakelock"

    // Android filters out incoming multicast packets unless a MulticastLock is
    // held, which drops the WiFi discovery beacons (239.255.42.99). Discovery
    // and hosting always happen with the app in the foreground, so hold the
    // lock while the activity is resumed. (NetworkKeepAliveService holds its
    // own lock during sessions, when the app may be in the background.)
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        // startService can throw (e.g. IllegalStateException /
                        // ForegroundServiceStartNotAllowedException on Android 12+
                        // when the app is considered in the background) — a missing
                        // keep-alive service must never crash the app.
                        try {
                            startService(Intent(this, NetworkKeepAliveService::class.java))
                        } catch (e: Exception) {
                            Log.w("GameSuite", "Could not start keep-alive service", e)
                        }
                        result.success(null)
                    }
                    "release" -> {
                        try {
                            stopService(Intent(this, NetworkKeepAliveService::class.java))
                        } catch (e: Exception) {
                            Log.w("GameSuite", "Could not stop keep-alive service", e)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        try {
            val lock = multicastLock ?: (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                .createMulticastLock("GameSuite::MulticastLock")
                .also {
                    it.setReferenceCounted(false)
                    multicastLock = it
                }
            if (!lock.isHeld) lock.acquire()
        } catch (e: Exception) {
            Log.w("GameSuite", "Could not acquire multicast lock", e)
        }
    }

    override fun onPause() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {}
        super.onPause()
    }
}
