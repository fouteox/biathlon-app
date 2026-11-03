package com.fouteox.biathlon.kit

import kotlinx.serialization.Serializable
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.FieldSource

/**
 * `race-status.json` is shared with the iOS app and the server, so the apps, the alerts and the
 * live updates agree on a race's status.
 */
class RaceStatusTest {
    @Serializable
    data class Case(val name: String, val status: String, val race: Competition) {
        override fun toString() = name
    }

    @ParameterizedTest
    @FieldSource("cases")
    fun sharedStatus(example: Case) {
        assertEquals(example.status, example.race.state.name.lowercase())
    }

    /** Real IDs: `BT2526SWRLCP03SMMS` (Le Grand-Bornand), `BT2526SWRLOG__SMIN` (Antholz-Anterselva Olympics). */
    @ParameterizedTest
    @CsvSource("BT2526SWRLCP03SMMS, BT2526SWRLCP03", "BT2526SWRLOG__SMIN, BT2526SWRLOG__")
    fun eventId(raceId: String, eventId: String) {
        assertEquals(eventId, decode<Competition>(race(raceId, "2026-02-10T12:30:00Z")).eventId)
    }

    @Test
    fun category() {
        assertEquals(RaceCategory.WOMEN, decode<Competition>(race("R1", "2026-11-26T15:15:00Z", category = "SW")).category)
    }

    /** Upcoming and live races can still be watched; cancelled and finished ones can't. */
    @ParameterizedTest
    @CsvSource("SCHEDULED, true", "LIVE, true", "CANCELLED, false", "FINISHED, false")
    fun canBeFollowedLive(state: Competition.State, followed: Boolean) {
        assertEquals(followed, state.canBeFollowedLive)
    }

    companion object {
        @JvmField
        val cases: List<Case> = decode(fixture("race-status"))
    }
}
