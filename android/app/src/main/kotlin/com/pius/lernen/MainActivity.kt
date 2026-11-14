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
        // Lernzeit-Sperre (siehe ScreenGuard.kt und lib/services/screen_guard.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lernen/screen_guard").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "usageAccess" to ScreenGuard.hasUsageAccess(this),
                            "overlay" to ScreenGuard.canOverlay(this),
                            "running" to ScreenGuardService.running,
                        ),
                    )
                    "configure" -> {
                        ScreenGuard.configure(this, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                        result.success(true)
                    }
                    "openUsageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(true)
                    }
                    "openOverlaySettings" -> {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    "installedApps" -> result.success(installedApps())
                    "usedMinutes" -> {
                        val packages = (call.argument<List<String>>("packages") ?: emptyList()).toSet()
                        val hour = call.argument<Int>("dayStartHour") ?: 4
                        val now = System.currentTimeMillis()
                        val used = ScreenGuard.usedMillis(this, packages, ScreenGuard.dayStart(now, hour), now)
                        result.success((used / 60_000).toInt())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("screen_guard", e.message, null)
            }
        }
    }

    /** Apps mit Startsymbol (ohne diese App), für die Auswahl der gesperrten Apps. */
    @Suppress("DEPRECATION")
    private fun installedApps(): List<Map<String, String>> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName to it.loadLabel(packageManager).toString() }
            .filter { it.first != packageName }
            .distinctBy { it.first }
            .map { mapOf("package" to it.first, "label" to it.second) }
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
