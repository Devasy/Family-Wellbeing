import 'package:flutter/material.dart';

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

