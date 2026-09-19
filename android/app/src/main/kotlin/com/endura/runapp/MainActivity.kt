package com.endura.runapp

import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "endura/social_share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareImageTo" -> {
                        val path = call.argument<String>("path")
                        val pkg = call.argument<String>("package")
                        if (path == null || pkg == null) {
                            result.error("bad_args", "path and package are required", null)
                        } else {
                            result.success(shareImageTo(path, pkg))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Returns false when the target app isn't installed so Dart can fall
     *  back to the system share sheet. */
    private fun shareImageTo(path: String, pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            val uri = FileProvider.getUriForFile(
                this, "$packageName.social_share_provider", File(path)
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                setPackage(pkg)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
