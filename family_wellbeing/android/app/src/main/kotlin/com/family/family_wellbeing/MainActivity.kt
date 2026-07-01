package com.family.family_wellbeing

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.bson.Document
import java.time.LocalDate

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.family.wellbeing/stats"
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Schedule daily background sync on app start
        WorkManagerHelper.scheduleDailySync(this)

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
                "saveConfig" -> {
                    val mongoUri = call.argument<String>("mongoUri")
                    val memberId = call.argument<String>("memberId")
                    
                    val sharedPrefs = getSharedPreferences("WellbeingPrefs", Context.MODE_PRIVATE)
                    sharedPrefs.edit()
                        .putString("MONGO_URI", mongoUri)
                        .putString("MEMBER_ID", memberId)
                        .apply()
                        
                    result.success(true)
                }
                "triggerSync" -> {
                    WorkManagerHelper.triggerImmediateSync(this)
                    result.success(true)
                }
                "fetchLocalUsage" -> {
                    try {
                        val today = LocalDate.now()
                        val stats = extractor.getUsageForDate(today)
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
                "fetchDbData" -> {
                    val sharedPrefs = getSharedPreferences("WellbeingPrefs", Context.MODE_PRIVATE)
                    val mongoUri = sharedPrefs.getString("MONGO_URI", null)
                    
                    if (mongoUri.isNullOrEmpty()) {
                        result.success(emptyList<Map<String, Any>>())
                        return@setMethodCallHandler
                    }
                    
                    scope.launch {
                        try {
                            val mongoService = MongoDbSyncService(mongoUri)
                            val documents = mongoService.fetchAllUsageRecords()
                            
                            val recordsList = documents.map { doc ->
                                val appBreakdownDocs = doc.get("appBreakdown") as? List<Document> ?: emptyList()
                                val appBreakdownList = appBreakdownDocs.map { appDoc ->
                                    mapOf(
                                        "appName" to (appDoc.getString("appName") ?: ""),
                                        "packageName" to (appDoc.getString("packageName") ?: ""),
                                        "minutes" to (appDoc.getLong("minutes") ?: 0L)
                                    )
                                }
                                
                                mapOf(
                                    "id" to (doc.getString("_id") ?: ""),
                                    "memberId" to (doc.getString("memberId") ?: ""),
                                    "date" to (doc.getString("date") ?: ""),
                                    "totalScreenTimeMinutes" to (doc.getLong("totalScreenTimeMinutes") ?: 0L),
                                    "appBreakdown" to appBreakdownList,
                                    "isComplete" to (doc.getBoolean("isComplete") ?: false),
                                    "syncedAt" to (doc.getLong("syncedAt") ?: 0L)
                                )
                            }
                            mongoService.close()
                            result.success(recordsList)
                        } catch (e: Exception) {
                            result.error("MONGO_ERROR", "Failed to query MongoDb: ${e.message}", null)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
