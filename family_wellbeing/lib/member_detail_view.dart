import 'dart:math';
import 'package:flutter/material.dart';
import 'usage_ring_chart.dart';
import 'screen_time_bar_chart.dart';
import 'sliding_segment_control.dart';
import 'models.dart'; // AppUsage, UsageRecord
import 'main.dart' show Member; // Member lives in main.dart

class MemberDetailView extends StatefulWidget {
  const MemberDetailView({
    super.key,
    required this.member,
    required this.db,
    required this.formatDuration,
    this.initialTimeframe = 'today',
  });

  final Member member;
  final List<UsageRecord> db;
  final String Function(int) formatDuration;
  final String initialTimeframe;

  @override
  State<MemberDetailView> createState() => _MemberDetailViewState();
}

class _MemberDetailViewState extends State<MemberDetailView> {
  late String _timeframe; // 'today' (Day) or 'weekly' (Week)
  int _dayOffset = 0;     // 0 = today, 1 = yesterday, etc.
  int _weekOffset = 0;    // 0 = this week, 1 = last week, etc.

  // Caching keys
  String? _lastTimeframe;
  int? _lastDayOffset;
  int? _lastWeekOffset;
  List<UsageRecord>? _lastDb;
  bool? _lastIsDark;

  // Cached results
  late int _activeMinutes;
  late List<AppUsage> _activeApps;
  late List<BarChartDayData> _barChartData;
  late String _comparisonText;
  late bool _missingPermission;
  late DateTime _targetDay;
  late List<DateTime> _weekDays;

  @override
  void initState() {
    super.initState();
    _timeframe = widget.initialTimeframe == 'today' ? 'today' : 'weekly';
  }

