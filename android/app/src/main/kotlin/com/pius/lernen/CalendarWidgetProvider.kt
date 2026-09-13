package com.pius.lernen

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Startbildschirm-Widget: zeigt die nächste Vorlesung, eine Lernerinnerung
 * (fällige Karten heute) und einen kleinen Klausur-Countdown. Die drei
 * Textzeilen werden von Dart aus über [HomeWidget.saveWidgetData] befüllt
 * (siehe lib/services/home_widget_service.dart) – dieser Provider liest sie
 * nur aus den SharedPreferences und zeigt sie an.
 */
class CalendarWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.calendar_widget_layout).apply {
            setTextViewText(
                R.id.widget_lecture,
                widgetData.getString("widget_lecture", null) ?: "Keine Vorlesung geplant",
            )
            setTextViewText(
                R.id.widget_reminder,
                widgetData.getString("widget_reminder", null) ?: "Öffnen zum Lernen",
            )
            setTextViewText(
                R.id.widget_countdown,
                widgetData.getString("widget_countdown", null) ?: "Keine Klausur geplant",
            )
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            setOnClickPendingIntent(R.id.widget_root, pendingIntent)
          }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
