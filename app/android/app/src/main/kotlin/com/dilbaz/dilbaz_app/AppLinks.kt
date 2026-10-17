package com.dilbaz.dilbaz_app

import android.net.Uri

/** Where the widget and the tile open the app; the app routes them (A19, docs/09 §9). */
object AppLinks {
    val cards: Uri = Uri.parse("dilbaz://cards")
    val capture: Uri = Uri.parse("dilbaz://capture")

    /** Keys the app writes with home_widget's saveWidgetData. */
    const val TODAY_LINE = "today_line"
    const val TODAY_DAY = "today_day"
    const val TODAY_OPEN = "today_open"
    const val CAPTURE_LABEL = "capture_label"
}
