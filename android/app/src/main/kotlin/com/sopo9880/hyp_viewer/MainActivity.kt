package com.sopo9880.hyp_viewer

import android.app.Activity
import android.net.Uri
import android.provider.DocumentsContract
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileInputStream
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
    private val securityUpdateRequest = 8421
    private val exportFolderRequest = 8422
    private var exportChannel: MethodChannel? = null
    private var pendingExport: MethodChannel.Result? = null
    private var pendingExportFiles: List<Map<String, String>> = emptyList()
    private var pendingSecurityUpdate: MethodChannel.Result? = null
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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
