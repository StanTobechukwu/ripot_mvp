package com.ripot.backup

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.util.UUID
import java.util.concurrent.Executors

class RipotBackupFilesPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var selection: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var lock: FileLock? = null
    private var lockFile: RandomAccessFile? = null
    private val prefs get() = context.getSharedPreferences("ripot_backup_folder", Context.MODE_PRIVATE)
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ripot/backup_files")
        channel.setMethodCallHandler { call, result ->
            when(call.method) {
                "location" -> result.success(prefs.getString("tree", null))
                "chooseFolder" -> {
                    val host = activity
                    if(host == null || selection != null) { result.error("PICKER", "Open Ripot to choose a folder.", null) }
                    else {
                        selection = result
                        try {
                            host.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                            }, 7314)
                        } catch(_: Exception) { selection = null; result.error("PICKER", "Could not open the folder picker.", null) }
                    }
                }
                "acquireLock" -> {
                    try {
                        if(lock != null) { result.success(false) }
                        else {
                            val f = RandomAccessFile(File(context.filesDir, "ripot-backup.lock"), "rw")
                            val acquired = try { f.channel.tryLock() } catch(_: Exception) { null }
                            if(acquired == null) f.close() else { lockFile=f; lock=acquired }
                            result.success(acquired != null)
                        }
                    } catch(_: Exception) { result.success(false) }
                }
                "releaseLock" -> { releaseLock(); result.success(null) }
                "writeBackup" -> {
                    val bytes=call.argument<ByteArray>("bytes")
                    val scope=call.argument<String>("scope") ?: ""
                    val keep=call.argument<Int>("keep") ?: 5
                    if(bytes==null || bytes.isEmpty() || bytes.size>180*1024*1024 || !setOf("all","reports","registry","logbook","records","templates").contains(scope) || keep !in 3..10) {
                        result.error("BACKUP", "Invalid backup request.", null)
                    } else executor.execute {
                        try { val name=write(bytes,scope,keep); main.post { result.success(name) } }
                        catch(_: Exception) { main.post { result.error("BACKUP", "Backup could not be saved and checked. Check storage space or choose the folder again. Previous backups were kept.", null) } }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun releaseLock() { try { lock?.release(); lockFile?.close() } finally { lock=null; lockFile=null } }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { channel.setMethodCallHandler(null); releaseLock(); executor.shutdown() }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { this.binding=binding; activity=binding.activity; binding.addActivityResultListener(this) }
    override fun onDetachedFromActivity() { binding?.removeActivityResultListener(this); binding=null; activity=null; selection?.success(null); selection=null }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if(requestCode!=7314) return false
        val result=selection ?: return true; selection=null
        val uri=data?.data
        if(resultCode!=Activity.RESULT_OK || uri==null) { result.success(null); return true }
        try {
            val flags=((data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
            if((flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION)==0 || (flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)==0) throw IllegalStateException()
            context.contentResolver.takePersistableUriPermission(uri,flags)
            if(!prefs.edit().putString("tree",uri.toString()).commit()) throw IllegalStateException()
            result.success(uri.toString())
        } catch(_: Exception) { result.error("PERMISSION","Choose a folder with read and write access.",null) }
        return true
    }
    private fun read(uri:Uri):ByteArray {
        val out=ByteArrayOutputStream()
        context.contentResolver.openInputStream(uri)?.use { input ->
            val buffer=ByteArray(8192)
            while(true) { val n=input.read(buffer); if(n<0) break; if(out.size()+n>180*1024*1024) throw IllegalStateException(); out.write(buffer,0,n) }
        } ?: throw IllegalStateException()
        return out.toByteArray()
    }
    private fun write(bytes:ByteArray,scope:String,keep:Int):String {
        val tree=Uri.parse(prefs.getString("tree",null) ?: throw IllegalStateException())
        val parent=DocumentsContract.buildDocumentUriUsingTree(tree,DocumentsContract.getTreeDocumentId(tree))
        val stamp=java.text.SimpleDateFormat("yyyy-MM-dd-HHmmss-SSS",java.util.Locale.ROOT).format(java.util.Date())
        val name="Ripot-$scope-$stamp-${UUID.randomUUID()}.ripotbackup"
        var pending:Uri?=null; var done:Uri?=null
        try {
            pending=DocumentsContract.createDocument(context.contentResolver,parent,"application/octet-stream","$name.pending") ?: throw IllegalStateException()
            context.contentResolver.openOutputStream(pending,"wt")?.use { it.write(bytes); it.flush() } ?: throw IllegalStateException()
            if(!read(pending).contentEquals(bytes)) throw IllegalStateException()
            done=DocumentsContract.renameDocument(context.contentResolver,pending,name) ?: throw IllegalStateException()
            if(!read(done).contentEquals(bytes)) throw IllegalStateException()
        } catch(e:Exception) {
            try { (done ?: pending)?.let { DocumentsContract.deleteDocument(context.contentResolver,it) } } catch(_:Exception) {}
            throw e
        }
        val key="managed:$tree:$scope"
        val owned=org.json.JSONArray(prefs.getString(key,"[]"))
        val items=mutableListOf<String>(); for(i in 0 until owned.length()) items.add(owned.getString(i))
        items.add(done.toString())
        // Register ownership before deleting any earlier file. Keep separate
        // retention sets for each scope and never scan/delete unrelated files.
        if(!prefs.edit().putString(key,org.json.JSONArray(items).toString()).commit()) return "$name (saved; rotation unavailable)"
        val failed=mutableListOf<String>()
        for(old in items.dropLast(keep)) {
            try { if(!DocumentsContract.deleteDocument(context.contentResolver,Uri.parse(old))) failed.add(old) } catch(_:Exception) { failed.add(old) }
        }
        prefs.edit().putString(key,org.json.JSONArray(failed+items.takeLast(keep)).toString()).commit()
        return if(failed.isEmpty()) name else "$name (saved; some older copies could not be removed)"
    }
}
