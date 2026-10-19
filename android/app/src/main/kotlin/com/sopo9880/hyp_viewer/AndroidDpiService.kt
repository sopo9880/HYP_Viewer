package com.sopo9880.hyp_viewer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.util.Log
import kotlin.concurrent.thread

/**
 * An opt-in app-local HTTP CONNECT proxy (ByeDPI).
 *
 * Runs in an isolated :dpi process so native code is not loaded in the Flutter
 * process and the C global state is discarded on stop/restart. No root or VPN,
 * no third-party app interception, no TLS interception.
 */
class AndroidDpiService : Service() {
    companion object {
        const val ACTION_START = "com.sopo9880.hyp_viewer.DPI_START"
        const val ACTION_STOP = "com.sopo9880.hyp_viewer.DPI_STOP"
        const val EXTRA_PORT = "port"
        const val EXTRA_PRESET = "preset"
        private const val CHANNEL = "hyp_android_dpi"
        private const val NOTIFICATION_ID = 31719
    }

    private var worker: Thread? = null
    private var stopping = false
    private val handler = Handler(Looper.getMainLooper())
    private val native by lazy { DpiNativeBridge() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                if (worker != null) return START_NOT_STICKY
                val port = intent.getIntExtra(EXTRA_PORT, -1)
                val preset = intent.getStringExtra(EXTRA_PRESET) ?: ""
                if (port !in 1025..65535 ||
                    preset !in listOf("standard", "strong", "sni")) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                createForegroundNotification()
                val args = mutableListOf(
                    "byedpi", "-i", "http://127.0.0.1",
                    "-p", port.toString(), "-U"
                )
                when (preset) {
                    "standard" -> args.addAll(listOf("-s", "1"))
                    "strong" -> args.addAll(listOf("-s", "1", "-q", "1"))
                    "sni" -> args.addAll(listOf("-s", "0+sm"))
                }
                worker = thread(name = "HYP-ByeDPI", isDaemon = true) {
                    try {
                        val code = native.run(args.toTypedArray())
                        Log.i("HYP-DPI", "Native DPI proxy exited with code " + code)
                    } catch (error: Throwable) {
                        Log.e("HYP-DPI", "Native DPI proxy failed", error)
                    } finally {
                        handler.post { finishIsolatedProcess() }
                    }
                }
            }
            ACTION_STOP -> {
                stopping = true
                try { if (worker != null) native.stop() } catch (_: Throwable) {}
                if (worker == null) finishIsolatedProcess()
                else handler.postDelayed({ finishIsolatedProcess() }, 2000L)
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun createForegroundNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL, "HYP Viewer DPI", NotificationManager.IMPORTANCE_LOW
            ))
        }
        val pending = PendingIntent.getActivity(this, NOTIFICATION_ID,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            Notification.Builder(this)
        }.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("HYP Viewer DPI")
            .setContentText("Local ByeDPI proxy is running")
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun finishIsolatedProcess() {
        if (stopping && worker?.isAlive == true) {
            Log.i("HYP-DPI", "Stopping native worker")
        }
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
        // ByeDPI parses global C state on start and is deliberately not
        // restarted inside one process. The Flutter process stays alive.
        Process.killProcess(Process.myPid())
    }

    override fun onDestroy() {
        try { if (worker != null) native.stop() } catch (_: Throwable) {}
        super.onDestroy()
    }
}
