package com.sopo9880.hyp_viewer

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "hyp_viewer/share"
    private var channel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
