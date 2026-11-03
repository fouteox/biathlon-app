package com.fouteox.biathlon

import android.content.Context
import androidx.glance.appwidget.testing.unit.hasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasText
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.featuredRaces
import com.fouteox.biathlon.kit.sample
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respondError
import io.ktor.http.HttpStatusCode
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** The "Next race" widget, on the fictional World Cup, as the iOS app's (Widgets/NextRaceWidget.swift). */
@RunWith(RobolectricTestRunner::class)
class NextRaceWidgetTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val now = Instant.now()

    @Test
    fun loadsTheNextRaceAndWhenToReload() = runBlocking {
        val client = IbuClient.sample(now)
        val feed = client.featuredRaces(now)
        val (entry, reload) = NextRaceWidget.load(client, now)
        assertEquals(feed.upcomingRace, entry.race)
        assertEquals(feed.event(checkNotNull(feed.upcomingRace)), entry.event)
        assertEquals(feed.widgetReloadTime(now), reload)
    }

    /** As often as while a race is live, after a failed load. */
    @Test
    fun saysWhenTheCalendarCannotLoad() = runBlocking {
        val failing = IbuClient(httpClient = HttpClient(MockEngine { respondError(HttpStatusCode.ServiceUnavailable) }))
        val (entry, reload) = NextRaceWidget.load(failing, now)
        assertEquals(NextRaceEntry.UNAVAILABLE, entry)
        assertEquals(now + Duration.ofMinutes(15), reload)
    }

    @Test
    fun showsTheNextRaceAndOpensIt() = runGlanceAppWidgetUnitTest {
        setContext(context)
        val entry = NextRaceEntry.sample(now)
        val race = checkNotNull(entry.race)
        provideComposable { NextRaceContent(entry) }
        onNode(hasText("Next race")).assertExists()
        onNode(hasText("Men's Sprint")).assertExists()
        onNode(hasText("🇫🇮 Kontiolahti")).assertExists()
        onNode(hasText(DateSkeleton.SHORT_START.format(race.startTime, android.text.format.DateFormat.is24HourFormat(context), context.resources.configuration.locales[0])))
            .assertExists()
        onNode(hasStartActivityClickAction(DeepLink.Race(race.id, race.shortDescription).intent(context))).assertExists()
    }

    @Test
    fun saysWhenTheRaceIsLive() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable { NextRaceContent(NextRaceEntry.sample(now, isLive = true)) }
        onNode(hasText("Live")).assertExists()
        onNode(hasText("Next race")).assertDoesNotExist()
    }

    /** Without a race to show, a tap opens the app. */
    @Test
    fun saysWhenNoRaceIsAhead() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable { NextRaceContent(NextRaceEntry(race = null, event = null)) }
        onNode(hasText("No races")).assertExists()
        onNode(hasStartActivityClickAction(NextRaceWidget.openApp(context))).assertExists()
    }

    @Test
    fun saysWhenTheCalendarIsUnavailable() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable { NextRaceContent(NextRaceEntry.UNAVAILABLE) }
        onNode(hasText("Unable to load")).assertExists()
    }

    /** The widget loads again at the time its feed gives, once the device is online. */
    @Test
    fun reloadsAtTheTimeTheFeedGives() {
        WorkManager.getInstance(context).cancelAllWork().result.get()
        val reload = now + Duration.ofMinutes(40)
        NextRaceWidget.scheduleReload(context, reload, now)
        val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork(NextRaceWidget.RELOAD).get().single()
        assertEquals(WorkInfo.State.ENQUEUED, work.state)
        assertTrue(work.constraints.requiredNetworkType == NetworkType.CONNECTED)
        assertEquals(reload.toEpochMilli().toDouble(), work.nextScheduleTimeMillis.toDouble(), 1_000.0)
    }
}
