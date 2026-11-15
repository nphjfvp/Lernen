package com.pius.lernen

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Lernzeit-Sperre: Regeln und heutiges Guthaben (von der Flutter-Seite, siehe
 * lib/services/screen_guard.dart), Zeitmessung über die Nutzungsstatistik.
 */
object ScreenGuard {
    private const val PREFS = "screen_guard"

    fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun configure(context: Context, args: Map<*, *>) {
        val packages = (args["packages"] as? List<*>)?.mapNotNull { it?.toString() } ?: emptyList()
        prefs(context).edit()
            .putBoolean("enabled", args["enabled"] == true)
            .putString("packages", packages.joinToString(","))
            .putInt("dayStartHour", (args["dayStartHour"] as? Number)?.toInt() ?: 4)
            .putInt("freeMinutes", (args["freeMinutes"] as? Number)?.toInt() ?: 30)
            .putString("dayKey", args["dayKey"]?.toString() ?: "")
            .putInt("allowedMinutes", (args["allowedMinutes"] as? Number)?.toInt() ?: 30)
            .putBoolean("unlimited", args["unlimited"] == true)
            .putString("nextStep", args["nextStep"]?.toString() ?: "")
            .putInt("otherUsedMinutes", (args["otherUsedMinutes"] as? Number)?.toInt() ?: 0)
            .apply()
        if (isEnabled(context)) ScreenGuardService.start(context) else ScreenGuardService.stop(context)
    }

    fun isEnabled(context: Context): Boolean {
        val p = prefs(context)
        return p.getBoolean("enabled", false) && packages(context).isNotEmpty()
    }

    fun packages(context: Context): Set<String> =
        (prefs(context).getString("packages", "") ?: "").split(",").filter { it.isNotBlank() }.toSet()

    fun dayStartHour(context: Context): Int = prefs(context).getInt("dayStartHour", 4)

    /** Beginn des Lerntags (z.B. heute 4:00, vor 4:00 gestern 4:00). */
    fun dayStart(now: Long, startHour: Int): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, startHour)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis > now) cal.add(Calendar.DAY_OF_MONTH, -1)
        return cal.timeInMillis
    }

    fun dayKey(now: Long, startHour: Int): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date(dayStart(now, startHour)))

    /** Erlaubte Minuten heute; null = unbegrenzt. Ein Stand von gestern gilt nicht – dann nur die freien Minuten. */
    fun allowedMinutes(context: Context, now: Long): Int? {
        val p = prefs(context)
        val today = dayKey(now, dayStartHour(context))
        if (p.getString("dayKey", "") != today) return p.getInt("freeMinutes", 30)
        if (p.getBoolean("unlimited", false)) return null
        return p.getInt("allowedMinutes", 30)
    }

    /** Heute auf anderen Geräten (z.B. am PC) genutzte Minuten – gemeinsames Zeitkonto. */
    fun otherUsedMinutes(context: Context, now: Long): Int {
        val p = prefs(context)
        if (p.getString("dayKey", "") != dayKey(now, dayStartHour(context))) return 0
        return p.getInt("otherUsedMinutes", 0)
    }

    fun nextStep(context: Context): String = prefs(context).getString("nextStep", "") ?: ""

    fun hasUsageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun canOverlay(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /** Zeit im Vordergrund in [packages] zwischen [from] und [to] (ms). */
    @Suppress("DEPRECATION")
    fun usedMillis(context: Context, packages: Set<String>, from: Long, to: Long): Long {
        if (packages.isEmpty() || !hasUsageAccess(context)) return 0
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(from, to)
        val event = UsageEvents.Event()
        val since = HashMap<String, Long>()
        var total = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            if (pkg !in packages) continue
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> if (!since.containsKey(pkg)) since[pkg] = event.timeStamp
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val start = since.remove(pkg) ?: from
                    total += (event.timeStamp - start).coerceAtLeast(0)
                }
            }
        }
        // Noch offen: bis jetzt zählen.
        for (start in since.values) total += (to - start).coerceAtLeast(0)
        return total
    }
}

/** Startet die Sperre nach einem Neustart wieder. */
class ScreenGuardBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (ScreenGuard.isEnabled(context)) ScreenGuardService.start(context)
    }
}

/**
 * Läuft im Vordergrund (mit Benachrichtigung): prüft jede Sekunde, welche App
 * vorn ist. Ist es eine gesperrte und das Guthaben aufgebraucht, legt er einen
 * Sperrbildschirm darüber.
 */
