package com.fouteox.biathlon.kit

/** IBU race category (`catId`). */
enum class RaceCategory(val code: String) {
    MEN("SM"),
    WOMEN("SW"),
    MIXED("MX"),
    ;

    companion object {
        /** Standings exist for men and women only. */
        val WITH_STANDINGS = listOf(MEN, WOMEN)

        fun of(code: String): RaceCategory? = entries.firstOrNull { it.code == code }
    }
}
