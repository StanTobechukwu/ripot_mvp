package com.nduaguba.report

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** SAF grants access only to the folder selected by the user. No storage permission. */
class LogbookFiles(private val activity: Activity, channel: MethodChannel) : MethodChannel.MethodCallHandler {
    companion object { const val REQUEST_FOLDER = 8124; const val LIMIT = 40 * 1024 * 1024 }
    private val prefs = activity.getSharedPreferences("ripot_logbook_folder", Activity.MODE_PRIVATE)
    private val executor = Executors.newSingleThreadExecutor()
    private var selection: MethodChannel.Result? = null
    init { channel.setMethodCallHandler(this) }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "location" -> result.success(prefs.getString("tree", null))
            "chooseFolder" -> {
                if (selection != null) { result.error("BUSY", "Folder selection is already open", null); return }
                selection = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }
                try { activity.startActivityForResult(intent, REQUEST_FOLDER) }
                catch (_: Exception) { selection = null; result.error("FOLDER", "The document picker could not be opened", null) }
            }
            "writeBackup" -> {
                val bytes = call.arguments as? ByteArray
                if (bytes == null || bytes.isEmpty() || bytes.size > LIMIT) { result.error("SIZE", "Invalid backup size", null); return }
                executor.execute {
                    try { val warning = write(bytes); activity.runOnUiThread { result.success(warning) } }
                    catch (_: Exception) { activity.runOnUiThread { result.error("BACKUP", "Backup could not be saved and checked. Check space or choose the folder again. Existing backups were kept.", null) } }
                }
            }
            else -> result.notImplemented()
        }
    }
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_FOLDER) return false
        val result = selection ?: return true
        selection = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        try {
            val flags = ((data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
            activity.contentResolver.takePersistableUriPermission(uri, flags)
            if (!prefs.edit().putString("tree", uri.toString()).commit()) throw IllegalStateException()
            result.success(uri.toString())
        } catch (_: Exception) { result.error("PERMISSION", "Choose a folder that permits reading and writing", null) }
        return true
    }
    private data class Child(val uri: Uri, val name: String)
    private fun children(tree: Uri): List<Child> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val out = mutableListOf<Child>()
        activity.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) out.add(Child(DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0)), cursor.getString(1)))
        } ?: throw IllegalStateException("Could not list folder")
        return out
    }
    private fun read(uri: Uri): ByteArray {
        val output = ByteArrayOutputStream()
        activity.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size() + count > LIMIT) throw IllegalStateException("Oversize backup")
                output.write(buffer, 0, count)
            }
        } ?: throw IllegalStateException("Could not read backup")
        return output.toByteArray()
    }
    private fun write(bytes: ByteArray): String? {
        val tree = Uri.parse(prefs.getString("tree", null) ?: throw IllegalStateException("Choose a folder"))
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val before = children(tree)
        // A fixed-width timestamp plus a UUID prevents name collisions across devices.
        val stem = "ripot-logbook-${System.currentTimeMillis().toString().padStart(16, '0')}-${java.util.UUID.randomUUID()}"
        var pending: Uri? = null
        var complete: Uri? = null
        try {
            pending = DocumentsContract.createDocument(activity.contentResolver, parent, "application/octet-stream", "$stem.pending") ?: throw IllegalStateException()
            activity.contentResolver.openOutputStream(pending, "wt")?.use { output -> output.write(bytes); output.flush() } ?: throw IllegalStateException()
            if (!read(pending).contentEquals(bytes)) throw IllegalStateException("Write verification failed")
            complete = DocumentsContract.renameDocument(activity.contentResolver, pending, "$stem.ripotbackup") ?: throw IllegalStateException("Provider cannot rename backup")
            if (!read(complete).contentEquals(bytes)) throw IllegalStateException("Read verification failed")
        } catch (e: Exception) {
            // Never touch previous completed files if writing or verification fails.
            try { (complete ?: pending)?.let { DocumentsContract.deleteDocument(activity.contentResolver, it) } } catch (_: Exception) { }
            throw e
        }
        // Only files created by this installation in this selected tree are managed.
        // After a reinstall, existing backups remain untouched until re-adopted explicitly.
        val key = "managed:${tree}"
        val owned = prefs.getStringSet(key, emptySet())!!.toMutableSet()
        val previous = before.filter { owned.contains(it.uri.toString()) }.sortedByDescending { it.name }
        val keep = setOfNotNull(complete?.toString(), previous.firstOrNull()?.uri?.toString())
        var cleanupFailed = false
        for (old in previous.drop(1)) {
            try { if (!DocumentsContract.deleteDocument(activity.contentResolver, old.uri)) cleanupFailed = true else owned.remove(old.uri.toString()) }
            catch (_: Exception) { cleanupFailed = true }
        }
        owned.addAll(keep)
        // Persist the new file before declaring rotation complete; old valid files
        // stay discoverable in Files even if app settings cannot be written.
        if (!prefs.edit().putStringSet(key, owned).commit()) cleanupFailed = true
        return if (cleanupFailed) "Backup saved and checked. Some older backups could not be removed; check the selected folder." else null
    }
}
