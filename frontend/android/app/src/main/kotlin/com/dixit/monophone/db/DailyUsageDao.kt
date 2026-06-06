package com.dixit.monophone.db

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase

/**
 * Data-access object for the [DailyUsageEntity] table.
 *
 * All operations use raw SQLite (via [UsageDatabase]) since this project
 * does not have the Room annotation-processor dependency.
 *
 * Thread-safety is provided by [UsageDatabase.databaseWriteExecutor]
 * which serialises all writes through a single-thread executor.
 */
class DailyUsageDao(private val db: SQLiteDatabase) {

    companion object {
        const val TABLE_NAME = "daily_usage"
        const val COL_PACKAGE = "packageName"
        const val COL_DATE = "date"
        const val COL_SECONDS = "accumulatedSeconds"

        val CREATE_TABLE = """
            CREATE TABLE IF NOT EXISTS $TABLE_NAME (
                $COL_PACKAGE TEXT NOT NULL,
                $COL_DATE TEXT NOT NULL,
                $COL_SECONDS INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY ($COL_PACKAGE, $COL_DATE)
            )
        """.trimIndent()
    }

    /**
     * Atomically add [additionalSeconds] to the accumulated time for a
     * specific package on a specific date.  If no row exists yet, inserts one.
     */
    fun incrementUsage(packageName: String, date: String, additionalSeconds: Int) {
        // Try update first; if no row was updated, insert.
        val values = ContentValues().apply {
            put(COL_SECONDS, additionalSeconds)
        }
        val rowsUpdated = db.update(
            TABLE_NAME,
            values,
            "$COL_PACKAGE = ? AND $COL_DATE = ?",
            arrayOf(packageName, date)
        )
        if (rowsUpdated == 0) {
            // Insert new row
            val insertValues = ContentValues().apply {
                put(COL_PACKAGE, packageName)
                put(COL_DATE, date)
                put(COL_SECONDS, additionalSeconds)
            }
            db.insert(TABLE_NAME, null, insertValues)
        } else {
            // Row existed — we need to ADD to the existing value,
            // not replace it.  Use a raw SQL UPDATE.
            db.execSQL(
                "UPDATE $TABLE_NAME SET $COL_SECONDS = $COL_SECONDS + ? " +
                        "WHERE $COL_PACKAGE = ? AND $COL_DATE = ?",
                arrayOf(additionalSeconds, packageName, date)
            )
        }
    }

    /**
     * Return the accumulated seconds for [packageName] on [date],
     * or 0 if no row exists.
     */
    fun getUsage(packageName: String, date: String): Int {
        val cursor = db.query(
            TABLE_NAME,
            arrayOf(COL_SECONDS),
            "$COL_PACKAGE = ? AND $COL_DATE = ?",
            arrayOf(packageName, date),
            null, null, null
        )
        return cursor.use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    /**
     * Return usage for all tracked packages on a specific date.
     */
    fun getAllUsageForDate(date: String): List<DailyUsageEntity> {
        val result = mutableListOf<DailyUsageEntity>()
        val cursor = db.query(
            TABLE_NAME,
            null,
            "$COL_DATE = ?",
            arrayOf(date),
            null, null, null
        )
        cursor.use {
            while (it.moveToNext()) {
                result.add(
                    DailyUsageEntity(
                        packageName = it.getString(it.getColumnIndexOrThrow(COL_PACKAGE)),
                        date = it.getString(it.getColumnIndexOrThrow(COL_DATE)),
                        accumulatedSeconds = it.getInt(it.getColumnIndexOrThrow(COL_SECONDS))
                    )
                )
            }
        }
        return result
    }

    /**
     * Return usage rows for a single package across multiple dates.
     */
    fun getUsageHistoryForPackage(packageName: String): List<DailyUsageEntity> {
        val result = mutableListOf<DailyUsageEntity>()
        val cursor = db.query(
            TABLE_NAME,
            null,
            "$COL_PACKAGE = ?",
            arrayOf(packageName),
            null, null, "$COL_DATE ASC"
        )
        cursor.use {
            while (it.moveToNext()) {
                result.add(
                    DailyUsageEntity(
                        packageName = it.getString(it.getColumnIndexOrThrow(COL_PACKAGE)),
                        date = it.getString(it.getColumnIndexOrThrow(COL_DATE)),
                        accumulatedSeconds = it.getInt(it.getColumnIndexOrThrow(COL_SECONDS))
                    )
                )
            }
        }
        return result
    }

    /**
     * Delete rows older than [cutoffDate].
     */
    fun pruneOldEntries(cutoffDate: String) {
        db.delete(TABLE_NAME, "$COL_DATE < ?", arrayOf(cutoffDate))
    }
}