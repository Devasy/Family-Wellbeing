package com.family.family_wellbeing

import android.util.Log
import com.mongodb.client.model.Filters
import com.mongodb.client.model.UpdateOptions
import com.mongodb.kotlin.client.coroutine.MongoClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.withContext
import org.bson.Document

data class DailyUsageDocument(
    val _id: String, // format: "memberId_YYYY-MM-DD"
    val memberId: String,
    val date: String, // format: "YYYY-MM-DD"
    val totalScreenTimeMinutes: Long,
    val appBreakdown: List<AppUsageRecord>,
    val isComplete: Boolean,
    val syncedAt: Long // Epoch timestamp
)

class MongoDbSyncService(private val connectionString: String) {

    private val client = MongoClient.create(connectionString)
    private val database = client.getDatabase("wellbeing")
    private val collection = database.getCollection<Document>("daily_usage")

    suspend fun upsertUsageRecord(record: DailyUsageDocument): Boolean = withContext(Dispatchers.IO) {
        try {
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

    suspend fun fetchAllUsageRecords(): List<Document> = withContext(Dispatchers.IO) {
        try {
            // Find all records and return as list of Bson Documents.
            // We will convert them to maps inside the MethodChannel.
            return@withContext collection.find().toList()
        } catch (e: Exception) {
            Log.e("MongoSync", "Failed to fetch records: ${e.message}")
            return@withContext emptyList()
        }
    }

    fun close() {
        try {
            client.close()
        } catch (e: Exception) {
            Log.e("MongoSync", "Error closing MongoClient: ${e.message}")
        }
    }
}
