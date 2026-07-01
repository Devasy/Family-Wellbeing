package com.family.wellbeing.core

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Process
import android.util.Log
import androidx.work.*
import com.mongodb.client.model.Filters
import com.mongodb.client.model.UpdateOptions
import com.mongodb.kotlin.client.coroutine.MongoClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.withContext
import org.bson.Document
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

/**
 * Data models matching the MongoDB Schema.
 * These represent the document structure we will push to Atlas.
 */
data class AppUsageRecord(
    val appName: String,
    val packageName: String,
    val minutes: Long
)

data class DailyUsageDocument(
    val _id: String, // format: "memberId_YYYY-MM-DD"
    val memberId: String,
    val date: String, // format: "YYYY-MM-DD"
    val totalScreenTimeMinutes: Long,
    val appBreakdown: List<AppUsageRecord>,
    val isComplete: Boolean,
    val syncedAt: Long // Epoch timestamp
)

/**
 * Helper class to interact with Android's UsageStatsManager.
 * Requires PACKAGE_USAGE_STATS permission granted via settings.
 */
class UsageStatsExtractor(private val context: Context) {

    private val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val packageManager = context.packageManager

    /**
     * Check if the user has granted the special Usage Access permission.
     */
    fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Gets total foreground time per app for a specific calendar day.
     */
    fun getUsageForDate(date: LocalDate): List<AppUsageRecord> {
        val zoneId = ZoneId.systemDefault()
        // Start: Midnight of the requested day
        val startOfDay = date.atStartOfDay(zoneId).toInstant().toEpochMilli()
        // End: 1 millisecond before midnight of the next day
        val endOfDay = date.plusDays(1).atStartOfDay(zoneId).toInstant().toEpochMilli() - 1

        // Use INTERVAL_DAILY to let the OS bucket the data appropriately
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startOfDay,
            endOfDay
        )

        val breakdown = mutableListOf<AppUsageRecord>()

        for (usage in stats) {
            // Ignore system processes and apps with less than 1 minute of usage
            if (usage.totalTimeInForeground > 60_000L) { 
                try {
                    val appInfo = packageManager.getApplicationInfo(usage.packageName, 0)
                    
                    // Optional: Filter out basic system apps (launchers, settings, etc.)
                    // if ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0) continue

                    val appName = packageManager.getApplicationLabel(appInfo).toString()
                    val minutes = TimeUnit.MILLISECONDS.toMinutes(usage.totalTimeInForeground)

                    // queryUsageStats can sometimes return multiple buckets for the same app,
                    // so we group and sum them if necessary (though INTERVAL_DAILY usually handles this)
                    breakdown.add(AppUsageRecord(appName, usage.packageName, minutes))
                } catch (e: PackageManager.NameNotFoundException) {
                    // App was uninstalled or hidden, skip
                    continue
                }
            }
        }

        // Aggregate duplicates (just in case) and sort by highest usage
        return breakdown
            .groupBy { it.packageName }
            .map { entry ->
                AppUsageRecord(
                    appName = entry.value.first().appName,
                    packageName = entry.key,
                    minutes = entry.value.sumOf { it.minutes }
                )
            }
            .sortedByDescending { it.minutes }
    }
}

/**
 * Service to handle direct connection to MongoDB Atlas using the official Kotlin Coroutine driver.
 */
class MongoDbSyncService(private val connectionString: String) {

    // Note: In production, MongoClient should be a singleton injected via Dagger/Hilt.
    private val client = MongoClient.create(connectionString)
    private val database = client.getDatabase("wellbeing")
    private val collection = database.getCollection<Document>("daily_usage")

    /**
     * Upserts a usage document. If the _id (memberId_date) exists, it overwrites it.
     */
    suspend fun upsertUsageRecord(record: DailyUsageDocument): Boolean = withContext(Dispatchers.IO) {
        try {
            // Convert our Data Class to a BSON Document
            val doc = Document("_id", record._id)
                .append("memberId", record.memberId)
                .append("date", record.date)
                .append("totalScreenTimeMinutes", record.totalScreenTimeMinutes)
                .append("isComplete", record.isComplete)
                .append("syncedAt", record.syncedAt)
                
            val breakdownList = record.appBreakdown.map { app ->
                Document("appName", app.appName)
                    .append("packageName", app.packageName)
                    .append("minutes", app.minutes)
            }
            doc.append("appBreakdown", breakdownList)

            // Upsert operation
            val filter = Filters.eq("_id", record._id)
            val update = Document("\$set", doc)
            val options = UpdateOptions().upsert(true)

            val result = collection.updateOne(filter, update, options)
            return@withContext result.wasAcknowledged()
        } catch (e: Exception) {
            Log.e("MongoSync", "Failed to upsert record: ${e.message}")
            return@withContext false
        }
    }
}

