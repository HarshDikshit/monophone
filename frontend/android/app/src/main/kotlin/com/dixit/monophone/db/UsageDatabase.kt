package com.dixit.monophone.db

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.concurrent.Executors

/**
 * SQLite database singleton for persisting daily app usage.
 *
 * Replaces Room (unavailable in this project) with the standard
 * Android [SQLiteOpenHelper] pattern.
 *
 * ── Threading ──
 * All DAO operations should run via [databaseWriteExecutor] to
 * avoid multi-thread write conflicts.
 *
 * ── Schema Version 1 ──
 * CREATE TABLE daily_usage (
 *     packageName TEXT NOT NULL,
 *     date TEXT NOT NULL,
 *     accumulatedSeconds INTEGER NOT NULL DEFAULT 0,
 *     PRIMARY KEY (packageName, date)
 * );
 */
class UsageDatabase private constructor(context: Context) :
    SQLiteOpenHelper(
        context.applicationContext,
        "focus_blocker_usage.db",
        null,
        DATABASE_VERSION
    ) {

    companion object {
        private const val DATABASE_VERSION = 1

        @Volatile
        private var INSTANCE: UsageDatabase? = null

        /** Single-thread executor for all DAO calls. */
        val databaseWriteExecutor = Executors.newSingleThreadExecutor()

        /**
         * Return the singleton [UsageDatabase], creating it on first call.
         */
        fun getInstance(context: Context): UsageDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: UsageDatabase(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(DailyUsageDao.CREATE_TABLE)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // For now, drop and recreate.  Provide proper migration in production.
        db.execSQL("DROP TABLE IF EXISTS ${DailyUsageDao.TABLE_NAME}")
        onCreate(db)
    }

    /**
     * Convenience accessor — returns a [DailyUsageDao] backed by this database.
     * Callers should execute on [databaseWriteExecutor].
     */
    fun dailyUsageDao(): DailyUsageDao {
        return DailyUsageDao(writableDatabase)
    }
}