package com.fouteox.biathlon

import android.Manifest
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ListItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.core.app.AlarmManagerCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.getSystemService
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fouteox.biathlon.kit.NotificationPreferences
import com.fouteox.biathlon.kit.RaceCategory
import com.fouteox.biathlon.kit.RaceKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

val LocalNotificationSettings = staticCompositionLocalOf<NotificationSettings> { error("No NotificationSettings provided") }

/** The app's settings: notifications, where the data comes from, the privacy policy and the version. */
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val uriHandler = LocalUriHandler.current
    val notifications = rememberNotificationControls()
    Screen(stringResource(R.string.settings), onBack) { padding ->
        LazyColumn(contentPadding = padding) {
            notifications.preferences?.let { notificationItems(notifications, it) }
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

/**
 * The notification preferences and what the system lets the app do, read again each time the
 * screen shows, back from the system's settings too.
 */
private class NotificationControls(
    private val context: Context,
    private val settings: NotificationSettings,
    private val scope: CoroutineScope,
) {
    var preferences by mutableStateOf<NotificationPreferences?>(null)
    var notificationsAllowed by mutableStateOf(true)
        private set
    var exactAlarmsAllowed by mutableStateOf(true)
        private set
    lateinit var requestPermission: () -> Unit

    fun refreshAccess() {
        notificationsAllowed = NotificationManagerCompat.from(context).areNotificationsEnabled()
        exactAlarmsAllowed = AlarmManagerCompat.canScheduleExactAlarms(checkNotNull(context.getSystemService<AlarmManager>()))
    }

    fun change(transform: (NotificationPreferences) -> NotificationPreferences) {
        val current = preferences ?: return
        // Asked in context, as Apple recommends too: when a first notification is turned on.
        if (!current.anyEnabled && transform(current).anyEnabled && !notificationsAllowed) requestPermission()
        scope.launch { settings.update(transform) }
    }

    fun openNotificationSettings() {
        context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
    }

    /** Debug builds: the notifications as a race brings them, to see them on any day. */
    fun showSampleAlert() {
        val (title, body) = checkNotNull(RaceNotifications.alertText(context, SAMPLE_RACE_ID, null, "push_cancelled", null))
        RaceNotifications.showAlert(context, SAMPLE_RACE_ID, title, body)
    }

    fun showSampleReminder() {
        val minutes = preferences?.reminderMinutes ?: return
        RaceNotifications.showReminder(context, SAMPLE_RACE_ID, context.getString(RaceKind.MEN_SPRINT.title), RaceNotifications.reminderText(context, minutes))
    }

    /** The system's "Alarms & reminders" access for the app, which exists from Android 12 on. */
    @RequiresApi(Build.VERSION_CODES.S)
    fun openExactAlarmSettings() {
        context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.fromParts("package", context.packageName, null)))
    }
}

@Composable
private fun rememberNotificationControls(): NotificationControls {
    val context = LocalContext.current
    val settings = LocalNotificationSettings.current
    val scope = rememberCoroutineScope()
    val controls = remember(context, settings, scope) { NotificationControls(context, settings, scope) }
    controls.preferences = settings.preferences.collectAsStateWithLifecycle(null).value
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { controls.refreshAccess() }
    controls.requestPermission = {
        // Before Android 13, notifications need no permission.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    WhileStarted(controls) { controls.refreshAccess() }
    return controls
}

/** The notification settings, as the iOS app's, from system list items and switches. */
private fun LazyListScope.notificationItems(controls: NotificationControls, preferences: NotificationPreferences) {
    if (preferences.anyEnabled && !controls.notificationsAllowed) {
        item { SectionFooter(stringResource(R.string.notifications_are_turned_off_in_settings)) }
        item { TextButton(controls::openNotificationSettings) { Text(stringResource(R.string.open_settings)) } }
    }
    item { SectionHeader(stringResource(R.string.notifications)) }
    item {
        SwitchRow(stringResource(R.string.reminder_before_the_start), preferences.reminderEnabled) { on ->
            controls.change { it.copy(reminderEnabled = on) }
        }
    }
    if (preferences.reminderEnabled) {
        item {
            val format = MeasureFormat.getInstance(LocalConfiguration.current.locales[0], MeasureFormat.FormatWidth.SHORT)
            ListItem(
                headlineContent = { Text(stringResource(R.string.notify_me)) },
                trailingContent = {
                    MenuPicker(preferences.reminderMinutes, NotificationPreferences.REMINDER_CHOICES, { format.format(Measure(it, MeasureUnit.MINUTE)) }) { minutes ->
                        controls.change { it.copy(reminderMinutes = minutes) }
                    }
                },
            )
        }
        if (!controls.exactAlarmsAllowed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            item { SectionFooter(stringResource(R.string.allow_alarms_and_reminders_so_that_reminders_arrive_on_time)) }
            item { TextButton(controls::openExactAlarmSettings) { Text(stringResource(R.string.allow)) } }
        }
    }
    item {
        SwitchRow(stringResource(R.string.race_cancelled), preferences.cancellationAlerts) { on ->
            controls.change { it.copy(cancellationAlerts = on) }
        }
    }
    item {
        SwitchRow(stringResource(R.string.start_time_changed), preferences.reschedulingAlerts) { on ->
            controls.change { it.copy(reschedulingAlerts = on) }
        }
    }
    item { SectionHeader(stringResource(R.string.notify_for)) }
    items(RaceCategory.entries) { category ->
        SwitchRow(stringResource(category.title), category in preferences.categories) { on ->
            controls.change { it.copy(categories = if (on) it.categories + category else it.categories - category) }
        }
    }
    // Not translated, as the iOS app's developer screen.
    if (BuildConfig.DEBUG) {
        item { SectionHeader("Developer") }
        item { ListItem(modifier = Modifier.clickable(onClick = controls::showSampleAlert), headlineContent = { Text("Show a sample alert") }) }
        item { ListItem(modifier = Modifier.clickable(onClick = controls::showSampleReminder), headlineContent = { Text("Show a sample reminder") }) }
    }
}

/** A men's sprint of the 2026-27 World Cup, for the sample notifications. */
private const val SAMPLE_RACE_ID = "BT2627SWRLCP01SMSP"

@Composable
private fun SwitchRow(text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    ListItem(
        modifier = Modifier.toggleable(value = checked, role = Role.Switch, onValueChange = onChange),
        headlineContent = { Text(text) },
        trailingContent = { Switch(checked = checked, onCheckedChange = null) },
    )
}
