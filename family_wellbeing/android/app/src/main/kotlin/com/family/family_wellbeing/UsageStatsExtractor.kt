package com.family.family_wellbeing

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
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

    // Never count these towards a person's screen time.
    private val excludedPackages = setOf(
        context.packageName, // this app itself
        "android",
        "com.android.systemui"
    )

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
     * Reconstructs real foreground sessions from raw usage events instead of
     * relying on queryUsageStats' pre-aggregated buckets, which are not
     * clipped to the day you ask for and silently misattribute time.
     */
    fun getUsageForDate(date: LocalDate): List<AppUsageRecord> {
        val zoneId = ZoneId.systemDefault()
        val dayStart = date.atStartOfDay(zoneId).toInstant().toEpochMilli()
        val dayEnd = date.plusDays(1).atStartOfDay(zoneId).toInstant().toEpochMilli()

        // Look back before midnight so a session already open when the day
        // started (e.g. using an app right across midnight) is captured.
        // We still only count the slice that falls inside [dayStart, dayEnd).
        val queryStart = dayStart - TimeUnit.HOURS.toMillis(12)
        val queryEnd = minOf(dayEnd, System.currentTimeMillis())

        val events = usageStatsManager.queryEvents(queryStart, queryEnd)
        val event = UsageEvents.Event()

        // package -> timestamp it was last brought to the foreground
        val foregroundSince = mutableMapOf<String, Long>()
        // package -> accumulated ms clipped to [dayStart, dayEnd)
        val accumulated = mutableMapOf<String, Long>()

        fun closeSession(pkg: String, endedAt: Long) {
            val startedAt = foregroundSince.remove(pkg) ?: return
            val clippedStart = maxOf(startedAt, dayStart)
            val clippedEnd = minOf(endedAt, dayEnd)
            if (clippedEnd > clippedStart) {
                accumulated[pkg] = (accumulated[pkg] ?: 0L) + (clippedEnd - clippedStart)
            }
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            // Screen-off/lock events may have a null packageName on many OEMs.
            // Handle them before the package null-check so all open sessions are
            // properly closed when the screen turns off.
            if (event.eventType == UsageEvents.Event.SCREEN_NON_INTERACTIVE) {
                foregroundSince.keys.toList().forEach { closeSession(it, event.timeStamp) }
                continue
            }

            val pkg = event.packageName ?: continue

            when (event.eventType) {
                // ACTIVITY_RESUMED/PAUSED (API 29+) are more accurate than the
                // legacy MOVE_TO_* events, but we handle both for older devices.
                UsageEvents.Event.ACTIVITY_RESUMED,
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    foregroundSince[pkg] = event.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    closeSession(pkg, event.timeStamp)
                }
            }
        }

        // Anything still open at the end of our query window (e.g. the app
        // being used right now) counts up to "now" or day end, whichever first.
        foregroundSince.keys.toList().forEach { closeSession(it, queryEnd) }

        val breakdown = mutableListOf<AppUsageRecord>()
        for ((packageName, totalTimeMs) in accumulated) {
            if (packageName in excludedPackages) continue
            if (totalTimeMs < 60_000L) continue // drop sub-minute noise

            var appName = packageName
            var shouldAdd = true
            try {
                val appInfo = packageManager.getApplicationInfo(packageName, 0)

                // Skip components with no launcher entry that are also system
                // packages - these are services, not something a person "used".
                val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val hasLauncherEntry = packageManager.getLaunchIntentForPackage(packageName) != null
                if (isSystemApp && !hasLauncherEntry) {
                    shouldAdd = false
                } else {
                    appName = packageManager.getApplicationLabel(appInfo).toString()
                }
            } catch (e: PackageManager.NameNotFoundException) {
                // Keep packageName as appName
            }

            if (shouldAdd) {
                val minutes = TimeUnit.MILLISECONDS.toMinutes(totalTimeMs)
                if (minutes > 0) {
                    breakdown.add(AppUsageRecord(appName, packageName, minutes))
                }
            }
        }

        return breakdown.sortedByDescending { it.minutes }
    }
}