package com.sopo9880.hyp_viewer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import hev.htproxy.TProxyService
import java.io.File
import kotlin.concurrent.thread

/**
 * Explicitly approved whole-device VPN using pinned hev-socks5-tunnel.
 * The tunnel forwards TCP and UDP to our *on-device* ByeDPI SOCKS5 worker.
 * HYP Viewer's own package is excluded to avoid routing the proxy back into
 * its own TUN device; no remote VPN server, root, or TLS interception is used.
 */
class AndroidDpiVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.sopo9880.hyp_viewer.VPN_START"
        const val ACTION_STOP = "com.sopo9880.hyp_viewer.VPN_STOP"
        const val EXTRA_PORT = "socksPort"
        const val EXTRA_PRESET = "preset"
        const val EXTRA_EXCLUDED = "excluded"
        private const val CHANNEL = "hyp_dpi_vpn"
        private const val NOTIFICATION_ID = 31720

        @Volatile private var active = false
        @Volatile private var lastError = ""
        fun isActive(): Boolean {
            return active && try { TProxyService.TProxyIsRunning() } catch (_: Throwable) { false }
        }
        fun errorCode(): String = lastError
    }

    private var tunnelFd: ParcelFileDescriptor? = null
    private var running = false

    override fun onBind(intent: Intent?): IBinder? =
        if (intent?.action == SERVICE_INTERFACE) super.onBind(intent) else null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                if (running) return START_NOT_STICKY
                val port = intent.getIntExtra(EXTRA_PORT, 0)
                val preset = intent.getStringExtra(EXTRA_PRESET) ?: ""
                if (port !in 1025..65535 || preset !in AndroidDpiPresets.names) {
                    lastError = "invalid-vpn-configuration"
                    stopSelf()
                    return START_NOT_STICKY
                }
                val excluded = intent.getStringArrayListExtra(EXTRA_EXCLUDED)
                    ?.take(100)?.toSet() ?: emptySet()
                try {
                    foreground()
                    val builder = Builder()
                        .setSession("HYP Viewer DPI")
                        .setMtu(1500)
                        .addAddress("10.74.0.2", 32)
                        .addRoute("0.0.0.0", 0)
                        .addAddress("fd74::2", 128)
                        .addRoute("::", 0)
                    val dns = if (AndroidDpiPresets.usesAlternativeDns(preset))
                        "77.88.8.8" else originalDns()
                    builder.addDnsServer(dns)
                    // Essential: otherwise our own SOCKS5 connection loops
                    // back into the VpnService and destroys connectivity.
                    builder.addDisallowedApplication(packageName)
                    for (name in excluded) {
                        if (name == packageName ||
                            !Regex("[A-Za-z0-9_.]{3,150}").matches(name)) continue
                        try { builder.addDisallowedApplication(name) }
                        catch (_: Exception) { /* Removed package. */ }
                    }
                    tunnelFd = builder.establish()
                        ?: throw IllegalStateException("Android refused VPN interface")
                    val config = File(cacheDir, "hyp_vpn_tunnel.yml")
                    config.writeText(
                        "tunnel:\n" +
                        "  mtu: 1500\n" +
                        "  ipv4: 10.74.0.2\n" +
                        "  ipv6: 'fd74::2'\n" +
                        "socks5:\n" +
                        "  port: $port\n" +
                        "  address: 127.0.0.1\n" +
                        "  udp: 'udp'\n" +
                        "misc:\n" +
                        "  log-level: warn\n"
                    )
                    if (!TProxyService.TProxyStartService(
                            config.absolutePath, tunnelFd!!.fd)) {
                        throw IllegalStateException("tun2socks rejected configuration")
                    }
                    running = true
                    active = true
                    lastError = ""
                } catch (e: Exception) {
                    Log.e("HYP-VPN", "Failed to create local VPN", e)
                    lastError = "vpn-start-failed"
                    stopTunnel()
                    stopSelf()
                } catch (e: LinkageError) {
                    Log.e("HYP-VPN", "Pinned tunnel JNI not available", e)
                    lastError = "native-tunnel-missing"
                    stopTunnel()
                    stopSelf()
                }
            }
            ACTION_STOP -> {
                stopTunnel()
                stopSelf()
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun originalDns(): String {
        return try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE)
                as ConnectivityManager
            val link = manager.getLinkProperties(manager.activeNetwork)
            link?.dnsServers?.firstOrNull { it.address.size == 4 }
                ?.hostAddress ?: "1.1.1.1"
        } catch (_: Exception) { "1.1.1.1" }
    }

    private fun foreground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "HYP Viewer device DPI",
                    NotificationManager.IMPORTANCE_LOW)
            )
        }
        val pending = PendingIntent.getActivity(this, NOTIFICATION_ID,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL) else Notification.Builder(this))
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("HYP Viewer DPI VPN")
            .setContentText("On-device DPI proxy, no remote VPN server")
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

    private fun stopTunnel() {
        active = false
        running = false
        try { TProxyService.TProxyStopService() } catch (_: Throwable) {}
        try { tunnelFd?.close() } catch (_: Exception) {}
        tunnelFd = null
    }

    override fun onRevoke() {
        lastError = "vpn-revoked"
        stopTunnel()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }
}
