package com.noor.noor_video_calls

import android.app.Activity
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val pickCode = 4711
    private var pendingPick: MethodChannel.Result? = null
    private var playing: Ringtone? = null

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
                                if (Build.VERSION.SDK_INT >= 28) r.isLooping = call.argument<Boolean>("loop") == true
                                r.play()
                                playing = r
                            }
                        } catch (e: Exception) {
                        }
                    }
                    result.success(null)
                }
                "stop" -> {
                    runOnUiThread {
                        try {
                            playing?.stop()
                        } catch (e: Exception) {
                        }
                        playing = null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
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
        try {
            playing?.stop()
        } catch (e: Exception) {
        }
        super.onDestroy()
    }
}
