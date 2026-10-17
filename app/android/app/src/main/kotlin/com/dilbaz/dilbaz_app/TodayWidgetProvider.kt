package com.dilbaz.dilbaz_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The home screen widget (docs/09 §9): today's cards as the app last planned them, and
 * "Söyleyemedim". A line from another day is not shown: it would tell that day's cards.
 */
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val open = widgetData.getString(AppLinks.TODAY_OPEN, null)
            ?: context.getString(R.string.today_widget_open)
        val line = if (widgetData.getString(AppLinks.TODAY_DAY, null) == today) {
            widgetData.getString(AppLinks.TODAY_LINE, null) ?: open
        } else {
            open
        }
        val capture = widgetData.getString(AppLinks.CAPTURE_LABEL, null)
            ?: context.getString(R.string.capture_tile)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.today_widget).apply {
                setTextViewText(R.id.today_line, line)
                setTextViewText(R.id.capture, capture)
                setOnClickPendingIntent(
                    R.id.today_line,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        AppLinks.cards,
                    ),
                )
                setOnClickPendingIntent(
                    R.id.capture,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        AppLinks.capture,
                    ),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
