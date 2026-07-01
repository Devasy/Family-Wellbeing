package com.family.family_wellbeing

import android.content.Context
import android.util.Log
import androidx.work.*
import java.time.LocalDate
import java.util.concurrent.TimeUnit

class DailySyncWorker(
    appContext: Context, 
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val extractor = UsageStatsExtractor(applicationContext)
        
        if (!extractor.hasUsageStatsPermission()) {
            Log.e("SyncWorker", "Missing Usage Stats Permission. Cannot sync.")
            return Result.failure()
        }

        val sharedPrefs = applicationContext.getSharedPreferences("WellbeingPrefs", Context.MODE_PRIVATE)
        val mongoUri = sharedPrefs.getString("MONGO_URI", null)
        val myMemberId = sharedPrefs.getString("MEMBER_ID", null)

        if (mongoUri.isNullOrEmpty() || myMemberId.isNullOrEmpty()) {
            Log.e("SyncWorker", "Missing configuration (Mongo URI or Member ID). Cannot sync.")
            return Result.failure()
        }

        val mongoService = MongoDbSyncService(mongoUri)
        val today = LocalDate.now()

        try {
            // Sync past 14 days (COMPLETE DATA - locks final scores)
            for (i in 1..14) {
                val pastDay = today.minusDays(i.toLong())
                val pastStats = extractor.getUsageForDate(pastDay)
                val pastTotal = pastStats.sumOf { it.minutes }
                
                if (pastTotal > 0) {
                    val pastDoc = DailyUsageDocument(
                        _id = "${myMemberId}_${pastDay}",
                        memberId = myMemberId,
                        date = pastDay.toString(),
                        totalScreenTimeMinutes = pastTotal,
                        appBreakdown = pastStats,
                        isComplete = true,
                        syncedAt = System.currentTimeMillis()
                    )
                    mongoService.upsertUsageRecord(pastDoc)
                }
            }

            // Sync Today (INCOMPLETE DATA - for live overview)
            val todayStats = extractor.getUsageForDate(today)
            val todayTotal = todayStats.sumOf { it.minutes }
            
            val todayDoc = DailyUsageDocument(
                _id = "${myMemberId}_${today}",
                memberId = myMemberId,
                date = today.toString(),
                totalScreenTimeMinutes = todayTotal,
                appBreakdown = todayStats,
                isComplete = false,
                syncedAt = System.currentTimeMillis()
            )
            mongoService.upsertUsageRecord(todayDoc)

            mongoService.close()
            return Result.success()
        } catch (e: Exception) {
            Log.e("SyncWorker", "Error during sync execution: ${e.message}")
            mongoService.close()
            return Result.retry()
        }
    }
}

object WorkManagerHelper {
    
    fun scheduleDailySync(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val syncRequest = PeriodicWorkRequestBuilder<DailySyncWorker>(
            24, TimeUnit.HOURS,
            2, TimeUnit.HOURS
        )
        .setConstraints(constraints)
        .build()

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
