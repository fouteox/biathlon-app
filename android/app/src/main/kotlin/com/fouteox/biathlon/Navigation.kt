package com.fouteox.biathlon

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSerializable
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberDecoratedNavEntries
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.runtime.serialization.NavBackStackSerializer
import com.fouteox.biathlon.kit.BiathlonEvent
import com.fouteox.biathlon.kit.Competition
import kotlinx.serialization.Serializable

/** The app's screens, saved with their back stacks across process death. */
@Serializable
sealed interface Route : NavKey {
    @Serializable
    data object Home : Route

    @Serializable
    data object Calendar : Route

    @Serializable
    data class Event(val event: BiathlonEvent) : Route

    @Serializable
    data class Race(val race: Competition) : Route
}

/** The navigation bar's destinations, each with its own back stack, as the iOS app's tabs. */
enum class Tab(@param:StringRes val label: Int, @param:DrawableRes val icon: Int, val root: Route) {
    HOME(R.string.home, R.drawable.ic_home, Route.Home),
    CALENDAR(R.string.calendar, R.drawable.ic_calendar_month, Route.Calendar),
}

/**
 * The selected tab and every tab's back stack, after the Navigation 3 recipe for multiple back
 * stacks. Back leaves a tab for Home, whose root exits the app.
 */
class Navigation(selected: MutableState<Tab>, private val backStacks: Map<Tab, NavBackStack<Route>>) {
    var selected by selected
        private set

    private val backStack get() = backStacks.getValue(selected)

    fun open(route: Route) {
        backStack.add(route)
    }

    /** A tab tapped again goes back to its root. */
    fun select(tab: Tab) {
        if (tab == selected) backStack.retainAll(listOf(tab.root)) else selected = tab
    }

    fun goBack() {
        if (backStack.size > 1) backStack.removeAt(backStack.lastIndex) else selected = Tab.HOME
    }

    /**
     * The entries shown: Home's, with the selected tab's above them. Each tab keeps its screens'
     * state and view models, and names its entries apart, as both can show the same race.
     */
    @Composable
    fun entries(content: @Composable (Route) -> Unit): List<NavEntry<Route>> {
        val decorated = backStacks.mapValues { (tab, stack) ->
            rememberDecoratedNavEntries(
                backStack = stack,
                entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator(), rememberViewModelStoreNavEntryDecorator()),
                entryProvider = { route -> NavEntry(route, contentKey = "${tab.name}/$route", content = content) },
            )
        }
        return listOf(Tab.HOME, selected).distinct().flatMap(decorated::getValue)
    }
}

@Composable
fun rememberNavigation(): Navigation {
    val selected = rememberSaveable { mutableStateOf(Tab.HOME) }
    val backStacks = Tab.entries.associateWith { tab ->
        rememberSerializable(serializer = NavBackStackSerializer(Route.serializer())) { NavBackStack(tab.root) }
    }
    return remember(selected, backStacks) { Navigation(selected, backStacks) }
}
