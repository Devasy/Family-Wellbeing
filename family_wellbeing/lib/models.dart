/// Shared data models used across the app, mongo_service, and chart widgets.
library;

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
  final String memberName;
  final String deviceModel;
  final String date;
  final int totalScreenTimeMinutes;
  final List<AppUsage> appBreakdown;
  final bool isComplete;

  UsageRecord({
    required this.id,
    required this.memberId,
    this.memberName = '',
    this.deviceModel = '',
    required this.date,
    required this.totalScreenTimeMinutes,
    required this.appBreakdown,
    required this.isComplete,
  });
}
