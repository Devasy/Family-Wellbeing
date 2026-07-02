import 'package:mongo_dart/mongo_dart.dart';
import 'main.dart'; // To reference UsageRecord and AppUsage

class MongoDbService {
  MongoDbService._();
  static final MongoDbService instance = MongoDbService._();

  /// Test connection and return a diagnostic report
  Future<String> testConnection(String uri) async {
    final steps = <String>[];
    steps.add("[1] URI type: ${uri.startsWith('mongodb+srv://') ? 'mongodb+srv://' : 'standard mongodb://'}");
    steps.add("[2] Initializing mongo_dart client...");

    Db? db;
    try {
      db = await Db.create(uri);
      steps.add("[3] Awaiting connection open (TLS enabled natively)...");
      await db.open();
      
      steps.add("[4] Connection successfully established!");
      
      final collection = db.collection('daily_usage');
      final count = await collection.count();
      steps.add("[5] Collection 'wellbeing.daily_usage': $count document(s) found.");
      
      return "OK|${steps.join('\n')}";
    } catch (e) {
      steps.add("EXCEPTION: ${e.runtimeType}: $e");
      return "ERROR|${steps.join('\n')}";
    } finally {
      if (db != null) {
        try {
          await db.close();
        } catch (_) {}
      }
    }
  }

  /// Fetch all usage records
  Future<List<UsageRecord>> fetchAllUsageRecords(String uri) async {
    if (uri.isEmpty) return [];
    
    Db? db;
    try {
      db = await Db.create(uri);
      await db.open();
      
      final collection = db.collection('daily_usage');
      final List<Map<String, dynamic>> docs = await collection.find().toList();
      
      final List<UsageRecord> records = [];
      for (final doc in docs) {
        final appBreakdownRaw = doc['appBreakdown'] as List<dynamic>? ?? [];
        final appBreakdown = appBreakdownRaw.map((app) {
          final appMap = Map<String, dynamic>.from(app as Map);
          return AppUsage(
            appName: appMap['appName'] as String? ?? 'Unknown',
            packageName: appMap['packageName'] as String? ?? '',
            minutes: (appMap['minutes'] as num? ?? 0).toInt(),
          );
        }).toList();

        records.add(UsageRecord(
          id: doc['_id'] as String? ?? '',
          memberId: doc['memberId'] as String? ?? '',
          date: doc['date'] as String? ?? '',
          totalScreenTimeMinutes: (doc['totalScreenTimeMinutes'] as num? ?? 0).toInt(),
          appBreakdown: appBreakdown,
          isComplete: doc['isComplete'] as bool? ?? false,
        ));
      }
      return records;
    } finally {
      if (db != null) {
        try {
          await db.close();
        } catch (_) {}
      }
    }
  }

  /// Upsert a single usage record
  Future<bool> upsertUsageRecord(String uri, UsageRecord record) async {
    if (uri.isEmpty) return false;
    
    Db? db;
    try {
      db = await Db.create(uri);
      await db.open();
      
      final collection = db.collection('daily_usage');
      
      final doc = {
        '_id': record.id,
        'memberId': record.memberId,
        'date': record.date,
        'totalScreenTimeMinutes': record.totalScreenTimeMinutes,
        'isComplete': record.isComplete,
        'syncedAt': DateTime.now().millisecondsSinceEpoch,
        'appBreakdown': record.appBreakdown.map((app) => {
          'appName': app.appName,
          'packageName': app.packageName,
          'minutes': app.minutes,
        }).toList(),
      };

      await collection.update(
        where.eq('_id', record.id),
        doc,
        upsert: true,
      );
      return true;
    } catch (e) {
      print("Upsert record failed: $e");
      return false;
    } finally {
      if (db != null) {
        try {
          await db.close();
        } catch (_) {}
      }
    }
  }
}
