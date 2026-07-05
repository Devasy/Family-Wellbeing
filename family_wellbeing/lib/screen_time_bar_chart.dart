import 'dart:math';
import 'package:flutter/material.dart';
import 'usage_ring_chart.dart' show kUsagePalette;

/// Shared bar layout so _handleTouch and _BarChartPainter.paint always agree.
class _BarLayout {
  const _BarLayout._({
    required this.barWidth,
    required this.spacing,
    required this.startX,
  });

  final double barWidth;
  final double spacing;
  final double startX;

  static const double leftPadding = 36.0;
  static const double rightPadding = 12.0;

  /// Returns null when [chartWidth] ≤ 0 or [dayCount] == 0.
  static _BarLayout? compute(double chartWidth, int dayCount) {
    if (chartWidth <= 0 || dayCount == 0) return null;
    final double barWidth = min(20.0, chartWidth / (dayCount * 1.6));
    final double spacing =
        (chartWidth - (barWidth * dayCount)) / (dayCount - 1 + 2);
    final double startX = leftPadding + spacing;
    return _BarLayout._(barWidth: barWidth, spacing: spacing, startX: startX);
  }
}

class BarChartSegment {
  final String name;
  final int minutes;
  final Color color;

  BarChartSegment({
    required this.name,
    required this.minutes,
    required this.color,
  });
}

class BarChartDayData {
  final String label; // e.g. "Mon" or "Jul 4"
  final int totalMinutes;
  final List<BarChartSegment> segments;

  BarChartDayData({
    required this.label,
    required this.totalMinutes,
    required this.segments,
  });
}

class ScreenTimeBarChart extends StatefulWidget {
  const ScreenTimeBarChart({
    super.key,
    required this.dayData,
    required this.formatDuration,
    required this.comparisonText,
    this.height = 200,
  });

  final List<BarChartDayData> dayData;
  final String Function(int) formatDuration;
  final String comparisonText;
  final double height;

  @override
  State<ScreenTimeBarChart> createState() => _ScreenTimeBarChartState();
}

class _ScreenTimeBarChartState extends State<ScreenTimeBarChart> {
  int? _hoveredIdx;

