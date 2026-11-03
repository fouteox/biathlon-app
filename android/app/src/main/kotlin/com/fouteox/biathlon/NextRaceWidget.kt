package com.fouteox.biathlon

import android.content.Context
import android.content.Intent
import android.os.Build
import android.text.format.DateFormat
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.components.Scaffold
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.fouteox.biathlon.kit.BiathlonEvent
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.HomeFeed
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.featuredRaces
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

/** What the widget shows: the race and its event, or why there is none. */
data class NextRaceEntry(val race: Competition?, val event: BiathlonEvent?, val isUnavailable: Boolean = false) {
    companion object {
        /** The calendar couldn't load. */
        val UNAVAILABLE = NextRaceEntry(race = null, event = null, isUnavailable = true)

        fun of(feed: HomeFeed): NextRaceEntry = feed.upcomingRace.let { NextRaceEntry(it, it?.let(feed::event)) }

        /** A fictional race, for the widget picker's preview, as on iOS. */
        fun sample(now: Instant, isLive: Boolean = false) = NextRaceEntry(
            Competition("BT2627SWRLCP01SMSP", "Men 10 km Sprint", if (isLive) now else now + Duration.ofDays(2), isLive = isLive),
            BiathlonEvent("BT2627SWRLCP01", "Kontiolahti", now, now + Duration.ofDays(4), "FIN"),
        )
    }
}

/**
 * The live race, otherwise the next one, on the home screen, as the iOS app's widget. It reads
 * the calendar through the server's cache, as the app does, each time it loads: then at the time
 * the feed gives (`HomeFeed.widgetReloadTime`), which [Reload] keeps.
 */
class NextRaceWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = context.applicationContext as BiathlonApplication
        // Glance calls this on the main thread.
        val (entry, reload) = withContext(Dispatchers.Default) { load(app.ibu, Instant.now()) }
        scheduleReload(context, reload)
        provideContent { GlanceTheme { NextRaceContent(entry) } }
    }

    /** The widget picker's preview, on Android 15 and later. */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent { GlanceTheme { NextRaceContent(NextRaceEntry.sample(Instant.now())) } }
    }

    /** Loads every placed widget again, once the device is online. */
    class Reload(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
        override suspend fun doWork(): Result {
            NextRaceWidget().updateAll(applicationContext)
            return Result.success()
        }
    }

    class Receiver : GlanceAppWidgetReceiver() {
        override val glanceAppWidget: GlanceAppWidget = NextRaceWidget()

        /** The last widget removed: nothing left to reload. */
        override fun onDisabled(context: Context) {
            super.onDisabled(context)
            WorkManager.getInstance(context).cancelUniqueWork(RELOAD)
        }
    }

    companion object {
        const val RELOAD = "next-race-widget"
        private const val TAG = "NextRaceWidget"

        /** After a failed load, as often as while a race is live. */
        private val RETRY_INTERVAL = Duration.ofSeconds(HomeFeed.WIDGET_LIVE_INTERVAL_SECONDS)

        private val PREVIEW_VERSION = intPreferencesKey("preview-version")
        private val Context.store by preferencesDataStore("next-race-widget")

        /** The entry for `now`, and when to load the next one. */
        suspend fun load(ibu: IbuClient, now: Instant): Pair<NextRaceEntry, Instant> = when (val feed = attempt { ibu.featuredRaces(now) }) {
            is Loadable.Loaded -> NextRaceEntry.of(feed.value) to feed.value.widgetReloadTime(now)
            else -> NextRaceEntry.UNAVAILABLE to now + RETRY_INTERVAL
        }

        /** One reload for every placed widget, each load replacing the last one's. */
        fun scheduleReload(context: Context, at: Instant, now: Instant = Instant.now()) {
            val request = OneTimeWorkRequestBuilder<Reload>()
                .setInitialDelay(Duration.between(now, at).coerceAtLeast(Duration.ZERO))
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(RELOAD, ExistingWorkPolicy.REPLACE, request)
        }

        /** What a tap opens without a race to show: the app, as from its icon. */
        fun openApp(context: Context): Intent = Intent(context, MainActivity::class.java)

        /**
         * Publishes the widget picker's preview, on Android 15 and later, once for each version of
         * the app: Android limits how often an app can, and keeps the preview published
         * (https://developer.android.com/reference/kotlin/androidx/glance/appwidget/GlanceAppWidgetManager#setWidgetPreviews(kotlin.reflect.KClass,androidx.collection.IntSet)).
         * A failure only leaves the picker without a preview, until the next launch.
         */
        suspend fun publishPreview(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
            if (context.store.data.first()[PREVIEW_VERSION] == BuildConfig.VERSION_CODE) return
            try {
                val result = withContext(Dispatchers.Default) { GlanceAppWidgetManager(context).setWidgetPreviews(Receiver::class) }
                if (result == GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_SUCCESS) {
                    context.store.edit { it[PREVIEW_VERSION] = BuildConfig.VERSION_CODE }
                } else {
                    Log.w(TAG, "Widget preview rate limited")
                }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (error: Exception) {
                Log.e(TAG, "Widget preview not published", error)
            }
        }
    }
}

/** The widget's content, after the iOS widget's: the live race or the next one, its place and its start; a tap opens it. */
@Composable
fun NextRaceContent(entry: NextRaceEntry) {
    val context = LocalContext.current
    val race = entry.race
    val open = race?.let { DeepLink.Race(it.id, it.shortDescription).intent(context) } ?: NextRaceWidget.openApp(context)
    Scaffold(GlanceModifier.clickable(actionStartActivity(open))) {
        Column(GlanceModifier.fillMaxSize().padding(vertical = 12.dp)) {
            if (race == null) {
                Text(
                    context.getString(if (entry.isUnavailable) R.string.unable_to_load else R.string.no_races),
                    style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.onSurfaceVariant),
                )
                return@Column
            }
            val isLive = race.state == Competition.State.LIVE
            Text(
                context.getString(if (isLive) R.string.live else R.string.next_race),
                style = TextStyle(
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (isLive) GlanceTheme.colors.error else GlanceTheme.colors.onSurfaceVariant,
                ),
            )
            Text(race.title(context.resources), style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.onSurface), maxLines = 2)
            entry.event?.let { event ->
                Text(Nation.titled(event.shortDescription, event.nation), style = TextStyle(fontSize = 14.sp, color = GlanceTheme.colors.onSurface), maxLines = 1)
            }
            Spacer(GlanceModifier.defaultWeight())
            Text(
                DateSkeleton.SHORT_START.format(race.startTime, DateFormat.is24HourFormat(context), context.resources.configuration.locales[0]),
                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.onSurface),
            )
        }
    }
}
