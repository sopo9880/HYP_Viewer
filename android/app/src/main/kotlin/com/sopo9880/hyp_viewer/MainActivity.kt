package com.sopo9880.hyp_viewer

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
    private var channel: MethodChannel? = null
    private var pendingSharedText: String? = null
    private var readerChannel: MethodChannel? = null
    private var securityChannel: MethodChannel? = null
    private var volumeNavigationEnabled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readShareIntent(intent)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeNavigationEnabled && event.action == KeyEvent.ACTION_DOWN &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
             event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.repeatCount == 0) {
                readerChannel?.invokeMethod(
                    if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) "next" else "previous", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "hyp_viewer/reader_control")
        readerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeNavigation" -> {
                    volumeNavigationEnabled = call.arguments == true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        securityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "hyp_viewer/security")
        securityChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
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
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStop() {
        volumeNavigationEnabled = false
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readShareIntent(intent)
        pendingSharedText?.let { channel?.invokeMethod("sharedText", it) }
    }

    private fun readShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return
        pendingSharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
    }
}
