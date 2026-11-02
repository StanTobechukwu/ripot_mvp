package com.nduaguba.report

import android.content.Intent
import android.content.ClipData
import android.content.ClipboardManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var logbookFiles: LogbookFiles? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        logbookFiles = LogbookFiles(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ripot/logbook_files"))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ripot/report_clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "write") {
                    result.notImplemented()
                } else {
                    val text = call.argument<String>("text")
                    val html = call.argument<String>("html")
                    if (text == null || html == null) {
                        result.error("arguments", "Missing report text.", null)
                    } else {
                        try {
                            val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                            val clip = ClipData.newHtmlText("Ripot report", text, html)
                            // Clinical text should not appear in Android's clipboard preview.
                            if (android.os.Build.VERSION.SDK_INT >= 24) {
                                clip.description.extras = android.os.PersistableBundle().apply {
                                    putBoolean("android.content.extra.IS_SENSITIVE", true)
                                }
                            }
                            clipboard.setPrimaryClip(clip)
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("clipboard", "Clipboard is unavailable. Try again.", null)
                        }
                    }
                }
            }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (logbookFiles?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
