package com.fouteox.biathlon

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.ui.NavDisplay
import com.fouteox.biathlon.kit.HomeFeed
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.WikidataClient
import com.fouteox.biathlon.kit.homeFeed
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.delay

/** The app, on Material 3's own colors: the wallpaper's where Android has them (12 and later). */
@Composable
fun BiathlonApp(client: IbuClient, wikidata: WikidataClient, server: ServerClient?) {
    val dark = isSystemInDarkTheme()
    val colorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        dark -> darkColorScheme()
        else -> lightColorScheme()
    }
    MaterialTheme(colorScheme = colorScheme) {
        CompositionLocalProvider(
            LocalIbuClient provides client,
            LocalWikidataClient provides wikidata,
            LocalServerClient provides server,
        ) { Tabs() }
    }
}

@Composable
private fun Tabs() {
    val homeFeed = rememberHomeFeed()
    val navigation = rememberNavigation()
    NavigationSuiteScaffold(
        navigationSuiteItems = {
            for (tab in Tab.entries) {
                item(
                    selected = tab == navigation.selected,
                    onClick = { navigation.select(tab) },
                    icon = { Icon(painterResource(tab.icon), contentDescription = null) },
                    label = { Text(stringResource(tab.label)) },
                )
            }
        },
    ) {
        NavDisplay(
            entries = navigation.entries { route ->
                when (route) {
                    Route.Home -> HomeScreen(homeFeed, navigation::open)
                    Route.Calendar -> CalendarScreen(navigation::open)
                    is Route.Event -> EventScreen(route.event, navigation::open, navigation::goBack)
                    is Route.Race -> RaceScreen(route.race, navigation::open, navigation::goBack)
                    is Route.Analysis -> AnalysisScreen(route.race, navigation::open, navigation::goBack)
                    is Route.RaceById -> RaceByIdScreen(route.id, route.title, navigation::open, navigation::goBack)
                    Route.Standings -> StandingsScreen(navigation::open)
                    is Route.Athlete -> AthleteScreen(route.id, route.name, navigation::open, navigation::goBack)
                    is Route.Nation -> NationScreen(route.code, route.category, navigation::open, navigation::goBack)
                    Route.Search -> SearchScreen(navigation::open)
                    Route.Settings -> SettingsScreen(navigation::goBack)
                }
            },
            onBack = navigation::goBack,
        )
    }
}

/**
 * The home feed, kept by the app rather than by the Home screen, as on iOS. It loads at launch
 * and whenever the app comes back, keeps refreshing while a race is live, and fetches itself
 * again at the next start, so the race shows live by itself.
 */
@Composable
private fun rememberHomeFeed(): LoadViewModel<HomeFeed> {
    val client = LocalIbuClient.current
    val feed = viewModel(key = "homeFeed") { LoadViewModel { client.homeFeed(Instant.now()) } }
    val state by feed.state.collectAsStateWithLifecycle()
    val loaded = state.value
    WhileStarted(feed) { feed.load() }
    RefreshWhileLive(loaded?.live != null, feed::load)
    // The start the app waits for: the next race's, while none is live.
    WhileStarted(loaded?.takeIf { it.live == null }?.next?.startTime) {
        while (true) {
            val time = feed.state.value.value?.nextStartRefreshTime(Instant.now()) ?: break
            delay(Duration.between(Instant.now(), time).toMillis())
            feed.load()
        }
    }
    return feed
}
