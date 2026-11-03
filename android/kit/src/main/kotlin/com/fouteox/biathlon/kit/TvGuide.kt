package com.fouteox.biathlon.kit

import java.net.URI
import java.time.Instant
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Who shows the races on TV, by country and period: the server's `/v1/tv-coverage`, which keeps
 * it by hand from the broadcasters' announcements.
 */
@Serializable
data class TvGuide(val coverage: List<Coverage>) {
    /** A broadcaster of a country, from `from` (included) to `until` (excluded). */
    @Serializable
    data class Coverage(
        /** ISO 3166 code. */
        val country: String,
        val broadcaster: String,
        /** Where the broadcaster streams live. */
        @Serializable(UriSerializer::class) val url: URI,
        @Serializable(IbuInstantSerializer::class) val from: Instant,
        @Serializable(IbuInstantSerializer::class) val until: Instant,
    )

    /** A country's broadcasters for one race. */
    data class Listing(val country: String, val broadcasters: List<Coverage>)

    /** The broadcasters of a race: the viewer's own country apart, the others in the guide's order. */
    data class Listings(val home: Listing?, val others: List<Listing>) {
        val isEmpty: Boolean get() = home == null && others.isEmpty()
    }

    /**
     * The countries with a broadcaster at `start`, `home` (the viewer's region) set apart from
     * the others, which every viewer can still look up, whatever the app's language.
     */
    fun listings(start: Instant, home: String?): Listings {
        val airing = coverage.filter { it.from <= start && start < it.until }
        val listings = airing.map { it.country }.distinct().map { country -> Listing(country, airing.filter { it.country == country }) }
        return Listings(listings.firstOrNull { it.country == home }, listings.filter { it.country != home })
    }
}

private object UriSerializer : KSerializer<URI> {
    override val descriptor = PrimitiveSerialDescriptor("Uri", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): URI = URI(decoder.decodeString())

    override fun serialize(encoder: Encoder, value: URI) = encoder.encodeString(value.toString())
}
