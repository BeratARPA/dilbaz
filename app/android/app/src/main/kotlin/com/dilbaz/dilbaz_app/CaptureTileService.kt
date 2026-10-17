package com.dilbaz.dilbaz_app

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/** The quick settings tile (A19): opens the "Söyleyemedim" capture page. */
class CaptureTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        tile.label = HomeWidgetPlugin.getData(this).getString(AppLinks.CAPTURE_LABEL, null)
            ?: getString(R.string.capture_tile)
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) unlockAndRun { open() } else open()
    }

    private fun open() {
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                HomeWidgetLaunchIntent.getActivity(
                    this,
                    MainActivity::class.java,
                    AppLinks.capture,
                ),
            )
        } else {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = AppLinks.capture
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
