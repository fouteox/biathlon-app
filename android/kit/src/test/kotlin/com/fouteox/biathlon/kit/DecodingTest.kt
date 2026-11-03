package com.fouteox.biathlon.kit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

/** Fixtures mirror the shape of real responses captured on 2026-10-19. */
class DecodingTest {
    @Test
    fun events() {
        val first = decode<List<BiathlonEvent>>(fixture("events")).first()
        assertEquals("BT2627SWRLCP01", first.id)
        assertEquals("FIN", first.nation)
        assertFalse(first.isWorldChampionships)
    }

    @Test
    fun competitionStates() {
        val races = decode<List<Competition>>(fixture("competitions"))
        assertEquals(Competition.State.SCHEDULED, races[0].state)
        assertFalse(races[0].isRelay)
        assertEquals(Competition.State.FINISHED, races[1].state)
        assertTrue(races[1].isRelay)
    }

    @Test
    fun relayResults() {
        val results = decode<RaceResults>(fixture("relay-results"))
        assertEquals(1, results.standings.size)
        val norway = results.standings.first()
        assertEquals(listOf("ULDAL Martin"), results.legs(norway).map { it.name })
    }

    /**
     * A start list ranks nobody, and the first athlete to start isn't the leader: a leader needs
     * a rank, and someone out of the race (DNS, DNF…) has none that counts.
     */
    @Test
    fun theLeaderIsTheFirstRankedRowStillInTheRace() {
        val startList = """{"IsStartList":true,"IsResult":false,"Results":[{"Name":"BOE J.T.","Rank":null,"IRM":null}]}"""
        val running = """{"IsStartList":false,"IsResult":false,"Results":[""" +
            """{"Name":"BOE J.T.","Rank":null,"IRM":"DNS"},{"Name":"PERROT E.","Rank":"1","IRM":null}]}"""

        assertNull(decode<RaceResults>(startList).leader)
        assertEquals("PERROT E.", decode<RaceResults>(running).leader?.name)
    }

    /** A relay's podium is of teams, not of their legs. */
    @Test
    fun relayPodiumIsOfTeams() {
        val results = decode<RaceResults>(fixture("relay-results"))
        assertEquals(listOf("NORWAY"), results.podium.map { it.name })
    }

    /** `SportEvt` of `Results?RaceId=BT2526SWRLCP01SMRL`: the event the race belongs to. */
    @Test
    fun raceResultsNameTheirEvent() {
        val event = checkNotNull(decode<RaceResults>(fixture("relay-results")).event)
        assertEquals("Oestersund", event.shortDescription)
        assertEquals("SWE", event.nation)
    }

    @Test
    fun cupStandingsAcceptNumericScores() {
        val cup = decode<CupStandings>(fixture("cup-results"))
        assertEquals(2, cup.rows.size)
        assertEquals(listOf("yellow"), cup.rows[0].bibColors)
        assertEquals("968", cup.rows[1].score)
        assertEquals(-1, cup.rows[1].rankChange)
    }

    @Test
    fun athleteDateWithoutTimeZone() {
        val bio = decode<AthleteBio>(fixture("athlete"))
        assertEquals(instant("2001-06-29T00:00:00Z"), bio.birthdate)
        assertEquals("BTFRA12906200101.png", bio.photoUrl?.path?.substringAfterLast('/'))
        assertFalse(bio.isDeceased)
    }

    /** As `CISBios?IBUId=BTNOR11807199801` returns Sivert Guttorm Bakken, who died in December 2025. */
    @Test
    fun deceasedAthlete() {
        val bio = decode<AthleteBio>(
            """{"IBUId":"BTNOR11807199801","FullName":"Sivert Guttorm BAKKEN","NAT":"NOR","Age":null,"Functions":"Deceased"}""",
        )
        assertTrue(bio.isDeceased)
        assertNull(bio.age(instant("2026-10-27T12:00:00Z")))
    }

    /** Eric Perrot, born on 29 June 2001: the age turns on the birthday, in UTC like the birthdate. */
    @ParameterizedTest
    @CsvSource("2026-06-28T23:59:00Z, 24", "2026-06-29T00:00:00Z, 25", "2026-10-27T12:00:00Z, 25")
    fun athleteAge(day: String, age: Int) {
        assertEquals(age, decode<AthleteBio>(fixture("athlete")).age(instant(day)))
    }

    @Test
    fun noAgeWithoutABirthdate() {
        assertNull(decode<AthleteBio>("""{"IBUId":"BTFRA20910199601"}""").age(instant("2026-10-27T12:00:00Z")))
    }

    /** `GenderId` of `CISBios`: "M" for Sivert Guttorm Bakken, "W" for Julia Simon. */
    @ParameterizedTest
    @CsvSource("M, MAN", "W, WOMAN", "X,")
    fun athleteGender(id: String, gender: Gender?) {
        assertEquals(gender, decode<AthleteBio>("""{"IBUId":"BTFRA20910199601","GenderId":"$id"}""").gender)
    }

    /** As `CupResults?CupId=BT2526SWRLCP__SWNC` returns them: a nation's `IBUId` is its code. */
    @Test
    fun nationsStandingsRowsAreNations() {
        val cup = decode<CupStandings>(
            """{"Rows":[{"Rank":"1","IBUId":"SWE","Name":"Sweden","ShortName":"Sweden","Nat":"SWE","Score":"6815"}]}""",
        )
        val row = cup.rows.first()
        assertTrue(row.isNation)
        assertNull(row.athleteId)
        assertEquals("SWE", row.nation)
    }

    /** Real IDs: `BT2425SWRLCP01` (Kontiolahti), `BT2425SWRLCH__` (Lenzerheide). */
    @Test
    fun worldChampionships() {
        val championships = decode<BiathlonEvent>(event("BT2425SWRLCH__", "2025-02-11T12:00:00Z", "2025-02-23T12:00:00Z"))
        assertTrue(championships.isWorldChampionships)
        assertFalse(championships.isOlympics)
    }

    /** The Olympics are in the World Cup calendar (`Level=1`): `BT2526SWRLOG__` (Antholz-Anterselva). */
    @Test
    fun olympics() {
        val olympics = decode<BiathlonEvent>(event("BT2526SWRLOG__", "2026-02-06T12:00:00Z", "2026-02-22T12:00:00Z"))
        assertTrue(olympics.isOlympics)
        assertFalse(olympics.isWorldChampionships)
    }
}
