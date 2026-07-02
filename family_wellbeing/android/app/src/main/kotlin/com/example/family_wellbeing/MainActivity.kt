package com.example.family_wellbeing

import android.content.Intent
import android.provider.Settings
import androidx.annotation.NonNull
import com.example.family_wellbeing.core.UsageStatsExtractor
import com.example.family_wellbeing.core.WorkManagerHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.family.wellbeing/stats"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    val extractor = UsageStatsExtractor(this)
                    result.success(extractor.hasUsageStatsPermission())
                }
                "requestPermission" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "triggerSync" -> {
                    WorkManagerHelper.triggerImmediateSync(this)
                    result.success(true)
                }
                "scheduleDailySync" -> {
                    WorkManagerHelper.scheduleDailySync(this)
                    result.success(true)
                }
                "saveSettingsToNative" -> {
                    val mongoUri = call.argument<String>("MONGO_URI")
                    val memberId = call.argument<String>("MEMBER_ID")
                    val sharedPrefs = getSharedPreferences("WellbeingPrefs", android.content.Context.MODE_PRIVATE)
                    with(sharedPrefs.edit()) {
                        putString("MONGO_URI", mongoUri)
                        putString("MEMBER_ID", memberId)
                        apply()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
