package com.fouteox.biathlon

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow

class MainActivity : ComponentActivity() {
    /** The link the app opened with, then those that bring it back, each opened once. */
    private val links = Channel<DeepLink>(Channel.CONFLATED)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Recreated, the app keeps the screens it showed rather than opening its link again.
        if (savedInstanceState == null) open(intent)
        val app = application as BiathlonApplication
        setContent {
            BiathlonApp(app.ibu, app.wikidata, app.server, app.favorites, app.notificationSettings, app.liveUpdates, links.receiveAsFlow())
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        open(intent)
    }

    private fun open(intent: Intent) {
        DeepLink.of(intent)?.let(links::trySend)
    }
}