class ScreenGuardService : Service() {
    companion object {
        private const val CHANNEL = "lernzeit_sperre"
        private const val NOTIFICATION_ID = 4711
        @Volatile var running = false

        fun start(context: Context) {
            val intent = Intent(context, ScreenGuardService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
            } catch (e: Exception) {
                // z.B. Start aus dem Hintergrund verboten – beim nächsten Öffnen der App erneut.
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScreenGuardService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastEventAt = 0L
    private var foreground: String? = null
    private var overlay: View? = null
    private var usedCache = 0L
    private var usedCacheAt = 0L
    private var lastNotified = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        createChannel()
        val notification = buildNotification("Lernzeit-Sperre aktiv")
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0,
            )
        } catch (e: Exception) {
            stopSelf()
            return
        }
        // Die letzten 10 Minuten lesen, damit eine schon offene App erkannt wird.
        lastEventAt = System.currentTimeMillis() - 600_000
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        hideOverlay()
        running = false
        super.onDestroy()
    }

    private val tick = object : Runnable {
        override fun run() {
            try {
                check()
            } catch (e: Exception) {
                // Nie abstürzen – nächste Runde.
            }
            handler.postDelayed(this, 1000)
        }
    }

    @Suppress("DEPRECATION")
    private fun check() {
        if (!ScreenGuard.isEnabled(this)) {
            stopSelf()
            return
        }
        val now = System.currentTimeMillis()
        // Welche App ist vorn? (Ereignisse seit der letzten Runde)
        if (ScreenGuard.hasUsageAccess(this)) {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val events = usm.queryEvents(lastEventAt, now)
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> foreground = event.packageName
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> if (foreground == event.packageName) foreground = null
                }
            }
            lastEventAt = now
        }
        val packages = ScreenGuard.packages(this)
        val front = foreground
        val allowed = ScreenGuard.allowedMinutes(this, now)
        val start = ScreenGuard.dayStart(now, ScreenGuard.dayStartHour(this))
        // Genutzte Zeit: alle 15 s neu aus der Statistik, dazwischen mitzählen.
        if (now - usedCacheAt > 15_000 || usedCacheAt < start) {
            usedCache = ScreenGuard.usedMillis(this, packages, start, now)
            usedCacheAt = now
        } else if (front != null && front in packages) {
            usedCache += 1000
        }
        // Gemeinsames Zeitkonto: was andere Geräte heute schon genutzt haben, zählt mit.
        val other = ScreenGuard.otherUsedMinutes(this, now)
        val usedMinutes = (usedCache / 60_000).toInt() + other
        val blocked = allowed != null && usedCache + other * 60_000L >= allowed * 60_000L
        if (front != null && front in packages && blocked) {
            showOverlay(usedMinutes, allowed ?: 0)
        } else {
            hideOverlay()
        }
        if (now - lastNotified > 30_000) {
            lastNotified = now
            val text = if (allowed == null) "Heute unbegrenzt – gut gelernt!" else "Heute $usedMinutes von $allowed Minuten genutzt"
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, buildNotification(text))
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(CHANNEL, "Lernzeit-Sperre", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Zeigt, wie viel Zeit in den gesperrten Apps heute übrig ist."
            setShowBadge(false)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun buildNotification(text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_lernzeit)
            .setContentTitle("Lernzeit-Sperre")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent())
            .build()

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

    private fun showOverlay(usedMinutes: Int, allowed: Int) {
        if (overlay != null || !ScreenGuard.canOverlay(this)) return
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F2121620"))
            setPadding(dp(32), dp(48), dp(32), dp(48))
            isClickable = true
            isFocusable = true
        }
        fun text(value: String, size: Float, bold: Boolean = false, color: Int = Color.WHITE) = TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
            if (bold) typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(6), 0, dp(6))
        }
        fun button(label: String, filled: Boolean, onClick: () -> Unit) = Button(this).apply {
            text = label
            isAllCaps = false
            textSize = 16f
            setTextColor(if (filled) Color.WHITE else Color.parseColor("#C7D2FE"))
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                if (filled) setColor(Color.parseColor("#5C6BC0")) else setStroke(dp(1), Color.parseColor("#7986CB"))
            }
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(52)).apply {
                topMargin = dp(12)
            }
        }
        root.addView(text("📚", 48f))
        root.addView(text("Lernzeit aufgebraucht", 24f, bold = true))
        root.addView(text("Heute $usedMinutes von $allowed Minuten genutzt.", 16f, color = Color.parseColor("#C5CAE9")))
        val step = ScreenGuard.nextStep(this)
        if (step.isNotEmpty()) root.addView(text(step, 16f, color = Color.parseColor("#E8EAF6")))
        root.addView(
            text(
                "Auf einem anderen Gerät gelernt? Lern-App öffnen – der Abgleich bringt das Guthaben mit. " +
                    "Die Zeit teilen sich Handy und PC.",
                13f,
                color = Color.parseColor("#9FA8DA"),
            ),
        )
        root.addView(button("Zur Lern-App", true) {
            hideOverlay()
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        })
        root.addView(button("Zum Startbildschirm", false) {
            hideOverlay()
            startActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        })
        try {
            wm.addView(root, params)
            overlay = root
        } catch (e: Exception) {
            overlay = null
        }
    }

    private fun hideOverlay() {
        val view = overlay ?: return
        overlay = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(view)
        } catch (e: Exception) {
            // schon weg
        }
    }
}
