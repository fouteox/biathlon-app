package com.fouteox.biathlon

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import androidx.core.content.getSystemService
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.LiveUpdate
import com.fouteox.biathlon.kit.RaceLiveState
import com.fouteox.biathlon.kit.ServerClient
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.io.File
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** The races followed live, on the states the server publishes for them (server/test/live.test.ts, "Live Update topics"). */
@RunWith(RobolectricTestRunner::class)
class LiveUpdatesTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val raceId = "BT2627SWRLCP01SMSP"
    private val topic = "race-$raceId"
    private val now = Instant.now()
    private val start = now + Duration.ofMinutes(10)

    private val live = RaceLiveState(
        Competition.State.LIVE,
        start,
        listOf(
            RaceLiveState.Leader("1", "PERROT E.", "FRA", "12:41.6"),
            RaceLiveState.Leader("2", "LAEGREID S.", "NOR", "+4.2"),
            RaceLiveState.Leader("3", "SAMUELSSON S.", "SWE", "+9.8"),
        ),
    )

    /** What `GET /v1/races/:id/channels/fcm` answers. */
    private var channel: Pair<HttpStatusCode, String> = HttpStatusCode.NotFound to """{"error":"no channel for this race"}"""

    private val subscriptions = mutableListOf<String>()

    private val topics = object : LiveUpdates.Topics {
        override fun subscribe(topic: String) {
            subscriptions += "+$topic"
        }

        override fun unsubscribe(topic: String) {
            subscriptions += "-$topic"
        }
    }

    private val liveUpdates = LiveUpdates(
        context,
        ServerClient(
            Url("https://server.example/"),
            HttpClient(
                MockEngine { request ->
                    assertEquals("https://server.example/v1/races/$raceId/channels/fcm", request.url.toString())
                    respond(channel.second, channel.first)
                },
            ),
        ),
        topics,
        PreferenceDataStoreFactory.create { File(Files.createTempDirectory("live").toFile(), "live.preferences_pb") },
    )

    @Before
    fun allowNotifications() {
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        RaceNotifications.createChannels(context)
    }

    private fun stateJson(state: RaceLiveState) = """{"phase":"${state.phase.name.lowercase()}","startTime":${state.startTime.epochSecond - 978_307_200},"leaders":[${
        state.leaders.joinToString(",") { """{"rank":"${it.rank}","name":"${it.name}","nation":"${it.nation}","result":"${it.result}"}""" }
    }]}"""

    /**
     * What Android promotes to a Live Update, as its guide lists it: Robolectric's Android 16
     * predates the guide's rules (its `hasPromotableCharacteristics` still asks for a colorized
     * notification), so each is checked here.
     */
    private fun assertPromotable(notification: Notification) {
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_REQUEST_PROMOTED_ONGOING))
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertTrue(notification.extras.getString(Notification.EXTRA_TITLE)?.isNotEmpty() == true)
        assertFalse(notification.extras.getBoolean(Notification.EXTRA_COLORIZED))
        assertTrue(notification.extras.getString(Notification.EXTRA_TEMPLATE) in listOf(null, Notification.BigTextStyle::class.java.name))
        val channel = checkNotNull(context.getSystemService<NotificationManager>()).getNotificationChannel(notification.channelId)
        assertTrue(channel.importance > NotificationManager.IMPORTANCE_MIN)
    }

    private fun posted(): List<Notification> = shadowOf(checkNotNull(context.getSystemService<NotificationManager>())).allNotifications

    private fun followed() = runBlocking { liveUpdates.followed.first() }

    private fun follow() = runBlocking { liveUpdates.follow(raceId, "Men's 10km Sprint", start) }

    @Test
    fun showsAFollowedRacesStateAtOnceAsALiveUpdate() {
        channel = HttpStatusCode.OK to """{"channelId":"$topic","state":${stateJson(live)},"timestamp":${now.epochSecond}}"""
        follow()
        assertEquals(setOf(raceId), followed())
        assertEquals(listOf("+$topic"), subscriptions)
        val notification = posted().single()
        assertEquals(RaceNotifications.LIVE_UPDATE_CHANNEL, notification.channelId)
        assertPromotable(notification)
        assertEquals("Men's Sprint", notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Live", notification.extras.getString(Notification.EXTRA_SUB_TEXT))
        assertEquals("1 🇫🇷 PERROT E. 12:41.6", notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(
            "1 🇫🇷 PERROT E. 12:41.6\n2 🇳🇴 LAEGREID S. +4.2\n3 🇸🇪 SAMUELSSON S. +9.8",
            notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString(),
        )
        assertEquals("FRA", notification.shortCriticalText)
        assertEquals(listOf("Unpin"), notification.actions.map { it.title.toString() })
        // The action and the dismissal both unpin the race, told apart from the others by its ID.
        val unpin = shadowOf(notification.actions.single().actionIntent).savedIntent
        assertEquals(raceId, unpin.data?.schemeSpecificPart)
        assertEquals(LiveUpdates.UnpinReceiver::class.java.name, unpin.component?.className)
        assertEquals(notification.actions.single().actionIntent, notification.deleteIntent)
    }

    @Test
    fun countsDownToTheStartUntilSomeoneLeads() {
        channel = HttpStatusCode.OK to
            """{"channelId":"$topic","state":${stateJson(RaceLiveState.demo(start)[0])},"timestamp":${now.epochSecond}}"""
        follow()
        val notification = posted().single()
        assertPromotable(notification)
        assertTrue(notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString().startsWith("Start "))
        assertEquals(start.epochSecond * 1000, notification.`when`)
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN))
        assertNull(notification.shortCriticalText)
    }

    @Test
    fun waitsForTheTopicToOpenBeforeTheStart() {
        follow()
        assertEquals(setOf(raceId), followed())
        assertEquals(listOf("+$topic"), subscriptions)
        assertEquals(emptyList<Notification>(), posted())
    }

    @Test
    fun keepsFollowingWhenTheServerIsDown() {
        channel = HttpStatusCode.ServiceUnavailable to ""
        follow()
        assertEquals(setOf(raceId), followed())
        assertEquals(emptyList<Notification>(), posted())
    }

    @Test
    fun doesNotFollowARaceOver() {
        channel = HttpStatusCode.Gone to """{"state":${stateJson(live)},"dismissalDate":${now.epochSecond + 1800}}"""
        assertThrows(LiveUpdates.RaceOverException::class.java) { follow() }
        assertEquals(emptySet<String>(), followed())
        assertEquals(listOf("+$topic", "-$topic"), subscriptions)
        assertEquals(emptyList<Notification>(), posted())
    }

    @Test
    fun showsOnlyAStateNewerThanTheOneOnScreen() = runBlocking {
        follow()
        val later = LiveUpdate.Update(raceId, live, now)
        liveUpdates.receive(later)
        liveUpdates.receive(LiveUpdate.Update(raceId, RaceLiveState.demo(start)[0], now - Duration.ofSeconds(60)))
        assertEquals("1 🇫🇷 PERROT E. 12:41.6", posted().single().extras.getCharSequence(Notification.EXTRA_TEXT).toString())
    }

    @Test
    fun leavesTheTopicOfARaceNoLongerFollowed() = runBlocking {
        liveUpdates.receive(LiveUpdate.Update(raceId, live, now))
        assertEquals(listOf("-$topic"), subscriptions)
        assertEquals(emptyList<Notification>(), posted())
    }

    @Test
    fun showsTheResultUntilItsDismissalThenForgetsTheRace() = runBlocking {
        follow()
        liveUpdates.receive(LiveUpdate.Update(raceId, live, now))
        val result = RaceLiveState.demoResult(start)
        liveUpdates.receive(LiveUpdate.End(raceId, result, now + Duration.ofMinutes(30), now + Duration.ofMinutes(1)), now)
        val notification = posted().single()
        assertFalse(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertFalse(notification.extras.getBoolean(Notification.EXTRA_REQUEST_PROMOTED_ONGOING))
        assertEquals(Duration.ofMinutes(30).toMillis(), notification.timeoutAfter)
        assertEquals("Finished", notification.extras.getString(Notification.EXTRA_SUB_TEXT))
        assertEquals(emptySet<String>(), followed())
        assertEquals(listOf("+$topic", "-$topic"), subscriptions)
    }

    /** A cancellation called off: its end, delivered late, is older than the reinstated race's state. */
    @Test
    fun keepsFollowingARaceReinstatedBeforeItsEndArrives() = runBlocking {
        follow()
        liveUpdates.receive(LiveUpdate.Update(raceId, live, now))
        liveUpdates.receive(LiveUpdate.End(raceId, RaceLiveState(Competition.State.CANCELLED, start, emptyList()), now + Duration.ofMinutes(30), now - Duration.ofMinutes(1)), now)
        assertEquals(setOf(raceId), followed())
        assertEquals("Live", posted().single().extras.getString(Notification.EXTRA_SUB_TEXT))
    }

    /** After a restart, or a state that arrived before the notification permission: shown again on return. */
    @Test
    fun showsAgainAStateNoLongerOnScreen() = runBlocking {
        channel = HttpStatusCode.OK to """{"channelId":"$topic","state":${stateJson(live)},"timestamp":${now.epochSecond}}"""
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        follow()
        assertEquals(emptyList<Notification>(), posted())
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        liveUpdates.refresh(now)
        assertEquals("1 🇫🇷 PERROT E. 12:41.6", posted().single().extras.getCharSequence(Notification.EXTRA_TEXT).toString())
    }

    @Test
    fun removesAnEndPastItsDismissal() = runBlocking {
        follow()
        liveUpdates.receive(LiveUpdate.Update(raceId, live, now))
        liveUpdates.receive(LiveUpdate.End(raceId, live, now - Duration.ofMinutes(1), now + Duration.ofMinutes(1)), now)
        assertEquals(emptyList<Notification>(), posted())
        assertEquals(emptySet<String>(), followed())
    }

    @Test
    fun unpinsARace() = runBlocking {
        follow()
        liveUpdates.receive(LiveUpdate.Update(raceId, live, now))
        liveUpdates.stop(raceId)
        assertEquals(emptyList<Notification>(), posted())
        assertEquals(emptySet<String>(), followed())
        assertEquals(listOf("+$topic", "-$topic"), subscriptions)
    }

    @Test
    fun catchesUpOnTheFollowedRacesAndForgetsTheStaleOnes() = runBlocking {
        follow()
        channel = HttpStatusCode.OK to """{"channelId":"$topic","state":${stateJson(live)},"timestamp":${now.epochSecond}}"""
        liveUpdates.refresh(now)
        assertEquals("1 🇫🇷 PERROT E. 12:41.6", posted().single().extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        // Its end never came.
        liveUpdates.refresh(start + Duration.ofDays(2))
        assertEquals(emptySet<String>(), followed())
        assertEquals(emptyList<Notification>(), posted())
    }

    @Test
    fun subscribesAgainOnceFcmRegistersTheInstallation() = runBlocking {
        follow()
        liveUpdates.resubscribe()
        assertEquals(listOf("+$topic", "+$topic"), subscriptions)
    }

    @Test
    fun showsTheDemoStatesWithoutARace() {
        val states = RaceLiveState.demo(start)
        for (state in states) {
            RaceNotifications.showLiveUpdate(context, "Men's Sprint", LiveUpdate.Update("demo", state, now), now)
            assertPromotable(posted().single())
        }
    }
}
