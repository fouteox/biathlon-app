package com.fouteox.biathlon

import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.provider.CalendarContract
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.sample
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.Url
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** A race's podium to share, its start to add to a calendar and its TV channels, on the fictional World Cup. */
@RunWith(RobolectricTestRunner::class)
class RaceActionsTest {
    @get:Rule
    val compose = createComposeRule()

    private val client = IbuClient.sample(Instant.now())
    private val application = RuntimeEnvironment.getApplication()

    /** Who shows every race: France's and Britain's broadcasters, whatever the date. */
    private val server = ServerClient(
        Url("https://example.workers.dev/"),
        HttpClient(
            MockEngine {
                respond(
                    """
                    {"coverage":[
                    {"country":"FR","broadcaster":"La Chaîne L'Équipe","url":"https://www.lequipe.fr/tv/","from":"2000-01-01T00:00:00Z","until":"2100-01-01T00:00:00Z"},
                    {"country":"GB","broadcaster":"TNT Sports","url":"https://www.tntsports.co.uk/biathlon/","from":"2000-01-01T00:00:00Z","until":"2100-01-01T00:00:00Z"}
                    ]}
                    """.trimIndent(),
                )
            },
        ),
    )

    private fun race(id: String): Competition = runBlocking { client.race(id) }

    private fun show(race: Competition) {
        compose.setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalIbuClient provides client, LocalServerClient provides server) {
                    RaceScreen(race, open = {}, onBack = {})
                }
            }
        }
    }

    /** The podium in a sentence, race and place first, names as a voice reads them. */
    @Test
    fun sharesThePodium() {
        show(race("BT2526SWRLCP01SMSP"))
        compose.waitForText("VANGEN A.")
        compose.onNodeWithContentDescription("Share").performClick()
        val chooser = shadowOf(application).nextStartedActivity
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        @Suppress("DEPRECATION") // The typed overload needs API 33.
        val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertEquals("Men's Sprint, Nordvik: Aksel Vangen wins, ahead of Hugo Martel and Lukas Brandt.", send.getStringExtra(Intent.EXTRA_TEXT))
    }

    /** A race to come goes to the calendar app, which asks where to save it. */
    @Test
    fun addsARaceToComeToTheCalendar() {
        val component = ComponentName("com.example.calendar", "com.example.calendar.EditEvent")
        shadowOf(application.packageManager).apply {
            addActivityIfNotPresent(component)
            // As calendar apps declare it: the system resolves implicit intents among default activities.
            val filter = IntentFilter(Intent.ACTION_INSERT).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                addDataType("vnd.android.cursor.dir/event")
            }
            addIntentFilterForActivity(component, filter)
        }
        val race = race("BT2829SWRLCP01SMSP")
        show(race)
        compose.waitForText("No start list yet")
        compose.onNodeWithContentDescription("Add to Calendar").performClick()
        val entry = shadowOf(application).nextStartedActivity
        assertEquals(Intent.ACTION_INSERT, entry.action)
        assertEquals("Men's Sprint", entry.getStringExtra(CalendarContract.Events.TITLE))
        assertEquals("Nordvik", entry.getStringExtra(CalendarContract.Events.EVENT_LOCATION))
        assertEquals(race.startTime.toEpochMilli(), entry.getLongExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, 0))
    }

    /** Without a calendar app, there is nothing to add the race to. */
    @Test
    fun noCalendarWithoutACalendarApp() {
        show(race("BT2829SWRLCP01SMSP"))
        compose.waitForText("No start list yet")
        compose.onNodeWithContentDescription("Add to Calendar").assertDoesNotExist()
    }

    /** A viewer's own country comes first; the others are folded away. */
    @Test
    @Config(qualifiers = "en-rGB")
    fun showsTheViewersChannelsFirst() {
        show(race("BT2829SWRLCP01SMSP"))
        compose.waitForText("TNT Sports")
        compose.onNodeWithText("La Chaîne L'Équipe").assertDoesNotExist()
        compose.onNodeWithText("Other countries").performClick()
        compose.onNodeWithText("La Chaîne L'Équipe").assertExists()
    }

    /** Once a race is over, it is no longer on TV. */
    @Test
    fun noChannelsOnceTheRaceIsOver() {
        show(race("BT2526SWRLCP01SMSP"))
        compose.waitForText("VANGEN A.")
        compose.onNodeWithText("On TV").assertDoesNotExist()
    }
}
