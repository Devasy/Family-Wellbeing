import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyWellbeingApp());
}

class FamilyWellbeingApp extends StatelessWidget {
  const FamilyWellbeingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Wellbeing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F4F5), // Zinc light background
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF18181B),
          primary: const Color(0xFF18181B),
          secondary: const Color(0xFFD85A30), // Warm clay accent
          surface: const Color(0xFFFAFAFA),
        ),
        fontFamily: 'sans-serif',
        cardTheme: CardThemeData(
          color: const Color(0xFFFAFAFA),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
          ),
        ),
      ),
      home: const MainLayout(),
    );
  }
}

// Data models
class Member {
  final String id;
  String name;
  String deviceModel;
  final Color avatarColor;

  Member({
    required this.id,
    required this.name,
    required this.deviceModel,
    required this.avatarColor,
  });
}

class AppUsage {
  final String appName;
  final String packageName;
  final int minutes;

  AppUsage({
    required this.appName,
    required this.packageName,
    required this.minutes,
  });
}

class UsageRecord {
  final String id;
  final String memberId;
  final String date;
  final int totalScreenTimeMinutes;
  final List<AppUsage> appBreakdown;
  final bool isComplete;

  UsageRecord({
    required this.id,
    required this.memberId,
    required this.date,
    required this.totalScreenTimeMinutes,
    required this.appBreakdown,
    required this.isComplete,
  });
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  // Navigation State
  String _activeTab = 'dashboard'; // 'dashboard' | 'leaderboard' | 'settings'

  // Preferences State
  String _displayName = 'Arun (You)';
  String _memberId = '1';
  String _mongoUri = '';

  // Local Usage Stats State
  int _localTodayTotalMinutes = 0;
  List<AppUsage> _localTodayBreakdown = [];

  // Database / Sync State
  List<UsageRecord> _dbRecords = [];
  bool _isSyncing = false;
  DateTime? _lastSynced;
  bool _hasPermission = false;
  bool _usingMockFallback = true;

  // Mock database (fallback)
  late List<UsageRecord> _mockDb;
  late List<Member> _mockMembers;

  // Platform channel
  static const _platform = MethodChannel('com.family.wellbeing/stats');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMockMembers();
    _loadPreferences().then((_) {
      _mockDb = _generateMockDatabase();
      _checkStatusAndFetchData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStatusAndFetchData();
    }
  }

