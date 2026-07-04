import 'package:mongo_dart/mongo_dart.dart';
import 'main.dart'; // To reference UsageRecord and AppUsage

class MongoDbService {
  MongoDbService._();
  static final MongoDbService instance = MongoDbService._();

  /// Forces the database name to 'wellbeing' if not explicitly defined in the URI path
  String _getFormattedUri(String uri) {
    if (uri.isEmpty) return uri;
    try {
      final parsed = Uri.parse(uri);
      // If path is empty, "/", or just query params, replace with "/wellbeing"
      if (parsed.path.isEmpty || parsed.path == '/') {
        return parsed.replace(path: '/wellbeing').toString();
      }
      return uri;
    } catch (_) {
      return uri;
    }
  }

  /// Test connection and return a diagnostic report
  Future<String> testConnection(String rawUri) async {
    final uri = _getFormattedUri(rawUri);
    final steps = <String>[];
    steps.add("[1] URI type: ${uri.startsWith('mongodb+srv://') ? 'mongodb+srv://' : 'standard mongodb://'}");
    steps.add("[2] Target database: wellbeing");
    steps.add("[3] Initializing mongo_dart client...");

    Db? db;
    try {
      db = await Db.create(uri);
      steps.add("[4] Awaiting connection open (TLS enabled natively)...");
      await db.open();
      
      steps.add("[5] Connection successfully established!");
      
      final collection = db.collection('daily_usage');
      final count = await collection.count();
      steps.add("[6] Collection 'wellbeing.daily_usage': $count document(s) found.");
      
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
  Future<List<UsageRecord>> fetchAllUsageRecords(String rawUri) async {
    final uri = _getFormattedUri(rawUri);
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
  Future<bool> upsertUsageRecord(String rawUri, UsageRecord record) async {
    final uri = _getFormattedUri(rawUri);
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