/**
 * WorkManager Job that runs daily to extract data and push to MongoDB.
 */
class DailySyncWorker(
    appContext: Context, 
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val extractor = UsageStatsExtractor(applicationContext)
        
        // 1. Check Permissions
        if (!extractor.hasUsageStatsPermission()) {
            Log.e("SyncWorker", "Missing Usage Stats Permission. Cannot sync.")
            return Result.failure()
        }

        // In a real app, retrieve these from EncryptedSharedPreferences
        val sharedPrefs = applicationContext.getSharedPreferences("WellbeingPrefs", Context.MODE_PRIVATE)
        val mongoUri = sharedPrefs.getString("MONGO_URI", null)
        val myMemberId = sharedPrefs.getString("MEMBER_ID", null)

        if (mongoUri.isNullOrEmpty() || myMemberId.isNullOrEmpty()) {
            Log.e("SyncWorker", "Missing configuration. Cannot sync.")
            return Result.failure()
        }

        val mongoService = MongoDbSyncService(mongoUri)
        val today = LocalDate.now()
        val yesterday = today.minusDays(1)

        try {
            // 2. Sync Yesterday (COMPLETE DATA - Locks in the final leaderboard score)
            val yesterdayStats = extractor.getUsageForDate(yesterday)
            val yesterdayTotal = yesterdayStats.sumOf { it.minutes }
            
            val yesterdayDoc = DailyUsageDocument(
                _id = "${myMemberId}_${yesterday}",
                memberId = myMemberId,
                date = yesterday.toString(),
                totalScreenTimeMinutes = yesterdayTotal,
                appBreakdown = yesterdayStats,
                isComplete = true, // Flagged as complete
                syncedAt = System.currentTimeMillis()
            )
            mongoService.upsertUsageRecord(yesterdayDoc)

            // 3. Sync Today (INCOMPLETE DATA - For live dashboard viewing)
            val todayStats = extractor.getUsageForDate(today)
            val todayTotal = todayStats.sumOf { it.minutes }
            
            val todayDoc = DailyUsageDocument(
                _id = "${myMemberId}_${today}",
                memberId = myMemberId,
                date = today.toString(),
                totalScreenTimeMinutes = todayTotal,
                appBreakdown = todayStats,
                isComplete = false, // Flagged as incomplete, will be overwritten tomorrow
                syncedAt = System.currentTimeMillis()
            )
            mongoService.upsertUsageRecord(todayDoc)

            // (Optional): Add logic here to walk backwards if phone was offline for days
            // using a `lastSyncedDate` saved in SharedPreferences.

            return Result.success()
        } catch (e: Exception) {
            Log.e("SyncWorker", "Error during sync execution: ${e.message}")
            return Result.retry()
        }
    }
}

/**
 * Helper object to enqueue the WorkManager job from your UI/Activity.
 */
object WorkManagerHelper {
    
    fun scheduleDailySync(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            // Optional: .setRequiresCharging(true) if you only want to sync at night while charging
            .build()

        val syncRequest = PeriodicWorkRequestBuilder<DailySyncWorker>(
            24, TimeUnit.HOURS, // Run once a day
            2, TimeUnit.HOURS   // Flex interval (Android optimizes battery based on this)
        )
        .setConstraints(constraints)
        .build()

        // KEEP ensures we don't spam duplicate jobs
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "DailyWellbeingSync",
            ExistingPeriodicWorkPolicy.KEEP,
            syncRequest
        )
    }
    
    fun triggerImmediateSync(context: Context) {
        val syncRequest = OneTimeWorkRequestBuilder<DailySyncWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
            
        WorkManager.getInstance(context).enqueue(syncRequest)
    }
}