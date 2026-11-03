package com.fouteox.biathlon

import android.app.Application
import androidx.work.Configuration
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.WikidataClient
import io.ktor.http.Url
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch

class BiathlonApplication : Application(), Configuration.Provider {
    /** WorkManager starts on demand, at its first use, rather than with every launch. */
    override val workManagerConfiguration: Configuration get() = Configuration.Builder().build()

    /** The server, when the build has one: the app then goes without what it adds. */
    val server: ServerClient? by lazy {
        BuildConfig.SERVER_URL.takeIf { it.isNotEmpty() }?.let { ServerClient(Url("${it.trimEnd('/')}/")) }
    }

    /** One client for the whole app, through the server's cache when there is a server, to spare the IBU API. */
    val ibu: IbuClient by lazy { IbuClient(server?.let { Url("${it.baseUrl}ibu/") } ?: IbuClient.IBU_BASE_URL) }

    /** The athletes and nations followed, kept on the device. */
    val favorites: Favorites by lazy { Favorites(FavoritesDatabase.open(this).favorites()) }

    /** Named as the iOS app names itself to Wikimedia, which asks for a way to reach its developer. */
    val wikidata: WikidataClient by lazy {
        WikidataClient("Biathlon/${BuildConfig.VERSION_NAME} (https://github.com/fouteox/biathlon-app)")
    }

    val notificationSettings: NotificationSettings by lazy { NotificationSettings.open(this) }

    /** The push alerts' registration, which needs the server. */
    val pushRegistration: PushRegistration? by lazy {
        server?.let { PushRegistration.open(this, it, notificationSettings, PlayIntegrity(this)::token) }
    }

    val reminders: Reminders by lazy { Reminders.open(this, ibu, notificationSettings) }

    @OptIn(FlowPreview::class)
    override fun onCreate() {
        super.onCreate()
        RaceNotifications.createChannels(this)
        NotificationWork.refreshRemindersDaily(this)
        // The preferences found at launch, then each change, after a pause that groups quick changes.
        MainScope().launch {
            notificationSettings.preferences.debounce(500.milliseconds).collect {
                NotificationWork.syncPush(this@BiathlonApplication)
                NotificationWork.refreshReminders(this@BiathlonApplication)
            }
        }
    }
}
