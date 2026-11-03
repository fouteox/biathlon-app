package com.fouteox.biathlon

import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.sample
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** Following a race live from its screen, on the fictional World Cup. */
@RunWith(RobolectricTestRunner::class)
class RaceLiveUpdateTest {
    @get:Rule
    val compose = createComposeRule()

    private val client = IbuClient.sample(Instant.now())

    /** What the race's topic answers: closed until shortly before the start. */
    private var channel: Pair<HttpStatusCode, String> = HttpStatusCode.NotFound to """{"error":"no channel for this race"}"""

    private val subscriptions = mutableListOf<String>()

    private val server = ServerClient(
        Url("https://example.workers.dev/"),
        HttpClient(
            MockEngine { request ->
                if (request.url.encodedPath.endsWith("/channels/fcm")) respond(channel.second, channel.first) else respond("""{"coverage":[]}""")
            },
        ),
    )

    private val liveUpdates = LiveUpdates(
        RuntimeEnvironment.getApplication(),
        server,
        object : LiveUpdates.Topics {
            override fun subscribe(topic: String, onSubscribed: () -> Unit) {
                subscriptions += "+$topic"
            }

            override fun unsubscribe(topic: String) {
                subscriptions += "-$topic"
            }
        },
        PreferenceDataStoreFactory.create { File(Files.createTempDirectory("live").toFile(), "live.preferences_pb") },
        CoroutineScope(Job()),
    )

    private fun race(id: String): Competition = runBlocking { client.race(id) }

    private fun show(race: Competition, liveUpdates: LiveUpdates? = this.liveUpdates) {
        compose.showScreen(client, server, liveUpdates = liveUpdates) { RaceScreen(race, open = {}, onBack = {}) }
        compose.waitForText(race.title(RuntimeEnvironment.getApplication().resources))
    }

    @Test
    fun followsARaceToComeThenUnpinsIt() {
        val race = race("BT2829SWRLCP01SMSP")
        show(race)
        compose.onNodeWithContentDescription("Live update").assertIsOff().performClick()
        compose.waitUntil { runBlocking { liveUpdates.followed.first() } == setOf(race.id) }
        compose.onNodeWithContentDescription("Live update").assertIsOn().performClick()
        compose.waitUntil { subscriptions.size == 2 }
        assertEquals(listOf("+race-${race.id}", "-race-${race.id}"), subscriptions)
        assertEquals(emptySet<String>(), runBlocking { liveUpdates.followed.first() })
    }

    @Test
    fun saysWhenTheRaceIsAlreadyOver() {
        // The calendar still lists the race as upcoming, the server knows it ended.
        channel = HttpStatusCode.Gone to """{"state":{"phase":"finished","startTime":817398900,"leaders":[]},"dismissalDate":1795708800,"timestamp":1795707000}"""
        show(race("BT2829SWRLCP01SMSP"))
        compose.onNodeWithContentDescription("Live update").performClick()
        compose.waitForText("This race is over.")
        compose.onNodeWithContentDescription("Live update").assertIsOff()
    }

    @Test
    fun cannotFollowARaceOver() {
        show(race("BT2526SWRLCP01SMSP"))
        compose.onNodeWithContentDescription("Live update").assertDoesNotExist()
    }

    @Test
    fun cannotFollowARaceWithoutTheServer() {
        show(race("BT2829SWRLCP01SMSP"), liveUpdates = null)
        compose.onNodeWithContentDescription("Live update").assertDoesNotExist()
    }
}
