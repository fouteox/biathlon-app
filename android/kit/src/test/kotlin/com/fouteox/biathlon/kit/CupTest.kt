package com.fouteox.biathlon.kit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

class CupTest {
    @Test
    fun worldCupId() {
        assertEquals("BT2627SWRLCP__SMTS", Cup.worldCupId(SeasonId("2627"), RaceCategory.MEN, StandingsDiscipline.TOTAL))
        assertEquals("BT2526SWRLCP__SWNC", Cup.worldCupId(SeasonId("2526"), RaceCategory.WOMEN, StandingsDiscipline.NATIONS))
    }

    /** A nation's screen lists its athletes in the order of the standings, without the nation's own row. */
    @Test
    fun athletesOfANation() {
        val cup = decode<CupStandings>(
            """{"Rows":[{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA"},{"Rank":"2","IBUId":"BTNOR1","Name":"B","Nat":"NOR"},""" +
                """{"Rank":"3","IBUId":"BTFRA2","Name":"C","Nat":"FRA"},{"Rank":"1","IBUId":"FRA","Name":"France","Nat":"FRA"}]}""",
        )
        assertEquals(listOf("BTFRA1", "BTFRA2"), cup.athletes("FRA").map { it.athleteId })
        assertTrue(cup.athletes("SWE").isEmpty())
    }

    /** An athlete's standings are those of their gender. */
    @ParameterizedTest
    @CsvSource("MAN, MEN", "WOMAN, WOMEN")
    fun standingsCategoryOfAGender(gender: Gender, category: RaceCategory) {
        assertEquals(category, gender.category)
    }
}