  String _getMonth(int month) {
    return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];
  }

  String _getDayOfWeek(int day) {
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1];
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today, ${dt.day} ${_getMonth(dt.month)}';
    if (diff == 1) return 'Yesterday, ${dt.day} ${_getMonth(dt.month)}';
    return '${_getDayOfWeek(dt.weekday)}, ${dt.day} ${_getMonth(dt.month)}';
  }

  String _formatWeekRange(List<DateTime> days) {
    if (days.isEmpty) return 'Selected Week';
    final start = days.first;
    final end = days.last;
    return '${start.day} ${_getMonth(start.month)} - ${end.day} ${_getMonth(end.month)}';
  }

  List<DateTime> _getWeekDays(int offset) {
    final List<DateTime> list = [];
    final now = DateTime.now();
    final anchor = now.subtract(Duration(days: offset * 7));
    for (int i = 6; i >= 0; i--) {
      list.add(anchor.subtract(Duration(days: i)));
    }
    return list;
  }

  String _yyyymmdd(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  void _ensureDataCalculated(bool isDark) {
    if (_lastTimeframe == _timeframe &&
        _lastDayOffset == _dayOffset &&
        _lastWeekOffset == _weekOffset &&
        _lastDb == widget.db &&
        _lastIsDark == isDark) {
      return;
    }

    _lastTimeframe = _timeframe;
    _lastDayOffset = _dayOffset;
    _lastWeekOffset = _weekOffset;
    _lastDb = widget.db;
    _lastIsDark = isDark;

    _targetDay = DateTime.now().subtract(Duration(days: _dayOffset));
    _weekDays = _getWeekDays(_weekOffset);

    final memberRecords = widget.db.where((r) => r.memberId == widget.member.id).toList();
    _missingPermission = memberRecords.isEmpty;

    if (_missingPermission) {
      _activeMinutes = 0;
      _activeApps = [];
      _barChartData = [];
      _comparisonText = 'No last week data';
      return;
    }

    if (_timeframe == 'today') {
      final String targetDayStr = _yyyymmdd(_targetDay);
      final dayRecord = memberRecords.firstWhere(
        (r) => r.date == targetDayStr,
        orElse: () => UsageRecord(
          id: '',
          memberId: widget.member.id,
          date: targetDayStr,
          totalScreenTimeMinutes: 0,
          appBreakdown: [],
          isComplete: false,
        ),
      );

      _activeMinutes = dayRecord.totalScreenTimeMinutes;
      _activeApps = dayRecord.appBreakdown;
      _barChartData = [];
      _comparisonText = '';
    } else {
      final Set<String> weekDaysStr = _weekDays.map((d) => _yyyymmdd(d)).toSet();
      final weeklyRecords = memberRecords.where((r) => weekDaysStr.contains(r.date)).toList();
      final int weeklyTotalMinutes = weeklyRecords.fold<int>(0, (sum, r) => sum + r.totalScreenTimeMinutes);

      _activeMinutes = weeklyTotalMinutes;

      final Map<String, AppUsage> mergedApps = {};
      for (final record in weeklyRecords) {
        for (final app in record.appBreakdown) {
          if (mergedApps.containsKey(app.packageName)) {
            final existing = mergedApps[app.packageName]!;
            mergedApps[app.packageName] = AppUsage(
              appName: app.appName,
              packageName: app.packageName,
              minutes: existing.minutes + app.minutes,
            );
          } else {
            mergedApps[app.packageName] = app;
          }
        }
      }
      final List<AppUsage> weeklyBreakdown = mergedApps.values.toList();

      final List<DateTime> prevWeekDays = _getWeekDays(_weekOffset + 1);
      final Set<String> prevWeekDaysStr = prevWeekDays.map((d) => _yyyymmdd(d)).toSet();
      final prevWeeklyRecords = memberRecords.where((r) => prevWeekDaysStr.contains(r.date)).toList();
      final int prevWeeklyTotalMinutes = prevWeeklyRecords.fold<int>(0, (sum, r) => sum + r.totalScreenTimeMinutes);

      _comparisonText = 'No last week data';
      if (prevWeeklyTotalMinutes > 0) {
        final double diff = (weeklyTotalMinutes - prevWeeklyTotalMinutes).toDouble();
        final double pct = (diff / prevWeeklyTotalMinutes) * 100;
        final int roundedPct = pct.round();
        if (roundedPct > 0) {
          _comparisonText = '$roundedPct% ↑ vs last week';
        } else if (roundedPct < 0) {
          _comparisonText = '${roundedPct.abs()}% ↓ vs last week';
        } else {
          _comparisonText = 'Flat vs last week';
        }
      }

      _barChartData = [];
      for (final day in _weekDays) {
        final dayStr = _yyyymmdd(day);
        final r = weeklyRecords.firstWhere(
          (rec) => rec.date == dayStr,
          orElse: () => UsageRecord(
            id: '',
            memberId: widget.member.id,
            date: dayStr,
            totalScreenTimeMinutes: 0,
            appBreakdown: [],
            isComplete: false,
          ),
        );

        final sortedApps = [...r.appBreakdown]..sort((a, b) => b.minutes.compareTo(a.minutes));
        final topApps = sortedApps.take(4).toList();
        final otherMins = sortedApps.skip(4).fold<int>(0, (sum, a) => sum + a.minutes);

        final segments = <BarChartSegment>[
          for (int k = 0; k < topApps.length; k++)
            BarChartSegment(
              name: topApps[k].appName,
              minutes: topApps[k].minutes,
              color: kUsagePalette[k % kUsagePalette.length],
            ),
        ];
        if (otherMins > 0) {
          segments.add(BarChartSegment(
            name: 'Other',
            minutes: otherMins,
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8),
          ));
        }

        _barChartData.add(BarChartDayData(
          label: _getDayOfWeek(day.weekday).substring(0, 3),
          totalMinutes: r.totalScreenTimeMinutes,
          segments: segments,
        ));
      }
    }

    _activeApps = _activeApps.where((app) => app.minutes > 0).toList()
      ..sort((a, b) => b.minutes.compareTo(a.minutes));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Trigger memoized calculations before building layout
    _ensureDataCalculated(isDark);

    final bool missingPermission = _missingPermission;
    final int activeMinutes = _activeMinutes;
    final List<AppUsage> activeApps = _activeApps;
    final List<BarChartDayData> barChartData = _barChartData;
    final String comparisonText = _comparisonText;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: theme.colorScheme.onSurface, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Member Profile',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.dividerColor, width: 1),
                ),
                child: Column(
                  children: [
                    Hero(
                      tag: 'lb_avatar_${widget.member.id}',
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: widget.member.avatarColor,
                        child: Text(
                          widget.member.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Hero(
                      tag: 'lb_name_${widget.member.id}',
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          widget.member.name,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.member.deviceModel,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Timeframe Segment Selector - sliding rounded switcher
                    SlidingSegmentControl(
                      selectedValue: _timeframe,
                      values: const ['today', 'weekly'],
                      labels: const ['Day', 'Week'],
                      onValueChanged: (val) => setState(() => _timeframe = val),
                    ),
                    const SizedBox(height: 16),

                    // Navigation Selector Bar - fully rounded capsule calendar switcher
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF18181B) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(30), // Consistent rounded design
                        border: Border.all(color: theme.dividerColor, width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                            onPressed: () {
                              setState(() {
                                if (_timeframe == 'today') {
                                  _dayOffset++;
                                } else {
                                  _weekOffset++;
                                }
                              });
                            },
                          ),
                          Text(
                            _timeframe == 'today'
                                ? _formatDate(_targetDay)
                                : _formatWeekRange(_weekDays),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                            onPressed: (_timeframe == 'today' && _dayOffset == 0) ||
                                    (_timeframe == 'weekly' && _weekOffset == 0)
                                ? null
                                : () {
                                    setState(() {
                                      if (_timeframe == 'today') {
                                        _dayOffset = max(0, _dayOffset - 1);
                                      } else {
                                        _weekOffset = max(0, _weekOffset - 1);
                                      }
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Combined duration summary pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 16,
                            color: theme.colorScheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _timeframe == 'today' ? 'Usage Total: ' : 'Weekly Total: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            widget.formatDuration(activeMinutes),
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Visual Chart Section
              if (!missingPermission) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _timeframe == 'today' ? 'USAGE DISTRIBUTION' : 'WEEKLY TIMELINE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: theme.dividerColor, width: 1),
                  ),
                  child: _timeframe == 'today'
                      ? ScreenTimeRingChart(
                          totalMinutes: activeMinutes,
                          breakdown: activeApps,
                          compact: false,
                          ringSize: 130,
                          strokeWidth: 16,
                          maxLegendItems: 5,
                          centerLabel: 'TODAY',
                          formatDuration: widget.formatDuration,
                        )
                      : ScreenTimeBarChart(
                          dayData: barChartData,
                          formatDuration: widget.formatDuration,
                          comparisonText: comparisonText,
                          height: 180,
                        ),
                ),
                const SizedBox(height: 24),
              ],

              // App Breakdown List
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DETAILED APP USAGE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.dividerColor, width: 1),
                ),
                child: missingPermission
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(Icons.lock_outline, size: 28, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              'Permissions Restricted',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'This user has not enabled usage tracking permissions.',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : activeApps.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No screen time recorded for this period.',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activeApps.length,
                            separatorBuilder: (context, index) =>
                                Divider(color: theme.dividerColor, height: 1),
                            itemBuilder: (context, index) {
                              final app = activeApps[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          app.appName.isNotEmpty
                                              ? app.appName.substring(0, 1).toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            app.appName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            app.packageName,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      widget.formatDuration(app.minutes),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
