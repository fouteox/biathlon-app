package com.fouteox.biathlon

import androidx.compose.runtime.Composable
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.WikidataClient
import com.fouteox.biathlon.kit.sample
import java.io.File
import java.nio.file.Files
import java.time.Instant
import org.robolectric.RuntimeEnvironment

/** Waits for a text the network brings, which the fictional World Cup serves at once. */
fun ComposeContentTestRule.waitForText(text: String) {
    waitUntil(5_000L) { onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty() }
}

/** Favorites of a test's own, gone with it. */
fun inMemoryFavorites(): Favorites =
    Favorites(Room.inMemoryDatabaseBuilder<FavoritesDatabase>(RuntimeEnvironment.getApplication()).build().favorites())

/** Notification settings of a test's own, gone with it. */
fun temporaryNotificationSettings(): NotificationSettings =
    NotificationSettings(PreferenceDataStoreFactory.create { File(Files.createTempDirectory("notifications").toFile(), "notifications.preferences_pb") })

/** The app on the fictional World Cup, without a server unless the test gives one. */
fun ComposeContentTestRule.launchApp(
    client: IbuClient = IbuClient.sample(Instant.now()),
    wikidata: WikidataClient = WikidataClient.sample(),
    favorites: Favorites = inMemoryFavorites(),
) {
    setContent { BiathlonApp(client, wikidata, server = null, favorites, temporaryNotificationSettings()) }
}

/** One screen, with what the app gives every screen. */
fun ComposeContentTestRule.showScreen(
    client: IbuClient = IbuClient.sample(Instant.now()),
    server: ServerClient? = null,
    favorites: Favorites = inMemoryFavorites(),
    notifications: NotificationSettings = temporaryNotificationSettings(),
    content: @Composable () -> Unit,
) {
    setContent { AppEnvironment(client, WikidataClient.sample(), server, favorites, notifications, content) }
}
