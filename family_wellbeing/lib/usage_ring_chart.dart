import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart' show AppUsage;

/// Color palette for chart segments - kept warm/neutral, no purple,
/// consistent with the rest of the app's accent (clay/slate/teal family).
const List<Color> kUsagePalette = [
  Color(0xFFD85A30), // clay (brand accent - always the #1 app)
  Color(0xFF2B6CB0), // blue
  Color(0xFF38A169), // green
  Color(0xFFD69E2E), // amber
  Color(0xFF319795), // teal
  Color(0xFFE53E3E), // red
  Color(0xFF4A5568), // slate
];

class _Segment {
  final String name;
  final int minutes;
  final Color color;
  _Segment(this.name, this.minutes, this.color);
}

/// An Apple Screen Time-style ring chart: a rounded, segmented donut with
/// the total time in the center, and a legend of the top contributing apps
/// below (or beside, in compact mode).
class ScreenTimeRingChart extends StatelessWidget {
  final int totalMinutes;
  final List<AppUsage> breakdown;
  final double ringSize;
  final double strokeWidth;
  final int maxLegendItems;
  final String centerLabel;
  final bool compact; // horizontal layout: ring + legend side by side
  final String Function(int minutes)? formatDuration;

  const ScreenTimeRingChart({
    super.key,
    required this.totalMinutes,
    required this.breakdown,
    this.ringSize = 190,
    this.strokeWidth = 22,
    this.maxLegendItems = 5,
    this.centerLabel = 'TOTAL',
    this.compact = false,
    this.formatDuration,
  });

  String _fmt(int minutes) {
    if (formatDuration != null) return formatDuration!(minutes);
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  List<_Segment> _buildSegments(Color otherColor) {
    final sorted = [...breakdown]..sort((a, b) => b.minutes.compareTo(a.minutes));
    final top = sorted.take(maxLegendItems).toList();
    final otherMinutes = sorted.skip(maxLegendItems).fold<int>(0, (sum, a) => sum + a.minutes);

    final segments = <_Segment>[
      for (int i = 0; i < top.length; i++)
        _Segment(top[i].appName, top[i].minutes, kUsagePalette[i % kUsagePalette.length]),
    ];
    if (otherMinutes > 0) {
      segments.add(_Segment('Other', otherMinutes, otherColor));
    }
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final otherColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8);
    final trackColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);

    final segments = _buildSegments(otherColor);
    final safeTotal = totalMinutes > 0 ? totalMinutes : 1;

    final ring = SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(ringSize, ringSize),
            painter: _RingPainter(
              segments: segments, 
              total: safeTotal, 
              strokeWidth: strokeWidth, 
              trackColor: trackColor,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(totalMinutes),
                style: TextStyle(
                  fontSize: compact ? 16 : 28,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                centerLabel,
                style: TextStyle(
                  fontSize: compact ? 8 : 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (segments.isEmpty)
          Text(
            'No app usage recorded.',
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          for (final seg in segments)
            Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 4 : 7),
              child: Row(
                children: [
                  Container(
                    width: compact ? 8 : 10,
                    height: compact ? 8 : 10,
                    decoration: BoxDecoration(color: seg.color, shape: BoxShape.circle),
                  ),
                  SizedBox(width: compact ? 8 : 10),
                  Expanded(
                    child: Text(
                      seg.name,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmt(seg.minutes),
                    style: TextStyle(
                      fontSize: compact ? 11.5 : 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );

    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 240) {
            return Column(
              children: [
                ring,
                const SizedBox(height: 12),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: 18),
              Expanded(child: legend),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        ring,
        const SizedBox(height: 22),
        legend,
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<_Segment> segments;
  final int total;
  final double strokeWidth;
  final Color trackColor;

  _RingPainter({
    required this.segments,
    required this.total,
    required this.strokeWidth,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, trackPaint);

    if (total <= 0 || segments.isEmpty) return;

    const gapRadians = 0.05; // visual breathing room between segments
    double startAngle = -pi / 2;
    for (final seg in segments) {
      final sweep = (seg.minutes / total) * 2 * pi;
      final adjustedSweep = max(sweep - gapRadians, sweep > 0 ? 0.01 : 0.0);
      if (adjustedSweep <= 0) {
        startAngle += sweep;
        continue;
      }
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, adjustedSweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    if (oldDelegate.total != total ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.segments.length != segments.length) {
      return true;
    }
    for (int i = 0; i < segments.length; i++) {
      final a = oldDelegate.segments[i];
      final b = segments[i];
      if (a.name != b.name || a.minutes != b.minutes || a.color != b.color) {
        return true;
      }
    }
    return false;
  }
}
