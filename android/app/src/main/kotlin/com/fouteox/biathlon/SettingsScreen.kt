package com.fouteox.biathlon

import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource

/** The app's settings: for now, where the data comes from, the privacy policy and the version. */
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val uriHandler = LocalUriHandler.current
    Screen(stringResource(R.string.settings), onBack) { padding ->
        LazyColumn(contentPadding = padding) {
            item { SectionHeader(stringResource(R.string.about)) }
            item {
                ListItem(
                    modifier = Modifier.clickable { uriHandler.openUri("https://www.biathlonresults.com") },
                    headlineContent = { Text(stringResource(R.string.data)) },
                    trailingContent = { Text("IBU Datacenter") },
                )
            }
            // The link stays hidden until the policy has its page.
            BuildConfig.PRIVACY_POLICY_URL.takeIf { it.isNotEmpty() }?.let { privacyPolicy ->
                item {
                    ListItem(
                        modifier = Modifier.clickable { uriHandler.openUri(privacyPolicy) },
                        headlineContent = { Text(stringResource(R.string.privacy_policy)) },
                    )
                }
            }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.version)) },
                    trailingContent = { Text(BuildConfig.VERSION_NAME) },
                )
            }
        }
    }
}
