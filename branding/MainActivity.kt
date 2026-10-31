package com.noor.noor_video_calls

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val pickCode = 4711
    private var pendingPick: MethodChannel.Result? = null
    private var playing: Ringtone? = null
    private var tone: ToneGenerator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var loopTask: Runnable? = null

    // ---- documents ----------------------------------------------------------------------------------------------
    private val docCode = 4712
    private var pendingDoc: MethodChannel.Result? = null
    private var docMax = 25L * 1024 * 1024
    private val docExt = setOf("pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "rtf", "odt", "ods", "odp", "zip", "rar", "7z")
    private val docMimes = arrayOf(
        "application/pdf", "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "text/plain", "text/csv", "text/comma-separated-values", "application/csv", "application/rtf", "text/rtf",
        "application/vnd.oasis.opendocument.text", "application/vnd.oasis.opendocument.spreadsheet", "application/vnd.oasis.opendocument.presentation",
        "application/zip", "application/x-zip-compressed", "application/vnd.rar", "application/x-rar-compressed", "application/x-7z-compressed",
        "application/octet-stream"
    )

    /** Copies the picked file into the app cache (and refuses wrong types / too big files before any upload). */
    private fun copyPicked(uri: Uri): Map<String, Any?> {
        var name = "file"
        var size = -1L
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val a = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val b = c.getColumnIndex(OpenableColumns.SIZE)
                if (a >= 0) name = c.getString(a) ?: name
                if (b >= 0 && !c.isNull(b)) size = c.getLong(b)
            }
        }
        val ext = name.substringAfterLast('.', "").lowercase()
        if (!docExt.contains(ext)) return mapOf("error" to "type")
        if (size > docMax) return mapOf("error" to "toobig")
        val safe = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_")
        val f = File(cacheDir, "pick_${System.currentTimeMillis()}_$safe")
        var total = 0L
        val ins = contentResolver.openInputStream(uri) ?: return mapOf("error" to "read")
        ins.use { input ->
            f.outputStream().use { output ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > docMax) {
                        output.close()
                        f.delete()
                        return mapOf("error" to "toobig")
                    }
                    output.write(buf, 0, n)
                }
            }
        }
        return mapOf("path" to f.absolutePath, "name" to name, "size" to total)
    }

    /** Saves a finished download into the phone's public Downloads folder; returns a content:// uri the viewer apps can open. */
    private fun saveDownload(path: String, name: String, mime: String): Map<String, Any?> {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= 29) {
            val v = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v) ?: return mapOf("error" to "fail")
            try {
                val o = contentResolver.openOutputStream(uri) ?: throw Exception("no stream")
                o.use { out -> src.inputStream().use { it.copyTo(out) } }
                val d = ContentValues()
                d.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, d, null, null)
            } catch (e: Exception) {
                try {
                    contentResolver.delete(uri, null, null)
                } catch (x: Exception) {
                }
                return mapOf("error" to "fail")
            }
            return mapOf("uri" to uri.toString())
        }
        // Android 9 and older: plain file in Downloads (needs the storage permission), then registered so other apps can open it
        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) dir.mkdirs()
        val base = name.substringBeforeLast('.', name)
        val ex = name.substringAfterLast('.', "")
        var dest = File(dir, name)
        var n = 1
        while (dest.exists()) {
            dest = File(dir, if (ex.isEmpty()) "$base ($n)" else "$base ($n).$ex")
            n++
        }
        src.inputStream().use { i -> dest.outputStream().use { o -> i.copyTo(o) } }
        val v = ContentValues().apply {
            put(MediaStore.MediaColumns.DATA, dest.absolutePath)
            put(MediaStore.MediaColumns.DISPLAY_NAME, dest.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
        }
        val uri = try {
            contentResolver.insert(MediaStore.Files.getContentUri("external"), v)
        } catch (e: Exception) {
            null
        }
        return mapOf("uri" to (uri?.toString() ?: Uri.fromFile(dest).toString()))
    }

    private fun stopLoop() {
        loopTask?.let { handler.removeCallbacks(it) }
        loopTask = null
    }

    private fun stopTone() {
        try {
            tone?.stopTone()
            tone?.release()
        } catch (e: Exception) {
        }
        tone = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // screenshot / screen-recording block (FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noor/secure").setMethodCallHandler { call, result ->
            if (call.method == "set") {
                val on = call.argument<Boolean>("on") == true
                runOnUiThread {
                    if (on) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // Contact Info > Notifications: phone's own tone picker, and playing the chosen tone
        // Gallery: find the copy the app just saved, and erase it later ("also delete the saved copy from the gallery")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noor/gallery").setMethodCallHandler { call, result ->
            when (call.method) {
                "lastAdded" -> {
                    var out: String? = null
                    try {
                        val video = call.argument<Boolean>("video") == true
                        val album = call.argument<String>("album") ?: ""
                        val base = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        val bucket = if (video) MediaStore.Video.Media.BUCKET_DISPLAY_NAME else MediaStore.Images.Media.BUCKET_DISPLAY_NAME
                        val added = if (video) MediaStore.Video.Media.DATE_ADDED else MediaStore.Images.Media.DATE_ADDED
                        val idCol = if (video) MediaStore.Video.Media._ID else MediaStore.Images.Media._ID
                        contentResolver.query(base, arrayOf(idCol, added), "$bucket=?", arrayOf(album), "$added DESC")?.use { c ->
                            if (c.moveToFirst() && System.currentTimeMillis() / 1000 - c.getLong(1) <= 30) {
                                out = ContentUris.withAppendedId(base, c.getLong(0)).toString()
                            }
                        }
                    } catch (e: Exception) {
                    }
                    result.success(out)
                }
                "delete" -> {
                    var n = 0
                    val list = call.argument<List<String>>("uris") ?: emptyList()
                    for (u in list) {
                        try {
                            if (contentResolver.delete(Uri.parse(u), null, null) > 0) n++
                        } catch (e: Exception) {
                            // not ours any more (e.g. after a reinstall): the system asks for permission, so we leave it
                        }
                    }
                    result.success(n)
                }
                else -> result.notImplemented()
            }
        }
        // Documents: pick a file (system file picker), save a downloaded file into the phone's Downloads folder, open it with the app the user chooses
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noor/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    docMax = call.argument<Number>("max")?.toLong() ?: docMax
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    i.addCategory(Intent.CATEGORY_OPENABLE)
                    i.type = "*/*"
                    i.putExtra(Intent.EXTRA_MIME_TYPES, docMimes)
                    pendingDoc?.success(null)
                    pendingDoc = result
                    try {
                        startActivityForResult(i, docCode)
                    } catch (e: Exception) {
                        pendingDoc = null
                        result.success(null)
                    }
                }
                "save" -> {
                    val path = call.argument<String>("path") ?: ""
                    val name = call.argument<String>("name") ?: "file"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    Thread {
                        val out: Map<String, Any?> = try {
                            saveDownload(path, name, mime)
                        } catch (e: SecurityException) {
                            mapOf("error" to "perm")
                        } catch (e: Exception) {
                            mapOf("error" to (if (Build.VERSION.SDK_INT < 29) "perm" else "fail"))
                        }
                        runOnUiThread { result.success(out) }
                    }.start()
                }
                "exists" -> {
                    var ok = false
                    try {
                        contentResolver.openFileDescriptor(Uri.parse(call.argument<String>("uri") ?: ""), "r")?.use { ok = true }
                    } catch (e: Exception) {
                        ok = false
                    }
                    result.success(ok)
                }
                "open" -> {
                    try {
                        val i = Intent(Intent.ACTION_VIEW)
                        i.setDataAndType(Uri.parse(call.argument<String>("uri") ?: ""), call.argument<String>("mime") ?: "*/*")
                        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        val ch = Intent.createChooser(i, call.argument<String>("title") ?: "")
                        ch.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        startActivity(ch)
                        result.success("ok")
                    } catch (e: ActivityNotFoundException) {
                        result.success("noapp")
                    } catch (e: Exception) {
                        result.success("gone")
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noor/sound").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    val ringtone = call.argument<String>("type") == "ringtone"
                    val i = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                    i.putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, if (ringtone) RingtoneManager.TYPE_RINGTONE else RingtoneManager.TYPE_NOTIFICATION)
                    i.putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                    i.putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
                    val cur = call.argument<String>("uri")
                    if (!cur.isNullOrEmpty()) i.putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(cur))
                    pendingPick?.success(null)
                    pendingPick = result
                    try {
                        startActivityForResult(i, pickCode)
                    } catch (e: Exception) {
                        pendingPick = null
                        result.success(null)
                    }
                }
                "play" -> {
                    runOnUiThread {
                        try {
                            playing?.stop()
                            val type = if (call.argument<String>("type") == "ringtone") RingtoneManager.TYPE_RINGTONE else RingtoneManager.TYPE_NOTIFICATION
                            val s = call.argument<String>("uri")
                            val uri = if (s.isNullOrEmpty()) RingtoneManager.getDefaultUri(type) else Uri.parse(s)
                            val r = RingtoneManager.getRingtone(applicationContext, uri)
                            if (r != null) {
                                stopLoop()
                                val loop = call.argument<Boolean>("loop") == true
                                if (type == RingtoneManager.TYPE_RINGTONE) {
                                    // an incoming call follows the phone's RING volume / silent mode
                                    r.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                                }
                                if (Build.VERSION.SDK_INT >= 28) r.isLooping = loop
                                r.play()
                                playing = r
                                if (loop && Build.VERSION.SDK_INT < 28) {
                                    val task = object : Runnable {
                                        override fun run() {
                                            val p = playing ?: return
                                            try {
                                                if (!p.isPlaying) p.play()
                                            } catch (e: Exception) {
                                            }
                                            handler.postDelayed(this, 800)
                                        }
                                    }
                                    loopTask = task
                                    handler.postDelayed(task, 800)
                                }
                            }
                        } catch (e: Exception) {
                        }
                    }
                    result.success(null)
                }
                "stop" -> {
                    runOnUiThread {
                        stopLoop()
                        try {
                            playing?.stop()
                        } catch (e: Exception) {
                        }
                        playing = null
                    }
                    result.success(null)
                }
                // outgoing call: the "tu-tu" ringback while the other phone rings (earpiece for audio calls, loudspeaker for video calls)
                "ringback" -> {
                    runOnUiThread {
                        try {
                            stopTone()
                            val stream = if (call.argument<Boolean>("speaker") == true) AudioManager.STREAM_MUSIC else AudioManager.STREAM_VOICE_CALL
                            tone = ToneGenerator(stream, 85)
                            tone?.startTone(ToneGenerator.TONE_SUP_RINGTONE)
                        } catch (e: Exception) {
                        }
                    }
                    result.success(null)
                }
                "stopRingback" -> {
                    runOnUiThread { stopTone() }
                    result.success(null)
                }
                // call finished: busy tone (declined / not answered) or a short beep (hang up after talking)
                "endtone" -> {
                    runOnUiThread {
                        try {
                            stopTone()
                            val stream = if (call.argument<Boolean>("speaker") == true) AudioManager.STREAM_MUSIC else AudioManager.STREAM_VOICE_CALL
                            val g = ToneGenerator(stream, 85)
                            val busy = call.argument<Boolean>("busy") == true
                            val ms = if (busy) 1600 else 350
                            g.startTone(if (busy) ToneGenerator.TONE_SUP_BUSY else ToneGenerator.TONE_PROP_PROMPT, ms)
                            handler.postDelayed({
                                try {
                                    g.release()
                                } catch (e: Exception) {
                                }
                            }, (ms + 300).toLong())
                        } catch (e: Exception) {
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == docCode) {
            val r = pendingDoc
            pendingDoc = null
            if (r == null) return
            val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                r.success(null)
                return
            }
            Thread {
                val out: Any? = try {
                    copyPicked(uri)
                } catch (e: Exception) {
                    mapOf("error" to "read")
                }
                runOnUiThread { r.success(out) }
            }.start()
            return
        }
        if (requestCode == pickCode) {
            val r = pendingPick
            pendingPick = null
            if (r != null) {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    @Suppress("DEPRECATION")
                    val uri: Uri? = data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                    val name: String? = if (uri == null) null else try {
                        RingtoneManager.getRingtone(this, uri)?.getTitle(this)
                    } catch (e: Exception) {
                        null
                    }
                    r.success(mapOf("uri" to uri?.toString(), "name" to name))
                } else {
                    r.success(null)
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        stopLoop()
        stopTone()
        try {
            playing?.stop()
        } catch (e: Exception) {
        }
        super.onDestroy()
    }
}
