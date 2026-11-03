package com.fouteox.biathlon.kit

import java.time.Instant

/**
 * What the server publishes of a race for its Live Update: on the race's FCM topic
 * (`buildTopicMessage`, server/src/fcm.ts), and from `GET /v1/races/:id/channels/fcm` for a race
 * just followed or a message missed.
 */
sealed interface LiveUpdate {
    val raceId: String
    val state: RaceLiveState

    /** When the server published it: FCM doesn't keep messages in order, so one older than the state on screen came late. */
    val publishedAt: Instant?

    /** The race's state. */
    data class Update(override val raceId: String, override val state: RaceLiveState, override val publishedAt: Instant) : LiveUpdate

    /**
     * The race is over: its final [state] stays until [dismissal], 30 minutes after the end
     * (`dismissalDate`, server/src/live.ts). [publishedAt] is `null` for the end the server
     * answers with as the race's current state, which comes as no message.
     */
    data class End(
        override val raceId: String,
        override val state: RaceLiveState,
        val dismissal: Instant,
        override val publishedAt: Instant?,
    ) : LiveUpdate

    companion object {
        /** The race's FCM topic (`raceTopic`, server/src/fcm.ts). */
        fun topic(raceId: String): String = "race-$raceId"

        /** A message of a race's topic, from its data; `null` for any other message, like an alert. */
        fun parse(data: Map<String, String>): LiveUpdate? {
            val raceId = data["raceId"] ?: return null
            val state = data["state"]?.let(::decodeState) ?: return null
            val publishedAt = data["timestamp"]?.toLongOrNull()?.let(Instant::ofEpochSecond) ?: return null
            return when (data["event"]) {
                "update" -> Update(raceId, state, publishedAt)
                "end" -> data["dismissalDate"]?.toLongOrNull()?.let { End(raceId, state, Instant.ofEpochSecond(it), publishedAt) }
                else -> null
            }
        }

        // Malformed JSON and unexpected shapes alike: SerializationException is one too.
        private fun decodeState(json: String): RaceLiveState? = try {
            IbuJson.decodeFromString<RaceLiveState>(json)
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}
