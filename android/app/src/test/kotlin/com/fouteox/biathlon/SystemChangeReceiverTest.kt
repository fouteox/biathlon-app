package com.fouteox.biathlon

import android.content.Context
import android.content.Intent
import androidx.work.WorkManager
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** A new time zone or language reaches the server, which writes the alerts' dates in them. */
@RunWith(RobolectricTestRunner::class)
class SystemChangeReceiverTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    private fun queued(name: String) = WorkManager.getInstance(context).getWorkInfosForUniqueWork(name).get().size

    @Test
    fun aNewTimeZoneSyncsTheRegistration() {
        WorkManager.getInstance(context).cancelAllWork().result.get()
        WorkManager.getInstance(context).pruneWork().result.get()
        NotificationWork.SystemChangeReceiver().onReceive(context, Intent(Intent.ACTION_TIMEZONE_CHANGED))
        assertEquals(1, queued("push-sync"))
    }

    @Test
    fun aNewLanguageSyncsTheRegistrationAndRewritesTheReminders() {
        WorkManager.getInstance(context).cancelAllWork().result.get()
        WorkManager.getInstance(context).pruneWork().result.get()
        NotificationWork.SystemChangeReceiver().onReceive(context, Intent(Intent.ACTION_LOCALE_CHANGED))
        assertEquals(1, queued("push-sync"))
        assertEquals(1, queued("reminders"))
    }
}