  void _initializeMockMembers() {
    _mockMembers = [
      Member(id: '1', name: _displayName, deviceModel: 'Pixel 8', avatarColor: const Color(0xFFD85A30)),
      Member(id: '2', name: 'Priya', deviceModel: 'Samsung S23', avatarColor: const Color(0xFF4A5568)),
      Member(id: '3', name: 'Rohan', deviceModel: 'OnePlus 11', avatarColor: const Color(0xFF2B6CB0)),
      Member(id: '4', name: 'Aarav', deviceModel: 'Pixel 7a', avatarColor: const Color(0xFF38A169)),
      Member(id: '5', name: 'Neha', deviceModel: 'Samsung A54', avatarColor: const Color(0xFFD69E2E)),
      Member(id: '6', name: 'Vikram', deviceModel: 'Nothing Phone 2', avatarColor: const Color(0xFFE53E3E)),
    ];
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _displayName = prefs.getString('displayName') ?? 'Arun (You)';
      _memberId = prefs.getString('memberId') ?? '1';
      _mongoUri = prefs.getString('mongoUri') ?? '';
      _mockMembers[0].name = _displayName;
    });
  }

  Future<void> _savePreferences(String name, String id, String uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('displayName', name);
    await prefs.setString('memberId', id);
    await prefs.setString('mongoUri', uri);

    setState(() {
      _displayName = name;
      _memberId = id;
      _mongoUri = uri;
      _mockMembers[0].name = _displayName;
    });

    try {
      await _platform.invokeMethod('saveConfig', {
        'mongoUri': uri,
        'memberId': id,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to save config to native: ${e.message}");
    }

    _checkStatusAndFetchData();
  }

  Future<void> _checkStatusAndFetchData() async {
    setState(() => _isSyncing = true);
    
    // Check permission
    bool perm = false;
    try {
      perm = await _platform.invokeMethod<bool>('checkPermission') ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to check permission: ${e.message}");
    }

    setState(() {
      _hasPermission = perm;
    });

    // Fetch local usage
    if (perm) {
      try {
        final Map<dynamic, dynamic>? usage = 
            await _platform.invokeMethod<Map<dynamic, dynamic>>('fetchLocalUsage');
        if (usage != null) {
          final breakdownRaw = usage['appBreakdown'] as List<dynamic>? ?? [];
          final breakdown = breakdownRaw.map((app) {
            return AppUsage(
              appName: app['appName'] as String? ?? 'Unknown',
              packageName: app['packageName'] as String? ?? '',
              minutes: (app['minutes'] as num? ?? 0).toInt(),
            );
          }).toList();

          setState(() {
            _localTodayTotalMinutes = (usage['totalScreenTimeMinutes'] as num? ?? 0).toInt();
            _localTodayBreakdown = breakdown;
          });
        }
      } on PlatformException catch (e) {
        debugPrint("Failed to fetch local stats: ${e.message}");
      }
    }

    // Fetch MongoDB stats
    bool dbFetchSuccess = false;
    if (_mongoUri.isNotEmpty) {
      try {
        final List<dynamic>? recordsRaw = await _platform.invokeMethod<List<dynamic>>('fetchDbData');
        if (recordsRaw != null && recordsRaw.isNotEmpty) {
          final List<UsageRecord> records = recordsRaw.map((recordMap) {
            final map = Map<String, dynamic>.from(recordMap as Map);
            final appBreakdownRaw = map['appBreakdown'] as List<dynamic>? ?? [];
            final appBreakdown = appBreakdownRaw.map((app) {
              final appMap = Map<String, dynamic>.from(app as Map);
              return AppUsage(
                appName: appMap['appName'] as String? ?? 'Unknown',
                packageName: appMap['packageName'] as String? ?? '',
                minutes: (appMap['minutes'] as num? ?? 0).toInt(),
              );
            }).toList();

            return UsageRecord(
              id: map['id'] as String? ?? '',
              memberId: map['memberId'] as String? ?? '',
              date: map['date'] as String? ?? '',
              totalScreenTimeMinutes: (map['totalScreenTimeMinutes'] as num? ?? 0).toInt(),
              appBreakdown: appBreakdown,
              isComplete: map['isComplete'] as bool? ?? false,
            );
          }).toList();

          setState(() {
            _dbRecords = records;
            _usingMockFallback = false;
          });
          dbFetchSuccess = true;
        }
      } on PlatformException catch (e) {
        debugPrint("Failed to fetch MongoDB stats: ${e.message}");
      }
    }

    if (!dbFetchSuccess) {
      setState(() {
        _usingMockFallback = true;
      });
      if (perm) {
        _updateMockDataWithLive();
      }
    }

    setState(() {
      _lastSynced = DateTime.now();
      _isSyncing = false;
    });
  }

  void _updateMockDataWithLive() {
    setState(() {
      final todayIndex = _mockDb.indexWhere(
        (r) => r.memberId == '1' && r.date == '2026-07-01'
      );
      if (todayIndex != -1) {
        _mockDb[todayIndex] = UsageRecord(
          id: '1_2026-07-01',
          memberId: '1',
          date: '2026-07-01',
          totalScreenTimeMinutes: _localTodayTotalMinutes,
          appBreakdown: _localTodayBreakdown,
          isComplete: false,
        );
      }
    });
  }

  Future<void> _requestUsagePermission() async {
    try {
      await _platform.invokeMethod('requestPermission');
    } on PlatformException catch (e) {
      debugPrint("Failed to request permission: ${e.message}");
    }
  }

  Future<void> _triggerManualSync() async {
    setState(() => _isSyncing = true);
    try {
      await _platform.invokeMethod('triggerSync');
    } on PlatformException catch (e) {
      debugPrint("Failed to trigger sync: ${e.message}");
    }
    await Future.delayed(const Duration(seconds: 2));
    await _checkStatusAndFetchData();
  }

  List<UsageRecord> _generateMockDatabase() {
    final db = <UsageRecord>[];
    final apps = ["Instagram", "WhatsApp", "YouTube", "Chrome", "Notion", "Spotify", "Maps"];
    final dates = [
      '2026-06-25', '2026-06-26', '2026-06-27', '2026-06-28', 
      '2026-06-29', '2026-06-30', '2026-07-01'
    ];

    final rand = Random(42);

    for (final member in _mockMembers) {
      for (final date in dates) {
        final isToday = date == '2026-07-01';
        
        int totalMins = isToday 
            ? rand.nextInt(120) + 20 
            : rand.nextInt(240) + 60;
            
        int remaining = totalMins;
        final breakdown = <AppUsage>[];
        final shuffledApps = List<String>.from(apps)..shuffle(rand);
        final userApps = shuffledApps.sublist(0, 3);
        
        for (int i = 0; i < userApps.length; i++) {
          final appName = userApps[i];
          if (i == userApps.length - 1) {
            breakdown.add(AppUsage(appName: appName, packageName: 'com.$appName', minutes: remaining));
          } else {
            final mins = remaining > 0 ? rand.nextInt((remaining * 0.7).toInt() + 1) : 0;
            breakdown.add(AppUsage(appName: appName, packageName: 'com.$appName', minutes: mins));
            remaining -= mins;
          }
        }
        
        breakdown.sort((a, b) => b.minutes.compareTo(a.minutes));

        db.add(UsageRecord(
          id: '${member.id}_$date',
          memberId: member.id,
          date: date,
          totalScreenTimeMinutes: totalMins,
          appBreakdown: breakdown,
          isComplete: !isToday,
        ));
      }
    }
    return db;
  }

  List<Member> _getMembersList(List<UsageRecord> db) {
    if (_usingMockFallback) {
      return _mockMembers;
    }

    // Dynamically resolve unique member records from synced MongoDB Atlas docs
    final uniqueIds = db.map((r) => r.memberId).toSet();
    uniqueIds.add(_memberId); // Ensure current user is present

    final List<Member> dynamicMembers = [];
    final avatarColors = [
      const Color(0xFFD85A30), // Warm clay
      const Color(0xFF4A5568), // Slate
      const Color(0xFF2B6CB0), // Blue
      const Color(0xFF38A169), // Green
      const Color(0xFFD69E2E), // Yellow
      const Color(0xFFE53E3E), // Red
      const Color(0xFF805AD5), // Purple
      const Color(0xFF319795), // Teal
    ];

    for (final id in uniqueIds) {
      if (id == _memberId) {
        dynamicMembers.add(Member(
          id: id,
          name: _displayName,
          deviceModel: 'Pixel 8 (This Device)',
          avatarColor: const Color(0xFFD85A30),
        ));
      } else {
        // Generate consistent avatar color based on hash of member ID
        final colorIndex = id.hashCode.abs() % avatarColors.length;
        dynamicMembers.add(Member(
          id: id,
          name: id, // display ID as name
          deviceModel: 'Family Member',
          avatarColor: avatarColors[colorIndex],
        ));
      }
    }
    return dynamicMembers;
  }

  String _formatDuration(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final List<UsageRecord> currentDb = _usingMockFallback ? _mockDb : _dbRecords;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: _buildHeader(),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: _buildActiveTabContent(currentDb),
              ),
            ),
          ),
          if (_activeTab != 'settings') _buildSyncIndicator(),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE4E4E7), width: 1),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.show_chart,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Wellbeing',
                    style: TextStyle(
                      color: Color(0xFF18181B),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _activeTab = _activeTab == 'settings' ? 'dashboard' : 'settings';
                  });
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _activeTab == 'settings' ? const Color(0xFF18181B) : Colors.white,
                    border: Border.all(
                      color: _activeTab == 'settings' ? const Color(0xFF18181B) : const Color(0xFFE4E4E7),
                    ),
                  ),
                  child: Icon(
                    _activeTab == 'settings' ? Icons.keyboard_arrow_down : Icons.person_outline,
                    color: _activeTab == 'settings' ? Colors.white : const Color(0xFF71717A),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(List<UsageRecord> currentDb) {
    switch (_activeTab) {
      case 'dashboard':
        return _buildDashboardView();
      case 'leaderboard':
        return LeaderboardView(
          db: currentDb,
          members: _getMembersList(currentDb),
          myId: _memberId,
          hasPermission: _hasPermission,
          usingMockFallback: _usingMockFallback,
          formatDuration: _formatDuration,
        );
      case 'settings':
        return SettingsView(
          displayName: _displayName,
          memberId: _memberId,
          mongoUri: _mongoUri,
          hasPermission: _hasPermission,
          isSyncing: _isSyncing,
          onRequestPermission: _requestUsagePermission,
          onSaveConfig: _savePreferences,
          onManualSync: _triggerManualSync,
          onClose: () => setState(() => _activeTab = 'dashboard'),
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildDashboardView() {
    if (!_hasPermission) {
      return _buildPermissionRequiredCard();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Overview',
              style: TextStyle(
                fontSize: 26,
                color: Color(0xFF18181B),
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Your real screen time today.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF71717A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        Card(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                const Text(
                  'TODAY (LIVE)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF71717A),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDuration(_localTodayTotalMinutes),
                  style: const TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                    letterSpacing: -1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        
        const Text(
          'App Breakdown',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF18181B),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _localTodayBreakdown.isEmpty ? 1 : _localTodayBreakdown.length,
              separatorBuilder: (context, index) => Container(
                height: 1,
                color: const Color(0xFFE5E7EB),
              ),
              itemBuilder: (context, index) {
                if (_localTodayBreakdown.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
                    child: Center(
                      child: Text(
                        'No app usage detected yet today. Try using some apps!',
                        style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final app = _localTodayBreakdown[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          app.appName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF18181B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatDuration(app.minutes),
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF18181B),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionRequiredCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 26,
            color: Color(0xFF18181B),
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline,
                  color: Color(0xFFD85A30),
                  size: 32,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Permission Required',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To display actual screen time data and your daily apps usage, this app requires standard Android Usage Stats permission.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF71717A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _requestUsagePermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF18181B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Grant Usage Access',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncIndicator() {
    final syncedString = _lastSynced != null 
        ? '${_lastSynced!.hour.toString().padLeft(2, '0')}:${_lastSynced!.minute.toString().padLeft(2, '0')}'
        : '';
        
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFF3F4F6), width: 1),
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSyncing)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFF71717A),
                  ),
                )
              else
                const Icon(
                  Icons.check,
                  size: 10,
                  color: Color(0xFF10B981),
                ),
              const SizedBox(width: 6),
              Text(
                _isSyncing ? 'Syncing...' : 'Synced $syncedString',
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Color(0xFF71717A),
                ),
              ),
              if (_usingMockFallback) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Text(
                    'DEMO',
                    style: TextStyle(fontSize: 8, color: Color(0xFFB45309), fontWeight: FontWeight.bold),
                  ),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE4E4E7), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = 'dashboard'),
              child: Container(
                color: Colors.transparent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.show_chart,
                      color: _activeTab == 'dashboard' ? const Color(0xFF18181B) : const Color(0xFF71717A).withOpacity(0.5),
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Overview',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _activeTab == 'dashboard' ? const Color(0xFF18181B) : const Color(0xFF71717A).withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: const Color(0xFFE4E4E7),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = 'leaderboard'),
              child: Container(
                color: Colors.transparent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bar_chart,
                      color: _activeTab == 'leaderboard' ? const Color(0xFF18181B) : const Color(0xFF71717A).withOpacity(0.5),
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ranks',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _activeTab == 'leaderboard' ? const Color(0xFF18181B) : const Color(0xFF71717A).withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Leaderboard Section
class LeaderboardView extends StatefulWidget {
  final List<UsageRecord> db;
  final List<Member> members;
  final String myId;
  final bool hasPermission;
  final bool usingMockFallback;
  final String Function(int) formatDuration;

  const LeaderboardView({
    super.key,
    required this.db,
    required this.members,
    required this.myId,
    required this.hasPermission,
    required this.usingMockFallback,
    required this.formatDuration,
  });

  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> {
  String _timeframe = 'today';
  String? _expandedUserId;

  @override
  Widget build(BuildContext context) {
    // Process records
    final List<Map<String, dynamic>> rankedData = widget.members.map((member) {
      int totalMinutes = 0;
      final Map<String, int> combinedBreakdown = {};
      bool isRequiredPermissionMissing = false;

      if (member.id == widget.myId && !widget.hasPermission) {
        isRequiredPermissionMissing = true;
      } else {
        if (_timeframe == 'today') {
          final record = widget.db.firstWhere(
            (r) => r.memberId == member.id && r.date == '2026-07-01',
            orElse: () => UsageRecord(id: '', memberId: member.id, date: '2026-07-01', totalScreenTimeMinutes: 0, appBreakdown: [], isComplete: false),
          );
          totalMinutes = record.totalScreenTimeMinutes;
          for (var app in record.appBreakdown) {
            combinedBreakdown[app.appName] = (combinedBreakdown[app.appName] ?? 0) + app.minutes;
          }
        } else {
          final dates = ['2026-06-25', '2026-06-26', '2026-06-27', '2026-06-28', '2026-06-29', '2026-06-30', '2026-07-01'];
          for (final date in dates) {
            final record = widget.db.firstWhere(
              (r) => r.memberId == member.id && r.date == date,
              orElse: () => UsageRecord(id: '', memberId: member.id, date: date, totalScreenTimeMinutes: 0, appBreakdown: [], isComplete: false),
          );
            totalMinutes += record.totalScreenTimeMinutes;
            for (var app in record.appBreakdown) {
              combinedBreakdown[app.appName] = (combinedBreakdown[app.appName] ?? 0) + app.minutes;
            }
          }
        }
      }

      final sortedBreakdown = combinedBreakdown.entries
          .map((e) => AppUsage(appName: e.key, packageName: '', minutes: e.value))
          .toList()
        ..sort((a, b) => b.minutes.compareTo(a.minutes));

      return {
        'member': member,
        'minutes': totalMinutes,
        'breakdown': sortedBreakdown,
        'missingPermission': isRequiredPermissionMissing,
      };
    }).toList();

    // Sort ascending (lowest screen time wins). If permission missing, rank at the bottom.
    rankedData.sort((a, b) {
      if (a['missingPermission'] as bool) return 1;
      if (b['missingPermission'] as bool) return -1;
      return (a['minutes'] as int).compareTo(b['minutes'] as int);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Leaderboard',
                  style: TextStyle(
                    fontSize: 26,
                    color: Color(0xFF18181B),
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.usingMockFallback ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: widget.usingMockFallback ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    widget.usingMockFallback ? 'DEMO DATA' : 'ATLAS SYNCED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: widget.usingMockFallback ? const Color(0xFFB45309) : const Color(0xFF065F46),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.usingMockFallback 
                  ? 'Showing simulated family screen time.' 
                  : 'Real live family stats synced from Atlas.',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF71717A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Segmented Control
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE4E4E7), width: 1),
            ),
          ),
          child: Row(
            children: [
              _buildSegmentTab('Today', 'today'),
              const SizedBox(width: 16),
              _buildSegmentTab('This Week', 'weekly'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Leaderboard List
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rankedData.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = rankedData[index];
            final Member member = data['member'] as Member;
            final int minutes = data['minutes'] as int;
            final List<AppUsage> breakdown = data['breakdown'] as List<AppUsage>;
            final bool missingPermission = data['missingPermission'] as bool;

            final bool isWinner = index == 0 && !missingPermission;
            final bool isMe = member.id == widget.myId;
            final bool isExpanded = _expandedUserId == member.id;

            final double maxMinutes = _timeframe == 'today' ? 400.0 : 2800.0;
            final double percentage = missingPermission ? 0.0 : min((minutes / maxMinutes), 1.0);

            return Column(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _expandedUserId = isExpanded ? null : member.id;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isExpanded ? 0 : 16),
                        bottomRight: Radius.circular(isExpanded ? 0 : 16),
                      ),
                      border: Border.all(
                        color: isMe ? const Color(0xFF18181B) : const Color(0xFFE4E4E7),
                        width: isMe ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Rank Index
                        SizedBox(
                          width: 22,
                          child: Text(
                            missingPermission ? '-' : '${index + 1}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Avatar
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: member.avatarColor,
                          ),
                          child: Center(
                            child: Text(
                              member.name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Info Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        member.name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                                          color: const Color(0xFF18181B),
                                        ),
                                      ),
                                      if (isWinner) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFDF2F0),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFF4E1DB)),
                                          ),
                                          child: const Text(
                                            'LEADER',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFD85A30),
                                            ),
                                          ),
                                        ),
                                      ]
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      if (missingPermission)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFFEE2E2)),
                                          ),
                                          child: const Text(
                                            'LOCK',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFEF4444),
                                            ),
                                          ),
                                        )
                                      else
                                        Text(
                                          widget.formatDuration(minutes),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontFamily: 'monospace',
                                            fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                                            color: isMe ? const Color(0xFF18181B) : const Color(0xFF52525B),
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                        color: const Color(0xFFA1A1AA),
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Custom Progress Bar
                              Container(
                                height: 4,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE4E4E7),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: percentage,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isWinner 
                                            ? const Color(0xFFD85A30) 
                                            : (isMe ? const Color(0xFF18181B) : const Color(0xFFD4D4D8)),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border(
                        left: BorderSide(color: isMe ? const Color(0xFF18181B) : const Color(0xFFE4E4E7), width: isMe ? 1.5 : 1.0),
                        right: BorderSide(color: isMe ? const Color(0xFF18181B) : const Color(0xFFE4E4E7), width: isMe ? 1.5 : 1.0),
                        bottom: BorderSide(color: isMe ? const Color(0xFF18181B) : const Color(0xFFE4E4E7), width: isMe ? 1.5 : 1.0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'APP BREAKDOWN',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF71717A),
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (missingPermission)
                          const Text(
                            'Please grant Usage Access permission to view details.',
                            style: TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontStyle: FontStyle.italic),
                          )
                        else if (breakdown.isEmpty)
                          const Text(
                            'No usage data recorded.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF71717A), fontStyle: FontStyle.italic),
                          )
                        else
                          ...breakdown.take(4).map((app) => Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      app.appName,
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF52525B)),
                                    ),
                                    Text(
                                      widget.formatDuration(app.minutes),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF71717A),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSegmentTab(String title, String tab) {
    final bool isActive = _timeframe == tab;
    return GestureDetector(
      onTap: () => setState(() => _timeframe = tab),
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF18181B) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isActive ? const Color(0xFF18181B) : const Color(0xFF71717A),
          ),
        ),
      ),
    );
  }
}

