package com.family.family_wellbeing

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.family.wellbeing/stats"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val extractor = UsageStatsExtractor(this)
            
            when (call.method) {
                "checkPermission" -> {
                    result.success(extractor.hasUsageStatsPermission())
                }
                "requestPermission" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "fetchLocalUsage" -> {
                    try {
                        val dateStr = call.argument<String>("date")
                        val queryDate = if (!dateStr.isNullOrEmpty()) {
                            LocalDate.parse(dateStr)
                        } else {
                            LocalDate.now()
                        }
                        
                        val stats = extractor.getUsageForDate(queryDate)
                        val total = stats.sumOf { it.minutes }
                        
                        val breakdownList = stats.map { app ->
                            mapOf(
                                "appName" to app.appName,
                                "packageName" to app.packageName,
                                "minutes" to app.minutes
                            )
                        }
                        
                        val resultMap = mapOf(
                            "totalScreenTimeMinutes" to total,
                            "appBreakdown" to breakdownList
                        )
                        result.success(resultMap)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to fetch local stats: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
