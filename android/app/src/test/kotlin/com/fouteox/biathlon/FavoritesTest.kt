package com.fouteox.biathlon

import com.fouteox.biathlon.kit.FavoriteSet
import com.fouteox.biathlon.kit.Gender
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.sample
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The favorites, in a database of their own for each test. */
@RunWith(RobolectricTestRunner::class)
class FavoritesTest {
    private val favorites = inMemoryFavorites()

    @Test
    fun theStarAddsAFavoriteThenRemovesIt() = runBlocking {
        favorites.toggle(Favorite.Kind.ATHLETE, "BTNORSM01", "Aksel VANGEN", "NOR")
        assertTrue(favorites.contains(Favorite.Kind.ATHLETE, "BTNORSM01").first())
        // A nation's code is no athlete's ID.
        assertFalse(favorites.contains(Favorite.Kind.NATION, "BTNORSM01").first())
        favorites.toggle(Favorite.Kind.ATHLETE, "BTNORSM01", "Aksel VANGEN", "NOR")
        assertFalse(favorites.contains(Favorite.Kind.ATHLETE, "BTNORSM01").first())
    }

    @Test
    fun listsTheFavoritesInTheOrderTheyWereAdded() = runBlocking {
        favorites.toggle(Favorite.Kind.NATION, "NOR", "Norway", "NOR")
        favorites.toggle(Favorite.Kind.ATHLETE, "BTNORSM01", "Aksel VANGEN", "NOR")
        assertEquals(listOf("NOR", "BTNORSM01"), favorites.all.first().map { it.key })
        assertEquals(FavoriteSet(athleteIds = setOf("BTNORSM01"), nations = setOf("NOR")), favorites.set.first())
    }

    @Test
    fun removesAFavorite() = runBlocking {
        favorites.toggle(Favorite.Kind.NATION, "NOR", "Norway", "NOR")
        favorites.remove(favorites.all.first().single())
        assertTrue(favorites.all.first().isEmpty())
    }

    /** What was saved with the favorite follows the athlete's IBU profile. */
    @Test
    fun refreshesTheAthletesFromTheirProfiles() = runBlocking {
        favorites.toggle(Favorite.Kind.ATHLETE, "BTNORSM01", "Aksel", null)
        favorites.toggle(Favorite.Kind.NATION, "NOR", "Norway", "NOR")
        favorites.refreshAthletes(IbuClient.sample(Instant.now()))
        val (athlete, nation) = favorites.all.first()
        assertEquals(Favorite(Favorite.Kind.ATHLETE, "BTNORSM01", "Aksel VANGEN", "NOR", athlete.addedAt, gender = Gender.MAN), athlete)
        assertEquals("Norway", nation.name)
    }

    /** An athlete the IBU fails to return keeps what was saved, until the next visit. */
    @Test
    fun keepsAnAthleteWhoseProfileFails() = runBlocking {
        favorites.toggle(Favorite.Kind.ATHLETE, "BTNORSM01", "Aksel", null)
        favorites.refreshAthletes(IbuClient.sample(Instant.now()) { it == "CISBios" })
        assertEquals("Aksel", favorites.all.first().single().name)
    }
}
