package com.fouteox.biathlon

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExpandedFullScreenSearchBar
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopSearchBar
import androidx.compose.material3.rememberSearchBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.AthleteMatch
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.searchAthletes
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * The athletes whose names start with what is typed, from the IBU's own search, as on iOS: after
 * a pause in the typing, so that each letter typed doesn't reach the IBU.
 */
class SearchViewModel(private val client: IbuClient) : ViewModel() {
    /** A retry is a search of its own, which a new query cancels. */
    private data class Search(val query: String, val attempt: Int = 0)

    /** The athletes found for [query], the text typed without its surrounding spaces. */
    data class Results(val query: String, val athletes: Loadable<List<AthleteMatch>>)

    private val search = MutableStateFlow(Search(""))

    private val mutableResults = MutableStateFlow<Results?>(null)

    /** `null` while nothing is typed. */
    val results: StateFlow<Results?> = mutableResults.asStateFlow()

    init {
        viewModelScope.launch {
            search.collectLatest { (query) ->
                if (query.isEmpty()) {
                    mutableResults.value = null
                } else {
                    mutableResults.value = Results(query, Loadable.Loading)
                    delay(TYPING_PAUSE_MILLIS)
                    mutableResults.value = Results(query, attempt { client.searchAthletes(query) })
                }
            }
        }
    }

    /** A space typed after a word searches nothing new. */
    fun type(text: String) {
        search.update { it.copy(query = text.trim()) }
    }

    fun retry() {
        search.update { it.copy(attempt = it.attempt + 1) }
    }

    private companion object {
        const val TYPING_PAUSE_MILLIS = 300L
    }
}

/** Athletes, active or former, by the start of their names, from the search bar Material puts on top. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(open: (Route) -> Unit) {
    val client = LocalIbuClient.current
    val search = viewModel { SearchViewModel(client) }
    val text = rememberTextFieldState()
    LaunchedEffect(text) { snapshotFlow { text.text.toString() }.collect(search::type) }
    val results by search.results.collectAsStateWithLifecycle()
    val searchBar = rememberSearchBarState()
    val keyboard = LocalSoftwareKeyboardController.current
    val inputField = @Composable {
        SearchBarDefaults.InputField(
            textFieldState = text,
            searchBarState = searchBar,
            onSearch = { keyboard?.hide() },
            placeholder = { Text(stringResource(R.string.biathletes)) },
            leadingIcon = { Icon(painterResource(R.drawable.ic_search), contentDescription = null) },
        )
    }
    val scope = rememberCoroutineScope()
    val openCollapsed = { route: Route ->
        // The full-screen search is a dialog over every screen: it closes first, with the results
        // left below the bar for the way back.
        scope.launch(start = CoroutineStart.UNDISPATCHED) { searchBar.snapTo(0f) }
        open(route)
    }
    // Tapping the bar opens the full-screen search; the results stay below it once it closes.
    val content = @Composable { modifier: Modifier -> SearchResults(results, search::retry, openCollapsed, modifier) }
    Scaffold(topBar = { TopSearchBar(state = searchBar, inputField = inputField) }) { padding ->
        content(Modifier.fillMaxSize().padding(padding))
    }
    ExpandedFullScreenSearchBar(state = searchBar, inputField = inputField) { content(Modifier.fillMaxSize()) }
}

@Composable
private fun SearchResults(results: SearchViewModel.Results?, retry: () -> Unit, open: (Route) -> Unit, modifier: Modifier) {
    when (val athletes = results?.athletes) {
        null -> Prompt(stringResource(R.string.search_for_a_biathlete), stringResource(R.string.type_the_start_of_a_first_or_last_name), modifier)
        Loadable.Loading -> LoadProgress(modifier)
        is Loadable.Failed -> LoadFailure(retry, isRetrying = false, modifier)
        is Loadable.Loaded -> if (athletes.value.isEmpty()) {
            Prompt(stringResource(R.string.no_results_for_arg, results.query), stringResource(R.string.check_the_spelling_or_try_a_new_search), modifier)
        } else {
            LazyColumn(modifier) {
                items(athletes.value, key = { it.id }) { athlete ->
                    ListItem(
                        modifier = Modifier.clickable { open(Route.Athlete(athlete.id, athlete.name)) },
                        leadingContent = { NationMark(athlete.nation) },
                        headlineContent = { Text(athlete.name) },
                    )
                }
            }
        }
    }
}

/** What to do, or what happened, in place of the results. */
@Composable
private fun Prompt(title: String, text: String, modifier: Modifier) {
    Column(
        modifier.padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(painterResource(R.drawable.ic_search), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}
