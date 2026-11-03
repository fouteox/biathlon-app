package com.fouteox.biathlon

import android.icu.text.DateFormat
import android.icu.text.DateIntervalFormat
import android.icu.util.DateInterval
import android.text.format.DateUtils
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import java.text.FieldPosition
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.util.Date
import java.util.Locale

/**
 * Dates as the iOS app writes them, from the same Unicode skeletons, in the device's language
 * and with its 12- or 24-hour clock (`j` in a skeleton).
 */
enum class DateSkeleton(private val pattern: String) {
    /** Day, date and time, with the year, since the calendar goes back to 1957-58. */
    START("EEEEdMMMMyjmm"),

    /** Day, date and time, abbreviated, where space is short: the widget. */
    SHORT_START("EEEdMMMjmm"),

    /** The time alone, where a header already gives the day. */
    TIME("jmm"),

    /** A day's header in an event's schedule. */
    DAY("EEEEdMMMMy"),

    /** An athlete's birthdate. */
    BIRTHDATE("dMMMMy"),

    /** A month's header in the calendar. */
    MONTH("MMMMy"),
    ;

    fun format(instant: Instant, is24Hour: Boolean, locale: Locale): String =
        DateFormat.getInstanceForSkeleton(pattern.replace("j", if (is24Hour) "H" else "h"), locale).format(Date.from(instant))
}

@Composable
@ReadOnlyComposable
private fun locale() = LocalConfiguration.current.locales[0]

@Composable
@ReadOnlyComposable
fun formatted(instant: Instant, skeleton: DateSkeleton): String =
    skeleton.format(instant, android.text.format.DateFormat.is24HourFormat(LocalContext.current), locale())

@Composable
@ReadOnlyComposable
fun formatted(day: LocalDate, skeleton: DateSkeleton): String = formatted(day.atStartOfDay(ZoneId.systemDefault()).toInstant(), skeleton)

@Composable
@ReadOnlyComposable
fun formatted(month: YearMonth): String = formatted(month.atDay(1), DateSkeleton.MONTH)

/** An event's first to last day, "1–7 Dec". */
@Composable
@ReadOnlyComposable
fun formattedDays(start: Instant, end: Instant): String {
    val interval = DateInterval(start.toEpochMilli(), maxOf(start, end).toEpochMilli())
    return DateIntervalFormat.getInstance("dMMM", locale()).format(interval, StringBuffer(), FieldPosition(0)).toString()
}

/** How far away a start is, "In 3 days", as the system says it. */
fun formattedFromNow(instant: Instant, now: Instant): String =
    DateUtils.getRelativeTimeSpanString(instant.toEpochMilli(), now.toEpochMilli(), DateUtils.MINUTE_IN_MILLIS).toString()
