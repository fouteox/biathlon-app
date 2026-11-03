package com.fouteox.biathlon

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as BiathlonApplication
        setContent { BiathlonApp(app.ibu, app.wikidata, app.server, app.favorites, app.notificationSettings, app.liveUpdates) }
    }
}
