package com.fouteox.biathlon.kit

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

/**
 * `race-kinds.json` lists every `catId` + `DisciplineId` pair of the World Cup, Olympic and
 * World Championships races of seasons 2024-25 to 2026-27. The iOS app and the server, whose
 * alerts name a race by the same code, read it too.
 */
class RaceKindTest {
    @Test
    fun knowsEveryRaceKind() {
        val codes = Json.decodeFromString<List<String>>(fixture("race-kinds"))
        assertEquals(codes, RaceKind.entries.map { it.code }.sorted())
    }

    /**
     * Real IDs: `BT2526SWRLCP03SMMS` (Le Grand-Bornand), `BT2526SWRLOG__MXRL` (Antholz-Anterselva
     * Olympics) and `BT1314SWRLCP08SMSPS` (a Kontiolahti sprint, with a fifth character).
     */
    @ParameterizedTest
    @CsvSource("BT2526SWRLCP03SMMS, MEN_MASS_START", "BT2526SWRLOG__MXRL, MIXED_RELAY", "BT1314SWRLCP08SMSPS, MEN_SPRINT")
    fun readsTheRaceId(raceId: String, kind: RaceKind) {
        assertEquals(kind, decode<Competition>(race(raceId, "2026-02-10T12:30:00Z")).kind)
    }

    @Test
    fun leavesAnUnknownKindOut() {
        assertNull(decode<Competition>(race("BT2526SWRLCP03SMXX", "2026-02-10T12:30:00Z")).kind)
    }

    /** An athlete's history, from `AllResults`: only the races of the World Cup circuit get a name. */
    @Test
    fun athleteHistory() {
        val worldCup = decode<AthleteResult>(
            """{"RaceId":"BT2526SWRLCP09SMPU","Season":"25/26","Comp":"PU","Level":"WC","Place":"Oslo","Rank":"1."}""",
        )
        val summer = decode<AthleteResult>(
            """{"RaceId":"SB2627SIBUL1MUSMSF","Season":"26/27","Comp":"SF","Level":"SBSIBUL1","Place":"Munich"}""",
        )
        assertTrue(worldCup.isWorldCupCircuit)
        assertEquals(RaceKind.MEN_PURSUIT, worldCup.kind)
        assertEquals(SeasonId("2526"), worldCup.seasonId)
        assertFalse(summer.isWorldCupCircuit)
    }
}
