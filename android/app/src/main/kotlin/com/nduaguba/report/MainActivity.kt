package com.nduaguba.report

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var logbookFiles: LogbookFiles? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        logbookFiles = LogbookFiles(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ripot/logbook_files"))
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (logbookFiles?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
