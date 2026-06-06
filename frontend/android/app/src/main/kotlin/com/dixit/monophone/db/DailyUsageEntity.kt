package com.dixit.monophone.db

/**
 * Data class representing daily accumulated usage for a single app package.
 *
 * Stored in the daily_usage SQLite table via [UsageDatabase].
 * The composite primary key is (packageName, date).
 */
data class DailyUsageEntity(
    val packageName: String,
    val date: String,
    val accumulatedSeconds: Int
)