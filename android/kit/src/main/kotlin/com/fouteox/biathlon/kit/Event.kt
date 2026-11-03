package com.fouteox.biathlon.kit

import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** An event (Kontiolahti, Hochfilzen…), from `Events`. */
@Serializable
data class BiathlonEvent(
    @SerialName("EventId") val id: String,
    @SerialName("ShortDescription") val shortDescription: String,
    @SerialName("StartDate") @Serializable(IbuInstantSerializer::class) val startDate: Instant,
    @SerialName("EndDate") @Serializable(IbuInstantSerializer::class) val endDate: Instant,
    @SerialName("Nat") val nation: String? = null,
) {
    /** World Championships IDs end in `SWRLCH__` (`BT2425SWRLCH__`), World Cup stages in `SWRLCP` and a number. */
    val isWorldChampionships: Boolean get() = id.endsWith("SWRLCH__")

    /** The Olympics, in the World Cup calendar too, end in `SWRLOG__` (`BT2526SWRLOG__`). */
    val isOlympics: Boolean get() = id.endsWith("SWRLOG__")

    enum class Phase { PAST, UNDERWAY, UPCOMING }
}
