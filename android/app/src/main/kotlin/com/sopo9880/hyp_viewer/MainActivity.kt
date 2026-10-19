package com.sopo9880.hyp_viewer

import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import android.net.Uri
import android.net.VpnService
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.MethodCall
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executor
import kotlin.concurrent.thread
import android.provider.DocumentsContract
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.KeyEvent
import android.content.ActivityNotFoundException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "hyp_viewer/share"
    private var dpiOperationBusy = false
    private val vpnPermissionRequest = 9420
    private var pendingVpnRequest: MethodChannel.Result? = null
    private var pendingVpnPreset = ""
    private var pendingVpnExcluded: ArrayList<String> = arrayListOf()
    private val vpnSocksPort by lazy {
        getSharedPreferences("hyp_android_dpi_socks", Context.MODE_PRIVATE)
    }
    private val dpiPreferences by lazy {
        getSharedPreferences("hyp_android_dpi_local", Context.MODE_PRIVATE)
    }
    private val proxyCallbackExecutor = Executor { command -> runOnUiThread(command) }
    private var channel: MethodChannel? = null
    private var pendingSharedText: String? = null
    private var pendingSharedImagePaths: List<String> = emptyList()
    private var sharedImageRequestSerial = 0
    private var readerChannel: MethodChannel? = null
    private var securityChannel: MethodChannel? = null
    private val securityUpdateRequest = 8421
    private val exportFolderRequest = 8422
    private var exportChannel: MethodChannel? = null
    private var pendingExport: MethodChannel.Result? = null
    private var pendingExportFiles: List<Map<String, String>> = emptyList()
    private var pendingSecurityUpdate: MethodChannel.Result? = null
    private var volumeNavigationEnabled = false
    private val notificationPermissionRequest = 8423
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private val downloadChannelName = "hyp_viewer/download_notification"
    private var downloadChannel: MethodChannel? = null
    private var pendingOpenDownloads = false
    // flutter_background 1.3.1 uses startForeground(1, ...) on this same
    // channel. Updating ID 1 is essential: never create a second running
    // download notification while the foreground service is active.
    private val ongoingNotificationId = 1
    private val terminalNotificationId = 3145
    private val foregroundChannelId = "flutter_background"
    private val resultChannelId = "hyp_viewer_download_results"
    private var lastProgressUpdateAt = 0L

    private fun notificationManager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun notificationsAllowed(): Boolean {
        val runtimeGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        return runtimeGranted && NotificationManagerCompat.from(this).areNotificationsEnabled()
    }

    private fun downloadsPendingIntent(): PendingIntent {
        val open = Intent(this, MainActivity::class.java).apply {
            putExtra("openDownloads", true)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(this, 3145, open, flags)
    }

    private fun ensureChannel(id: String, description: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = notificationManager()
            if (manager.getNotificationChannel(id) == null) {
                manager.createNotificationChannel(NotificationChannel(
                    id, description, NotificationManager.IMPORTANCE_LOW))
            }
        }
    }

    private fun updateDownloadProgress(args: Map<*, *>) {
        val total = ((args["total"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
        val done = ((args["done"] as? Number)?.toInt() ?: 0).coerceIn(0, total)
        val preparing = total == 0
        val paused = args["paused"] == true
        val isUpdate = args["update"] == true
        val queued = ((args["queued"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
        val language = args["language"] as? String ?: "ko"
        val id = (args["workId"] as? String ?: "").take(12)
        val now = android.os.SystemClock.elapsedRealtime()
        // Throttle fast cached pages without suppressing the last page or pause.
        if (!paused && done < total && done > 0 && now - lastProgressUpdateAt < 200L)
            return
        lastProgressUpdateAt = now
        val percent = if (preparing) 0 else (done * 100L / total).toInt()
        val title = when (language) {
            "en" -> if (paused) "HYP Viewer · Download paused" else "HYP Viewer · Downloading"
            "ja" -> if (paused) "HYP Viewer · 一時停止中" else "HYP Viewer · ダウンロード中"
            else -> if (paused) "HYP Viewer · 다운로드 일시정지" else "HYP Viewer · 다운로드 중"
        }
        val text = when (language) {
            "en" -> if (preparing) "Preparing work #$id" else if (isUpdate) "App update: $percent%" else "Work #$id · $done/$total pages · $percent%"
            "ja" -> if (preparing) "作品 #$id を準備中" else if (isUpdate) "アプリ更新: $percent%" else "作品 #$id · $done/${total}ページ · $percent%"
            else -> if (preparing) "작품 #$id 준비 중" else if (isUpdate) "앱 업데이트 · $percent%" else "작품 #$id · $done/${total}페이지 · $percent%"
        }
        val subText = if (queued == 0) null else when (language) {
            "en" -> "$queued works queued"
            "ja" -> "待機中: ${queued}作品"
            else -> "대기 중인 작품 ${queued}개"
        }
        ensureChannel(foregroundChannelId, when (language) {
            "en" -> "HYP Viewer downloads"
            "ja" -> "HYP Viewer ダウンロード"
            else -> "HYP Viewer 다운로드"
        })
        val notification = NotificationCompat.Builder(this, foregroundChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(subText)
            .setContentIntent(downloadsPendingIntent())
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(total, done, preparing)
            .build()
        try {
            notificationManager().notify(ongoingNotificationId, notification)
        } catch (_: SecurityException) {
            // Android 13+ may suppress notifications if the user declines permission.
        }
    }

    private fun showDownloadResult(args: Map<*, *>) {
        val workId = (args["workId"] as? String ?: "").take(12)
        val success = args["success"] == true
        val cancelled = args["cancelled"] == true
        val language = args["language"] as? String ?: "ko"
        val state = when (language) {
            "en" -> if (cancelled) "Cancelled" else if (success) "Finished" else "Failed"
            "ja" -> if (cancelled) "キャンセル" else if (success) "完了" else "失敗"
            else -> if (cancelled) "취소됨" else if (success) "완료" else "실패"
        }
        val label = when (language) {
            "en" -> "Work #$workId download $state"
            "ja" -> "作品 #$workId ダウンロード$state"
            else -> "작품 #$workId 다운로드 $state"
        }
        ensureChannel(resultChannelId, when (language) {
            "en" -> "HYP Viewer download results"
            "ja" -> "HYP Viewer ダウンロード結果"
            else -> "HYP Viewer 다운로드 결과"
        })
        val notification = NotificationCompat.Builder(this, resultChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("HYP Viewer")
            .setContentText(label)
            .setContentIntent(downloadsPendingIntent())
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .build()
        try {
            notificationManager().notify(terminalNotificationId, notification)
        } catch (_: SecurityException) { /* App notifications not permitted. */ }
    }
    private val volumeHandler = Handler(Looper.getMainLooper())
    private var heldVolumeKey: Int? = null
    private var volumeRepeatRunnable: Runnable? = null
    private var volumeRepeatSuspended = false
    private var volumeRepeatIntervalMs = 400L

    private fun releaseVolumeHold() {
        volumeRepeatRunnable?.let { volumeHandler.removeCallbacks(it) }
        volumeRepeatRunnable = null
        heldVolumeKey = null
        volumeRepeatSuspended = false
    }

    private fun emitVolumeTurn(keyCode: Int, repeating: Boolean) {
        val next = keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        readerChannel?.invokeMethod(if (next) {
            if (repeating) "nextRepeat" else "next"
        } else {
            if (repeating) "previousRepeat" else "previous"
        }, null)
    }

    private fun beginVolumeHold(keyCode: Int) {
        releaseVolumeHold()
        heldVolumeKey = keyCode
        emitVolumeTurn(keyCode, false)
        val tick = object : Runnable {
            override fun run() {
                if (!volumeNavigationEnabled || heldVolumeKey != keyCode ||
                    volumeRepeatSuspended) return
                emitVolumeTurn(keyCode, true)
                volumeHandler.postDelayed(this, volumeRepeatIntervalMs)
            }
        }
        volumeRepeatRunnable = tick
        volumeHandler.postDelayed(tick, 500L)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readShareIntent(intent)
        if (intent?.getBooleanExtra("openDownloads", false) == true) {
            pendingOpenDownloads = true
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isVolume = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if (isVolume && volumeNavigationEnabled) {
            when (event.action) {
                KeyEvent.ACTION_DOWN -> {
                    if (event.repeatCount == 0 && heldVolumeKey != event.keyCode) {
                        beginVolumeHold(event.keyCode)
                    }
                    // Android's own auto-repeat is consumed. A fixed timer
                    // starts after 500ms and is stopped on KEY_UP.
                    return true
                }
                KeyEvent.ACTION_UP -> {
                    if (heldVolumeKey == event.keyCode) releaseVolumeHold()
                    return true
                }
            }
        }
        if (isVolume && event.action == KeyEvent.ACTION_UP &&
            heldVolumeKey == event.keyCode) {
            releaseVolumeHold()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "hyp_viewer/reader_control")
        downloadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            downloadChannelName)
        downloadChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        notificationsAllowed()) {
                        result.success(notificationsAllowed())
                    } else if (pendingNotificationPermission != null) {
                        result.error("permission_in_progress",
                            "Notification permission is already requested", null)
                    } else {
                        pendingNotificationPermission = result
                        try {
                            ActivityCompat.requestPermissions(this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                notificationPermissionRequest)
                        } catch (_: Exception) {
                            pendingNotificationPermission = null
                            result.success(false)
                        }
                    }
                }
                "notificationsEnabled" -> result.success(notificationsAllowed())
                "updateProgress" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments != null) updateDownloadProgress(arguments)
                    result.success(null)
                }
                "showResult" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments != null) showDownloadResult(arguments)
                    result.success(null)
                }
                "clearResult" -> {
                    notificationManager().cancel(terminalNotificationId)
                    result.success(null)
                }
                "consumeOpenDownloads" -> {
                    val pending = pendingOpenDownloads
                    pendingOpenDownloads = false
                    result.success(pending)
                }
                else -> result.notImplemented()
            }
        }
        readerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeNavigation" -> {
                    val args = call.arguments as? Map<*, *>
                    volumeNavigationEnabled = args?.get("enabled") == true ||
                        call.arguments == true
                    val interval = (args?.get("intervalMs") as? Number)?.toLong() ?: 400L
                    volumeRepeatIntervalMs = if (interval in listOf(200L, 400L, 700L))
                        interval else 400L
                    if (!volumeNavigationEnabled) releaseVolumeHold()
                    result.success(null)
                }
                "pauseVolumeRepeat" -> {
                    volumeRepeatSuspended = true
                    volumeRepeatRunnable?.let { volumeHandler.removeCallbacks(it) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        securityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "hyp_viewer/security")
        securityChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openSecuritySettingsForUpdate" -> {
                    if (pendingSecurityUpdate != null) {
                        result.error("settings_open", "Security settings already open", null)
                    } else {
                        pendingSecurityUpdate = result
                        try {
                            startActivityForResult(
                                Intent(Settings.ACTION_SECURITY_SETTINGS),
                                securityUpdateRequest
                            )
                        } catch (_: Exception) {
                            try {
                                startActivityForResult(
                                    Intent(Settings.ACTION_SETTINGS),
                                    securityUpdateRequest
                                )
                            } catch (_: Exception) {
                                pendingSecurityUpdate = null
                                result.success(false)
                            }
                        }
                    }
                }
                "openSecuritySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        try {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                            result.success(true)
                        } catch (_: Exception) { result.success(false) }
                    } catch (_: SecurityException) { result.success(false) }
                }
                else -> result.notImplemented()
            }
        }
        exportChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "hyp_viewer/export_cbz")
        exportChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "exportToFolder" -> {
                    if (pendingExport != null) {
                        result.error("busy", "Another export is in progress", null)
                    } else {
                        val files = call.argument<List<Map<String, String>>>("files")
                        if (files.isNullOrEmpty() || files.size > 500) {
                            result.error("invalid", "Select 1 to 500 CBZ files", null)
                        } else {
                            pendingExport = result
                            pendingExportFiles = files
                            try {
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivityForResult(intent, exportFolderRequest)
                            } catch (error: Exception) {
                                pendingExport = null
                                pendingExportFiles = emptyList()
                                result.error("picker", error.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "hyp_viewer/android_dpi").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startAndroidDpi(call, result)
                "stop" -> stopAndroidDpi(result)
                "vpnStart" -> startDeviceDpiVpn(call, result)
                "vpnStop" -> stopDeviceDpiVpn(result)
                "vpnStatus" -> result.success(mapOf(
                    "running" to AndroidDpiVpnService.isActive(),
                    "code" to AndroidDpiVpnService.errorCode()
                ))
                "vpnApps" -> {
                    thread(name = "HYP-VPN-apps") {
                        val apps = launchableVpnApps()
                        runOnUiThread { result.success(apps) }
                    }
                }
                "status" -> {
                    val port = dpiPreferences.getInt("port", 0)
                    val supported = WebViewFeature.isFeatureSupported(
                        WebViewFeature.PROXY_OVERRIDE)
                    // Never open a socket on the Android UI thread.
                    thread(name = "HYP-DPI-status", isDaemon = true) {
                        val live = port in 1025..65535 && isDpiListening(port)
                        runOnUiThread {
                            result.success(mapOf(
                                "supported" to supported,
                                "running" to live,
                                "port" to port
                            ))
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                }
                "getSharedImages" -> {
                    result.success(pendingSharedImagePaths)
                    pendingSharedImagePaths = emptyList()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isDpiListening(port: Int): Boolean = try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress("127.0.0.1", port), 140)
            true
        }
    } catch (_: Exception) { false }

    private fun newDpiPort(): Int = ServerSocket(
        0, 1, InetAddress.getByName("127.0.0.1")
    ).use { server -> server.localPort }

    private fun stopNativeDpi() {
        try {
            startService(Intent(this, AndroidDpiService::class.java).apply {
                action = AndroidDpiService.ACTION_STOP
            })
        } catch (_: Exception) { /* Already stopped. */ }
    }

    private fun startAndroidDpi(call: MethodCall, result: MethodChannel.Result) {
        if (dpiOperationBusy) {
            result.error("busy", "Android DPI operation already running", null)
            return
        }
        // App-local HTTP CONNECT and device VPN share one allowlist.
        val preset = call.argument<String>("preset") ?: "all_dnsredir"
        if (preset !in AndroidDpiPresets.names) {
            result.error("invalid_preset", "Unknown ByeDPI preset", null)
            return
        }
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.error("webview_unsupported",
                "This Android WebView cannot use a local HTTP proxy", null)
            return
        }
        dpiOperationBusy = true
        val stored = dpiPreferences.getInt("port", 0)
        val port = try {
            if (stored in 1025..65535) stored else newDpiPort()
        } catch (_: Exception) {
            dpiOperationBusy = false
            result.error("port", "Unable to reserve local DPI port", null)
            return
        }
        dpiPreferences.edit().putInt("port", port).apply()
        try {
            // The Service ignores a second START when its engine already runs.
            // This avoids checking local sockets on the Android main thread.
            val intent = Intent(this, AndroidDpiService::class.java).apply {
                action = AndroidDpiService.ACTION_START
                putExtra(AndroidDpiService.EXTRA_PORT, port)
                putExtra(AndroidDpiService.EXTRA_PRESET, preset)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
            dpiOperationBusy = false
            result.error("service", "Android DPI service could not start", null)
            return
        }
        thread(name = "HYP-DPI-probe", isDaemon = true) {
            var listening = false
            for (attempt in 0 until 55) {
                if (isDpiListening(port)) {
                    listening = true
                    break
                }
                try { Thread.sleep(125L) } catch (_: InterruptedException) {}
            }
            runOnUiThread {
                if (!listening) {
                    dpiOperationBusy = false
                    stopNativeDpi()
                    result.error("engine_timeout",
                        "ByeDPI native proxy did not start", null)
                    return@runOnUiThread
                }
                try {
                    val config = ProxyConfig.Builder()
                        .addProxyRule("http://127.0.0.1:" + port)
                        .addBypassRule("127.0.0.1")
                        .addBypassRule("localhost")
                        .build()
                    ProxyController.getInstance().setProxyOverride(config,
                        proxyCallbackExecutor, Runnable {
                            dpiOperationBusy = false
                            result.success(mapOf("running" to true, "port" to port))
                        })
                } catch (_: Exception) {
                    dpiOperationBusy = false
                    stopNativeDpi()
                    result.error("webview_proxy",
                        "Unable to configure WebView HTTP proxy", null)
                }
            }
        }
    }

    private fun stopAndroidDpi(result: MethodChannel.Result) {
        if (dpiOperationBusy) {
            result.error("busy", "Android DPI operation already running", null)
            return
        }
        dpiOperationBusy = true
        val port = dpiPreferences.getInt("port", 0)
        stopNativeDpi()
        // Explicitly wait for the isolated native process to release the port,
        // otherwise changing presets could silently reuse the old engine.
        thread(name = "HYP-DPI-stop", isDaemon = true) {
            var released = port !in 1025..65535
            for (attempt in 0 until 32) {
                if (!isDpiListening(port)) {
                    released = true
                    break
                }
                try { Thread.sleep(100L) } catch (_: InterruptedException) {}
            }
            runOnUiThread {
                if (!released) {
                    dpiOperationBusy = false
                    result.error("stop_timeout",
                        "Native DPI proxy did not release its port", null)
                    return@runOnUiThread
                }
                if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                    dpiOperationBusy = false
                    result.success(null)
                    return@runOnUiThread
                }
                try {
                    ProxyController.getInstance().clearProxyOverride(
                        proxyCallbackExecutor, Runnable {
                            dpiOperationBusy = false
                            result.success(null)
                        })
                } catch (_: Exception) {
                    dpiOperationBusy = false
                    result.error("webview_proxy_reset",
                        "Unable to clear WebView HTTP proxy", null)
                }
            }
        }
    }


    private fun launchableVpnApps(): List<Map<String, String>> {
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = packageManager.queryIntentActivities(query, 0)
        return apps.mapNotNull { activity ->
            val name = activity.activityInfo?.packageName ?: return@mapNotNull null
            if (name == packageName) return@mapNotNull null
            mapOf("package" to name,
                  "name" to activity.loadLabel(packageManager).toString().take(100))
        }.distinctBy { it["package"] }
            .sortedBy { it["name"] }
            .take(250)
    }

    private fun stopSocksDpi() {
        try {
            startService(Intent(this, AndroidDpiSocksService::class.java).apply {
                action = AndroidDpiService.ACTION_STOP
            })
        } catch (_: Exception) {}
    }

    private fun startDeviceDpiVpn(call: MethodCall, result: MethodChannel.Result) {
        if (pendingVpnRequest != null || dpiOperationBusy) {
            result.error("vpn-busy", "VPN startup is already running", null)
            return
        }
        if (AndroidDpiVpnService.isActive()) {
            result.success(mapOf("running" to true))
            return
        }
        val preset = call.argument<String>("preset") ?: ""
        if (preset !in AndroidDpiPresets.names) {
            result.error("invalid-preset", "Unsupported device DPI preset", null)
            return
        }
        val excluded = call.argument<List<String>>("excluded") ?: emptyList()
        if (excluded.size > 100 || excluded.any {
                it.length > 150 || !Regex("[A-Za-z0-9_.]{3,150}").matches(it)
            }) {
            result.error("invalid-exclusions", "Unsupported package exclusion", null)
            return
        }
        pendingVpnPreset = preset
        pendingVpnExcluded = ArrayList(excluded.distinct())
        pendingVpnRequest = result
        try {
            val consent = VpnService.prepare(this)
            if (consent != null) {
                startActivityForResult(consent, vpnPermissionRequest)
            } else {
                launchDeviceDpiVpn()
            }
        } catch (_: Exception) {
            pendingVpnRequest = null
            result.error("vpn-consent", "Android VPN consent unavailable", null)
        }
    }

    private fun launchDeviceDpiVpn() {
        val result = pendingVpnRequest ?: return
        val port = try {
            val previous = vpnSocksPort.getInt("port", 0)
            if (previous in 1025..65535) previous else newDpiPort()
        } catch (_: Exception) {
            pendingVpnRequest = null
            result.error("vpn-port", "Unable to allocate SOCKS5 port", null)
            return
        }
        vpnSocksPort.edit().putInt("port", port).apply()
        try {
            val native = Intent(this, AndroidDpiSocksService::class.java).apply {
                action = AndroidDpiService.ACTION_START
                putExtra(AndroidDpiService.EXTRA_PORT, port)
                putExtra(AndroidDpiService.EXTRA_PRESET, pendingVpnPreset)
                putExtra(AndroidDpiService.EXTRA_PROXY_KIND, "socks5")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(native)
            } else {
                startService(native)
            }
        } catch (_: Exception) {
            pendingVpnRequest = null
            result.error("vpn-socks-service", "Unable to launch local SOCKS5", null)
            return
        }
        thread(name = "HYP-DPI-VPN-start", isDaemon = true) {
            var listening = false
            for (attempt in 0 until 65) {
                if (isDpiListening(port)) { listening = true; break }
                try { Thread.sleep(100L) } catch (_: InterruptedException) {}
            }
            if (listening) {
                runOnUiThread {
                    try {
                        val intent = Intent(this, AndroidDpiVpnService::class.java).apply {
                            action = AndroidDpiVpnService.ACTION_START
                            putExtra(AndroidDpiVpnService.EXTRA_PORT, port)
                            putExtra(AndroidDpiVpnService.EXTRA_PRESET, pendingVpnPreset)
                            putStringArrayListExtra(AndroidDpiVpnService.EXTRA_EXCLUDED,
                                pendingVpnExcluded)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    } catch (_: Exception) {}
                }
                for (attempt in 0 until 65) {
                    if (AndroidDpiVpnService.isActive()) break
                    try { Thread.sleep(100L) } catch (_: InterruptedException) {}
                }
            }
            val ok = listening && AndroidDpiVpnService.isActive()
            runOnUiThread {
                val reply = pendingVpnRequest
                pendingVpnRequest = null
                if (ok) {
                    reply?.success(mapOf("running" to true, "port" to port))
                } else {
                    stopSocksDpi()
                    reply?.error("vpn-start-failed",
                        AndroidDpiVpnService.errorCode().ifEmpty {
                            if (listening) "Tunnel failed" else "SOCKS5 engine not listening"
                        }, null)
                }
            }
        }
    }

    private fun stopDeviceDpiVpn(result: MethodChannel.Result) {
        if (pendingVpnRequest != null) {
            result.error("vpn-busy", "VPN startup is running", null)
            return
        }
        try {
            startService(Intent(this, AndroidDpiVpnService::class.java).apply {
                action = AndroidDpiVpnService.ACTION_STOP
            })
            stopSocksDpi()
        } catch (_: Exception) {}
        thread(name = "HYP-VPN-stop", isDaemon = true) {
            for (attempt in 0 until 40) {
                if (!AndroidDpiVpnService.isActive()) break
                try { Thread.sleep(100L) } catch (_: InterruptedException) {}
            }
            runOnUiThread {
                if (AndroidDpiVpnService.isActive()) {
                    result.error("vpn-stop-timeout", "VPN did not stop", null)
                } else {
                    result.success(null)
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequest) {
            pendingNotificationPermission?.success(notificationsAllowed())
            pendingNotificationPermission = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnPermissionRequest) {
            if (resultCode == Activity.RESULT_OK) {
                launchDeviceDpiVpn()
            } else {
                val reply = pendingVpnRequest
                pendingVpnRequest = null
                reply?.error("vpn-permission-denied", "VPN approval was declined", null)
            }
            return
        }
        if (requestCode == securityUpdateRequest) {
            pendingSecurityUpdate?.success(true)
            pendingSecurityUpdate = null
        }
        if (requestCode == exportFolderRequest) {
            val reply = pendingExport
            val files = pendingExportFiles
            pendingExport = null
            pendingExportFiles = emptyList()
            if (reply != null) {
                val tree = data?.data
                if (resultCode != Activity.RESULT_OK || tree == null) {
                    reply.success(0)
                } else {
                    Thread {
                        var count = 0
                        var failures = 0
                        try {
                            // Folder-grant URIs must be used via ContentResolver;
                            // they are NOT ordinary filesystem paths on Android.
                            val treeId = DocumentsContract.getTreeDocumentId(tree)
                            val parent = DocumentsContract.buildDocumentUriUsingTree(
                                tree, treeId)
                            val root = filesDir.canonicalPath + File.separator
                            for (entry in files) {
                                val original = File(entry["path"] ?: "")
                                val targetName = entry["name"] ?: ""
                                if (!original.isFile ||
                                    !original.canonicalPath.startsWith(root) ||
                                    !original.name.endsWith(".cbz") ||
                                    original.length() > 200L * 1024 * 1024 ||
                                    !Regex("^[a-zA-Z0-9_ -]{1,95}[.]cbz$")
                                        .matches(targetName)) {
                                    failures++
                                    continue
                                }
                                var output: Uri? = null
                                try {
                                    val created = DocumentsContract.createDocument(
                                        contentResolver, parent,
                                        "application/vnd.comicbook+zip", targetName)
                                        ?: throw IllegalStateException(
                                            "Could not create destination")
                                    output = created
                                    FileInputStream(original).use { input ->
                                        contentResolver.openOutputStream(created, "w").use { stream ->
                                            if (stream == null) throw IllegalStateException(
                                                "Could not open destination")
                                            input.copyTo(stream, bufferSize = 65536)
                                        }
                                    }
                                    count++
                                } catch (_: Exception) {
                                    failures++
                                    if (output != null) {
                                        try {
                                            DocumentsContract.deleteDocument(contentResolver, output)
                                        } catch (_: Exception) {}
                                    }
                                }
                            }
                            runOnUiThread {
                                reply.success(mapOf("saved" to count, "failed" to failures))
                            }
                        } catch (error: Exception) {
                            runOnUiThread {
                                reply.error("export", error.message, null)
                            }
                        }
                    }.start()
                }
            }
        }
    }

    override fun onStop() {
        volumeNavigationEnabled = false
        releaseVolumeHold()
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readShareIntent(intent)
        if (intent.getBooleanExtra("openDownloads", false)) {
            pendingOpenDownloads = true
            downloadChannel?.invokeMethod("openDownloads", null)
        }
        pendingSharedText?.let { shared ->
            channel?.invokeMethod("sharedText", shared)
            pendingSharedText = null
        }
    }

    private fun readShareIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action == Intent.ACTION_SEND &&
            intent.type == "text/plain") {
            pendingSharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            return
        }
        if (intent.type?.startsWith("image/") != true ||
            intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE) return

        val images = linkedSetOf<Uri>()
        if (intent.action == Intent.ACTION_SEND) {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(images::add)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                ?.forEach(images::add)
        }
        intent.clipData?.let { clips ->
            for (index in 0 until minOf(clips.itemCount, 8)) {
                clips.getItemAt(index).uri?.let(images::add)
            }
        }
        val selected = images.take(8)
        if (selected.isEmpty()) return
        val generation = ++sharedImageRequestSerial
        Thread {
            val copied = mutableListOf<String>()
            for ((index, uri) in selected.withIndex()) {
                try {
                    val input = contentResolver.openInputStream(uri) ?: continue
                    val folder = File(cacheDir, "hyp_shared_images")
                    if (!folder.exists()) folder.mkdirs()
                    val file = File(folder,
                        "share_" + System.currentTimeMillis().toString() +
                        "_" + index.toString() + ".img")
                    var size = 0L
                    var tooLarge = false
                    input.use { stream ->
                        FileOutputStream(file).use { output ->
                            val bytes = ByteArray(65536)
                            while (true) {
                                val count = stream.read(bytes)
                                if (count < 0) break
                                size += count
                                if (size > 12L * 1024 * 1024) {
                                    tooLarge = true
                                    break
                                }
                                output.write(bytes, 0, count)
                            }
                        }
                    }
                    if (tooLarge || size == 0L) file.delete()
                    else copied.add(file.absolutePath)
                } catch (_: Exception) {
                    // Revoked/expired ContentResolver URI. Continue other images.
                }
            }
            runOnUiThread {
                if (generation == sharedImageRequestSerial &&
                    copied.isNotEmpty()) {
                    pendingSharedImagePaths = copied
                    channel?.let { incoming ->
                        incoming.invokeMethod("sharedImages", copied)
                        pendingSharedImagePaths = emptyList()
                    }
                }
            }
        }.start()
    }
}
