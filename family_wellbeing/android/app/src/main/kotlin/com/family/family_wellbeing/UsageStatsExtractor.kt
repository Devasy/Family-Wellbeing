package com.family.family_wellbeing

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Process
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit

data class AppUsageRecord(
    val appName: String,
    val packageName: String,
    val minutes: Long
)

class UsageStatsExtractor(private val context: Context) {

    private val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val packageManager = context.packageManager

    fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun getUsageForDate(date: LocalDate): List<AppUsageRecord> {
        val zoneId = ZoneId.systemDefault()
        val startOfDay = date.atStartOfDay(zoneId).toInstant().toEpochMilli()
        val endOfDay = date.plusDays(1).atStartOfDay(zoneId).toInstant().toEpochMilli() - 1

        val statsMap = usageStatsManager.queryAndAggregateUsageStats(startOfDay, endOfDay)
        val breakdown = mutableListOf<AppUsageRecord>()

        if (statsMap != null) {
            for ((packageName, usage) in statsMap) {
                if (usage.totalTimeInForeground > 60_000L) { // > 1 minute
                    try {
                        val appInfo = packageManager.getApplicationInfo(packageName, 0)
                        val appName = packageManager.getApplicationLabel(appInfo).toString()
                        val minutes = TimeUnit.MILLISECONDS.toMinutes(usage.totalTimeInForeground)
                        if (minutes > 0) {
                            breakdown.add(AppUsageRecord(appName, packageName, minutes))
                        }
                    } catch (e: PackageManager.NameNotFoundException) {
                        continue
                    }
                }
            }
        }

        return breakdown.sortedByDescending { it.minutes }
    }
}
