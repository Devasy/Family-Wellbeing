import 'package:flutter/material.dart';

class SlidingSegmentControl extends StatelessWidget {
  const SlidingSegmentControl({
    super.key,
    required this.selectedValue,
    required this.values,
    required this.labels,
    required this.onValueChanged,
  });

  final String selectedValue;
  final List<String> values;
  final List<String> labels;
  final ValueChanged<String> onValueChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final int selectedIndex = values.indexOf(selectedValue);
    final int safeIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = constraints.maxWidth;
          final double segmentWidth = totalWidth / values.length;

          return Stack(
            children: [
              // Gliding background highlight pill
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                left: safeIndex * segmentWidth,
                width: segmentWidth,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Gesture detectors and text labels
              Row(
                children: List.generate(values.length, (index) {
                  final val = values[index];
                  final label = labels[index];
                  final bool isActive = selectedValue == val;

                  return Expanded(
                    child: Semantics(
                      label: label,
                      button: true,
                      selected: isActive,
                      child: GestureDetector(
                        onTap: () => onValueChanged(val),
                        child: Container(
                          color: Colors.transparent, // Expand tap hit area
                          alignment: Alignment.center,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                              color: isActive
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}
