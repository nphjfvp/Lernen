package com.pius.lernen

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Update aus der App (siehe lib/services/update_installer_io.dart):
        // die heruntergeladene APK an den System-Installer übergeben.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lernen/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("args", "Pfad fehlt", null)
                    } else {
                        result.success(installApk(File(path)))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** "started", "needsPermission" oder "failed". */
    private fun installApk(file: File): String {
        if (!file.exists()) return "failed"
        // Ab Android 8 muss man einmal erlauben, dass Lernen Apps installiert.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            return try {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                "needsPermission"
            } catch (e: Exception) {
                "failed"
            }
        }
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "started"
        } catch (e: Exception) {
            "failed"
        }
    }
}
