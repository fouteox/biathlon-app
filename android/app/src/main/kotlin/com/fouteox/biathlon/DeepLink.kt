package com.fouteox.biathlon

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * What the widget, the Live Update and the app shortcuts open in the app, under its URL scheme
 * as on iOS (Shared/DeepLink.swift): `biathlon://race/<id>?name=<IBU name>`, so that a tap lands
 * on the race and not on Home, and the shortcuts' `biathlon://next-race` and `biathlon://latest-result`.
 * The links reach MainActivity by name, which opens no other app's.
 */
sealed interface DeepLink {
    val uri: Uri

    /** A race by its ID, with the IBU's English name for a kind the app doesn't know. */
    data class Race(val id: String, val name: String) : DeepLink {
        override val uri: Uri get() = Uri.Builder().scheme(SCHEME).authority(RACE).appendPath(id).appendQueryParameter(NAME, name).build()
    }

    /** The live race, otherwise the next one. */
    data object NextRace : DeepLink {
        override val uri: Uri = Uri.Builder().scheme(SCHEME).authority(NEXT_RACE).build()
    }

    /** The latest finished race. */
    data object LatestResult : DeepLink {
        override val uri: Uri = Uri.Builder().scheme(SCHEME).authority(LATEST_RESULT).build()
    }

    /**
     * Opens the link in the app, brought back on top of its task when open, rather than in a
     * second one, where it receives the link through `onNewIntent`.
     */
    fun intent(context: Context): Intent = Intent(Intent.ACTION_VIEW, uri, context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    /** [intent], for a notification: each link its own, told apart by its data. */
    fun pendingIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(context, 0, intent(context), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    companion object {
        private const val SCHEME = "biathlon"
        private const val RACE = "race"
        private const val NEXT_RACE = "next-race"
        private const val LATEST_RESULT = "latest-result"
        private const val NAME = "name"

        /** The link an intent opens; `null` for the launcher's, or a link the app doesn't know. */
        fun of(intent: Intent): DeepLink? {
            val uri = intent.data?.takeIf { intent.action == Intent.ACTION_VIEW && it.scheme == SCHEME } ?: return null
            return when (uri.authority) {
                RACE -> uri.pathSegments.singleOrNull()?.let { Race(it, uri.getQueryParameter(NAME).orEmpty()) }
                NEXT_RACE -> NextRace
                LATEST_RESULT -> LatestResult
                else -> null
            }
        }
    }
}
