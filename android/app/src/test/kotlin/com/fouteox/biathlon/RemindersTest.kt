package com.fouteox.biathlon

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Looper
import androidx.core.content.getSystemService
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.RaceCategory
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.engine.mock.respondError
import io.ktor.http.HttpStatusCode
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager

/** The reminders' alarms, set from a calendar of two races of the coming week. */
@RunWith(RobolectricTestRunner::class)
class RemindersTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val now = Instant.parse("2026-11-26T12:00:00Z")
    private var calendarIsUnavailable = false
    private val client = IbuClient(
        httpClient = HttpClient(
            MockEngine { request ->
                if (calendarIsUnavailable) return@MockEngine respondError(HttpStatusCode.ServiceUnavailable)
                when (request.url.segments.last()) {
                    "Events" -> respond(
                        """[{"EventId":"BT2627SWRLCP01","ShortDescription":"Kontiolahti","StartDate":"2026-11-23T00:00:00Z","EndDate":"2026-11-29T23:00:00Z"}]""",
                    )
                    else -> respond(
                        """[${race("BT2627SWRLCP01SMSP", "SM", "2026-11-26T15:15:00Z")},${race("BT2627SWRLCP01SWSP", "SW", "2026-11-27T12:00:00Z")}]""",
                    )
                }
            },
        ),
    )
    private val settings = temporaryNotificationSettings()
    private val reminders = Reminders(
        context,
        client,
        settings,
        PreferenceDataStoreFactory.create { File(Files.createTempDirectory("reminders").toFile(), "reminders.preferences_pb") },
    )
    private val alarms = shadowOf(checkNotNull(context.getSystemService<AlarmManager>()))

    private fun race(id: String, category: String, start: String) =
        """{"RaceId":"$id","catId":"$category","ShortDescription":"$id","StartTime":"$start","StatusId":1,"ScheduleStatus":"SCHEDULED"}"""

    private val scheduledTimes get() = alarms.scheduledAlarms.map { Instant.ofEpochMilli(it.triggerAtMs) }

    @Test
    fun remindsBeforeEachRaceOfTheChosenCategories() = runBlocking {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        settings.update { it.copy(reminderEnabled = true, reminderMinutes = 15, categories = setOf(RaceCategory.MEN)) }
        reminders.refresh(now)
        assertEquals(listOf(Instant.parse("2026-11-26T15:00:00Z")), scheduledTimes)

        settings.update { it.copy(categories = setOf(RaceCategory.MEN, RaceCategory.WOMEN)) }
        reminders.refresh(now)
        assertEquals(listOf(Instant.parse("2026-11-26T15:00:00Z"), Instant.parse("2026-11-27T11:45:00Z")), scheduledTimes.sorted())
    }

    @Test
    fun theAlarmShowsTheReminder() = runBlocking {
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        settings.update { it.copy(reminderEnabled = true, reminderMinutes = 15, categories = setOf(RaceCategory.MEN)) }
        reminders.refresh(now)
        alarms.fireAlarm(alarms.scheduledAlarms.single())
        shadowOf(Looper.getMainLooper()).idle()

        val notification = shadowOf(checkNotNull(context.getSystemService<NotificationManager>())).allNotifications.single()
        assertEquals(RaceNotifications.REMINDER_CHANNEL, notification.channelId)
        assertEquals("Men's Sprint", notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Starts in 15 minutes", notification.extras.getString(Notification.EXTRA_TEXT))
    }

    @Test
    fun cancelsTheAlarmsOnceTheRemindersAreOff() = runBlocking {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        settings.update { it.copy(reminderEnabled = true) }
        reminders.refresh(now)
        assertEquals(2, scheduledTimes.size)
        settings.update { it.copy(reminderEnabled = false) }
        reminders.refresh(now)
        assertEquals(emptyList<Instant>(), scheduledTimes)
    }

    /** A late reminder is useless: none without the "Alarms & reminders" access, which Settings then asks for. */
    @Test
    fun setsNoneWithoutTheExactAlarmAccess() = runBlocking {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        settings.update { it.copy(reminderEnabled = true) }
        reminders.refresh(now)
        assertEquals(emptyList<Instant>(), scheduledTimes)
    }

    @Test
    fun keepsTheAlarmsWhenTheCalendarIsUnavailable() = runBlocking {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        settings.update { it.copy(reminderEnabled = true) }
        reminders.refresh(now)
        calendarIsUnavailable = true
        assertFalse(reminders.refresh(now))
        assertEquals(2, scheduledTimes.size)
    }
}
