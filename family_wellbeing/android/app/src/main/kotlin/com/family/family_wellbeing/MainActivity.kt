package com.family.family_wellbeing

import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.family.wellbeing/stats"
    private val PREFS_NAME = "family_wellbeing_prefs"
    private val KEY_INSTALL_ID = "install_id"

    /** Returns the per-install UUID, generating and persisting it on first call. */
    private fun getInstallId(): String {
        val prefs: SharedPreferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        var id = prefs.getString(KEY_INSTALL_ID, null)
        if (id.isNullOrEmpty()) {
            id = UUID.randomUUID().toString()
            prefs.edit().putString(KEY_INSTALL_ID, id).apply()
        }
        return id
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val executor = Executors.newSingleThreadExecutor()
        val mainHandler = Handler(Looper.getMainLooper())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val extractor = UsageStatsExtractor(this)

            when (call.method) {
                "checkPermission" -> {
                    result.success(extractor.hasUsageStatsPermission())
                }
                "requestPermission" -> {
                    val intent = Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "fetchLocalUsage" -> {
                    // Run the usage query off the platform thread to avoid blocking the UI.
                    val dateStr = call.argument<String>("date")
                    executor.execute {
                        try {
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
                            mainHandler.post { result.success(resultMap) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("ERROR", "Failed to fetch local stats: ${e.message}", null)
                            }
                        }
                    }
                }
                "getDeviceMetadata" -> {
                    try {
                        val manufacturer = android.os.Build.MANUFACTURER ?: "Unknown"
                        val model = android.os.Build.MODEL ?: "Device"
                        val deviceName = if (model.startsWith(manufacturer, ignoreCase = true)) {
                            model
                        } else {
                            "${manufacturer.substring(0, 1).uppercase() + manufacturer.substring(1)} $model"
                        }

                        val resultMap = mapOf(
                            "deviceName" to deviceName,
                            "deviceId" to getInstallId()
                        )
                        result.success(resultMap)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to fetch device metadata: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}

