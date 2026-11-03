package com.fouteox.biathlon.kit

/** What the user asked to be notified of, as the iOS app's `NotificationPreferences`. */
data class NotificationPreferences(
    val reminderEnabled: Boolean = false,
    val reminderMinutes: Int = 15,
    val cancellationAlerts: Boolean = false,
    val reschedulingAlerts: Boolean = false,
    val categories: Set<RaceCategory> = RaceCategory.entries.toSet(),
) {
    val anyEnabled: Boolean get() = reminderEnabled || wantsPush

    /** Push alerts are only useful with at least one alert type and one category. */
    val wantsPush: Boolean get() = (cancellationAlerts || reschedulingAlerts) && categories.isNotEmpty()

    /**
     * What the server is told for these preferences, worded in `locale` and `timeZone`; `null`
     * when no push alert is wanted, which unregisters the device.
     */
    fun registration(locale: String, timeZone: String): AndroidDeviceRegistration? =
        if (!wantsPush) {
            null
        } else {
            AndroidDeviceRegistration(
                categories = RaceCategory.entries.filter { it in categories }.map { it.code },
                cancellation = cancellationAlerts,
                rescheduling = reschedulingAlerts,
                locale = locale,
                timeZone = timeZone,
            )
        }

    companion object {
        val REMINDER_CHOICES = listOf(5, 10, 15, 30, 60)
    }
}
