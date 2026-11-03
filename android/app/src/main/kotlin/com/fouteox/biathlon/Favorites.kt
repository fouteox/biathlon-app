package com.fouteox.biathlon

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import com.fouteox.biathlon.kit.FavoriteSet
import com.fouteox.biathlon.kit.Gender
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.Nation
import java.time.Instant
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** A favorite, as the iOS app keeps it: an athlete (key = IBU ID) or a nation (key = IOC code), once each. */
@Entity(tableName = "favorite", primaryKeys = ["kind", "key"])
data class Favorite(
    val kind: Kind,
    val key: String,
    val name: String,
    val nation: String?,
    val addedAt: Instant,
    /** From the IBU profile ([Favorites.refreshAthletes]). */
    val isDeceased: Boolean = false,
    /** From the IBU profile ([Favorites.refreshAthletes]), for "Deceased" to agree in French. */
    val gender: Gender? = null,
) {
    enum class Kind { ATHLETE, NATION }

    /** A nation reads in the app's language whatever name it was saved under. */
    val title: String get() = if (kind == Kind.NATION) Nation.localizedName(key) else name
}

@Dao
interface FavoriteDao {
    @Query("SELECT * FROM favorite ORDER BY addedAt")
    fun all(): Flow<List<Favorite>>

    @Query("SELECT EXISTS(SELECT 1 FROM favorite WHERE kind = :kind AND `key` = :key)")
    fun contains(kind: Favorite.Kind, key: String): Flow<Boolean>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(favorite: Favorite)

    /** The number of favorites removed: one, or none. */
    @Query("DELETE FROM favorite WHERE kind = :kind AND `key` = :key")
    suspend fun delete(kind: Favorite.Kind, key: String): Int

    @Transaction
    suspend fun toggle(favorite: Favorite) {
        if (delete(favorite.kind, favorite.key) == 0) insert(favorite)
    }

    @Query("UPDATE favorite SET name = :name, nation = :nation, isDeceased = :isDeceased, gender = :gender WHERE kind = 'ATHLETE' AND `key` = :id")
    suspend fun updateAthlete(id: String, name: String, nation: String?, isDeceased: Boolean, gender: Gender?)
}

class InstantConverters {
    @TypeConverter
    fun toEpochMilli(instant: Instant): Long = instant.toEpochMilli()

    @TypeConverter
    fun fromEpochMilli(milliseconds: Long): Instant = Instant.ofEpochMilli(milliseconds)
}

@Database(entities = [Favorite::class], version = 1)
@TypeConverters(InstantConverters::class)
abstract class FavoritesDatabase : RoomDatabase() {
    abstract fun favorites(): FavoriteDao

    companion object {
        fun open(context: Context): FavoritesDatabase = Room.databaseBuilder<FavoritesDatabase>(context, "favorites.db").build()
    }
}

/** The athletes and nations followed, on the device: what every list marks and what the Favorites tab lists. */
class Favorites(private val dao: FavoriteDao) {
    /** In the order they were added. */
    val all: Flow<List<Favorite>> = dao.all()

    val set: Flow<FavoriteSet> = all.map { favorites ->
        FavoriteSet(
            athleteIds = favorites.filter { it.kind == Favorite.Kind.ATHLETE }.mapTo(mutableSetOf()) { it.key },
            nations = favorites.filter { it.kind == Favorite.Kind.NATION }.mapTo(mutableSetOf()) { it.key },
        )
    }

    fun contains(kind: Favorite.Kind, key: String): Flow<Boolean> = dao.contains(kind, key)

    suspend fun toggle(kind: Favorite.Kind, key: String, name: String, nation: String?) {
        dao.toggle(Favorite(kind, key, name, nation, Instant.now()))
    }

    suspend fun remove(favorite: Favorite) {
        dao.delete(favorite.kind, favorite.key)
    }

    /**
     * Follows the athletes' IBU profiles, what was saved with each favorite going stale: an athlete
     * can change nation (Jakov Fak, from CRO to SLO) or name, or pass away. One whose profile fails
     * to load keeps what was saved, until the next visit.
     */
    suspend fun refreshAthletes(client: IbuClient) = coroutineScope {
        for (favorite in all.first().filter { it.kind == Favorite.Kind.ATHLETE }) {
            launch {
                val bio = attempt { client.athlete(favorite.key) }.value ?: return@launch
                dao.updateAthlete(favorite.key, bio.fullName, bio.nation, bio.isDeceased, bio.gender)
            }
        }
    }
}