// Settings Section
class SettingsView extends StatefulWidget {
  final String displayName;
  final String memberId;
  final String mongoUri;
  final bool hasPermission;
  final bool isSyncing;
  final VoidCallback onRequestPermission;
  final Function(String, String, String) onSaveConfig;
  final VoidCallback onManualSync;
  final VoidCallback onClose;

  const SettingsView({
    super.key,
    required this.displayName,
    required this.memberId,
    required this.mongoUri,
    required this.hasPermission,
    required this.isSyncing,
    required this.onRequestPermission,
    required this.onSaveConfig,
    required this.onManualSync,
    required this.onClose,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _nameController;
  late TextEditingController _memberIdController;
  late TextEditingController _mongoUriController;
  bool _obscureUri = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _memberIdController = TextEditingController(text: widget.memberId);
    _mongoUriController = TextEditingController(text: widget.mongoUri);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberIdController.dispose();
    _mongoUriController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.arrow_back, color: Color(0xFF18181B), size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 22,
                color: Color(0xFF18181B),
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Section: My Profile
        _buildSectionHeader('MY PROFILE'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Display Name',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF52525B)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  decoration: _buildInputDecoration('Enter your display name'),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF18181B)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Member ID',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF52525B)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _memberIdController,
                  decoration: _buildInputDecoration('Enter family member ID (e.g. 1)'),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF18181B)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Section: Database Configuration
        _buildSectionHeader('DATABASE CONNECTION'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MongoDB Atlas Connection URI',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF52525B)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _mongoUriController,
                  obscureText: _obscureUri,
                  decoration: _buildInputDecoration('mongodb+srv://...').copyWith(
                    suffixIcon: GestureDetector(
                      onTap: () => setState(() => _obscureUri = !_obscureUri),
                      child: Icon(
                        _obscureUri ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: const Color(0xFF71717A),
                        size: 18,
                      ),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF18181B)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: const [
                    Icon(Icons.shield_outlined, size: 13, color: Color(0xFF71717A)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Stored in Android EncryptedSharedPreferences.',
                        style: TextStyle(fontSize: 10, color: Color(0xFF71717A)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Section: Permissions
        _buildSectionHeader('PERMISSIONS'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'PACKAGE_USAGE_STATS',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF18181B)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Required to read screen time via UsageStatsManager.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF71717A)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.hasPermission)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Text(
                      'GRANTED',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: widget.onRequestPermission,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'GRANT',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  widget.onSaveConfig(
                    _nameController.text.trim(),
                    _memberIdController.text.trim(),
                    _mongoUriController.text.trim(),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Settings saved successfully!'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Save Changes',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.hasPermission && widget.mongoUri.isNotEmpty) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: widget.onManualSync,
                child: Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
                  ),
                  child: Center(
                    child: widget.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF18181B),
                            ),
                          )
                        : const Icon(Icons.refresh, color: Color(0xFF18181B), size: 20),
                  ),
                ),
              ),
            ]
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Color(0xFF71717A),
        letterSpacing: 1.0,
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF71717A), width: 1),
      ),
    );
  }
}