  void _handleTouch(Offset localPos, Size size) {
    final double chartWidth =
        size.width - _BarLayout.leftPadding - _BarLayout.rightPadding;
    final layout = _BarLayout.compute(chartWidth, widget.dayData.length);
    if (layout == null) return;

    final int numDays = widget.dayData.length;
    int? detectedIdx;
    for (int i = 0; i < numDays; i++) {
      final double x = layout.startX + i * (layout.barWidth + layout.spacing);
      if (localPos.dx >= x - layout.spacing / 2 &&
          localPos.dx <= x + layout.barWidth + layout.spacing / 2) {
        detectedIdx = i;
        break;
      }
    }

    if (detectedIdx != _hoveredIdx) {
      setState(() {
        _hoveredIdx = detectedIdx;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeDays = widget.dayData.where((d) => d.totalMinutes > 0).length;
    final totalMinutes = widget.dayData.fold<int>(0, (sum, d) => sum + d.totalMinutes);
    final double avgMinutes = activeDays > 0 ? totalMinutes / widget.dayData.length : 0.0;
    
    final int maxMinutes = widget.dayData.fold<int>(0, (maxVal, d) => max(maxVal, d.totalMinutes));
    final double yMax = max(maxMinutes, 120).toDouble() * 1.15; 

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = Size(constraints.maxWidth, widget.height);
        return Column(
          children: [
            GestureDetector(
              onTapDown: (details) => _handleTouch(details.localPosition, chartSize),
              onPanUpdate: (details) => _handleTouch(details.localPosition, chartSize),
              onTapUp: (_) => setState(() => _hoveredIdx = null),
              onTapCancel: () => setState(() => _hoveredIdx = null),
              onPanEnd: (_) => setState(() => _hoveredIdx = null),
              onPanCancel: () => setState(() => _hoveredIdx = null),
              child: SizedBox(
                height: widget.height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _BarChartPainter(
                    dayData: widget.dayData,
                    avgMinutes: avgMinutes,
                    yMax: yMax,
                    theme: theme,
                    isDark: isDark,
                    formatDuration: widget.formatDuration,
                    hoveredIdx: _hoveredIdx,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Legend summary row with comparison text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Average',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.comparisonText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: widget.comparisonText.contains('↑')
                            ? const Color(0xFFD85A30) // brand warm clay for increase
                            : widget.comparisonText.contains('↓')
                                ? const Color(0xFF38A169) // green for decrease
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Text(
                  widget.formatDuration(avgMinutes.round()),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<BarChartDayData> dayData;
  final double avgMinutes;
  final double yMax;
  final ThemeData theme;
  final bool isDark;
  final String Function(int) formatDuration;
  final int? hoveredIdx;

  _BarChartPainter({
    required this.dayData,
    required this.avgMinutes,
    required this.yMax,
    required this.theme,
    required this.isDark,
    required this.formatDuration,
    required this.hoveredIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPadding = 36.0;
    const double rightPadding = 12.0;
    const double topPadding = 24.0;
    const double bottomPadding = 24.0;

    final double chartWidth = size.width - leftPadding - rightPadding;
    final double chartHeight = size.height - topPadding - bottomPadding;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    // Draw horizontal grid lines (at 0%, 50%, 100%)
    final gridPaint = Paint()
      ..color = theme.dividerColor.withOpacity(0.5)
      ..strokeWidth = 1.0;

    final gridLevels = [0.0, 0.5, 1.0];
    for (final level in gridLevels) {
      final y = size.height - bottomPadding - (chartHeight * level);
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );

      // Draw grid values text on the left axis
      final int levelMinutes = (yMax * level).round();
      if (levelMinutes > 0) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: formatDuration(levelMinutes),
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(leftPadding - textPainter.width - 6, y - textPainter.height / 2),
        );
      }
    }

    // Draw bars
    final layout = _BarLayout.compute(chartWidth, dayData.length);
    if (layout == null) return; // nothing to draw (empty data)
    final double barWidth = layout.barWidth;
    final double spacing = layout.spacing;
    final double startX = layout.startX;

    for (int i = 0; i < dayData.length; i++) {
      final day = dayData[i];
      final double x = startX + i * (barWidth + spacing);
      final double bottomY = size.height - bottomPadding;

      // Draw hover feedback backdrop column
      if (hoveredIdx == i) {
        final hoverPaint = Paint()
          ..color = theme.colorScheme.onSurface.withOpacity(0.04)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - spacing / 3, topPadding - 4, barWidth + (2 * spacing) / 3, chartHeight + 8),
            const Radius.circular(8),
          ),
          hoverPaint,
        );
      }

      // Draw empty bar placeholder track
      final trackPaint = Paint()
        ..color = isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5)
        ..style = PaintingStyle.fill;
      final trackRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, topPadding, barWidth, chartHeight),
        const Radius.circular(6),
      );
      canvas.drawRRect(trackRect, trackPaint);

      // Draw stacked segments
      if (day.totalMinutes > 0) {
        double currentY = bottomY;
        
        for (int j = 0; j < day.segments.length; j++) {
          final seg = day.segments[j];
          final double segHeight = (seg.minutes / yMax) * chartHeight;
          if (segHeight <= 0) continue;

          final double segTop = max(topPadding, currentY - segHeight);
          final rectPaint = Paint()..color = seg.color;

          final isTopSegment = j == day.segments.length - 1 || 
              day.segments.skip(j + 1).fold<int>(0, (sum, s) => sum + s.minutes) == 0;

          if (isTopSegment) {
            final rect = RRect.fromRectAndCorners(
              Rect.fromLTRB(x, segTop, x + barWidth, currentY),
              topLeft: const Radius.circular(6),
              topRight: const Radius.circular(6),
            );
            canvas.drawRRect(rect, rectPaint);
          } else {
            final rect = Rect.fromLTRB(x, segTop, x + barWidth, currentY);
            canvas.drawRect(rect, rectPaint);
          }

          currentY = segTop;
        }
      }

      // Draw day label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: day.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: hoveredIdx == i ? FontWeight.bold : FontWeight.w600,
            color: hoveredIdx == i ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(x + (barWidth - labelPainter.width) / 2, size.height - bottomPadding + 6),
      );
    }

    // Draw average line
    if (avgMinutes > 0 && avgMinutes <= yMax) {
      final double avgY = size.height - bottomPadding - (chartHeight * (avgMinutes / yMax));
      final double startXLine = leftPadding;
      final double endXLine = size.width - rightPadding;

      final avgLinePaint = Paint()
        ..color = theme.colorScheme.secondary.withOpacity(0.9)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      // Draw dashes
      double dashX = startXLine;
      const double dashWidth = 5.0;
      const double dashSpace = 4.0;
      while (dashX < endXLine) {
        final double drawEnd = min(dashX + dashWidth, endXLine);
        canvas.drawLine(Offset(dashX, avgY), Offset(drawEnd, avgY), avgLinePaint);
        dashX += dashWidth + dashSpace;
      }

      // Draw average text badge
      final avgText = 'Avg: ${formatDuration(avgMinutes.round())}';
      final textPainter = TextPainter(
        text: TextSpan(
          text: avgText,
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final double labelX = endXLine - textPainter.width - 8;
      final double labelY = avgY - textPainter.height - 4;
      final double adjustedLabelY = max(topPadding - 4, labelY);

      final bgPaint = Paint()
        ..color = theme.colorScheme.secondary
        ..style = PaintingStyle.fill;

      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          labelX - 4,
          adjustedLabelY,
          textPainter.width + 8,
          textPainter.height + 4,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(labelRect, bgPaint);

      textPainter.paint(canvas, Offset(labelX, adjustedLabelY + 2));
    }

    // Draw hover tooltip on top of everything
    if (hoveredIdx != null && hoveredIdx! >= 0 && hoveredIdx! < dayData.length) {
      final day = dayData[hoveredIdx!];
      final double x = startX + hoveredIdx! * (barWidth + spacing);
      final double bottomY = size.height - bottomPadding;
      final double barTopY = bottomY - (day.totalMinutes / yMax * chartHeight);

      final tooltipText = '${day.label}: ${formatDuration(day.totalMinutes)}';
      final tooltipPainter = TextPainter(
        text: TextSpan(
          text: tooltipText,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.black : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      double tooltipX = x + barWidth / 2 - tooltipPainter.width / 2;
      double tooltipY = barTopY - tooltipPainter.height - 12;

      tooltipY = max(topPadding - 8, tooltipY);
      tooltipX = max(leftPadding, min(size.width - rightPadding - tooltipPainter.width - 8, tooltipX));

      final tooltipBgPaint = Paint()
        ..color = theme.colorScheme.onSurface
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(tooltipX - 8, tooltipY - 6, tooltipPainter.width + 16, tooltipPainter.height + 12),
          const Radius.circular(6),
        ),
        tooltipBgPaint,
      );

      tooltipPainter.paint(canvas, Offset(tooltipX, tooltipY + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    // Value-based comparison for dayData to avoid spurious repaints when the
    // parent rebuilds with a new list instance containing identical entries.
    bool dayDataChanged = oldDelegate.dayData.length != dayData.length;
    if (!dayDataChanged) {
      for (int i = 0; i < dayData.length; i++) {
        if (oldDelegate.dayData[i].label != dayData[i].label ||
            oldDelegate.dayData[i].totalMinutes != dayData[i].totalMinutes) {
          dayDataChanged = true;
          break;
        }
      }
    }
    return dayDataChanged ||
        oldDelegate.avgMinutes != avgMinutes ||
        oldDelegate.yMax != yMax ||
        oldDelegate.theme != theme ||
        oldDelegate.isDark != isDark ||
        oldDelegate.hoveredIdx != hoveredIdx;
  }
}
