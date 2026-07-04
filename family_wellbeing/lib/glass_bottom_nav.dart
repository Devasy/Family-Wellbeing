import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme_manager.dart';

class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
  });

  final String activeTab;
  final ValueChanged<String> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Define glassmorphic colors
    Color glassBg;
    Color glassBorder;
    if (ThemeViewModel.instance.themeMode == 'amoled') {
      glassBg = Colors.black.withOpacity(0.75);
      glassBorder = Colors.white.withOpacity(0.08);
    } else if (isDark) {
      glassBg = const Color(0xFF18181B).withOpacity(0.75);
      glassBorder = Colors.white.withOpacity(0.1);
    } else {
      glassBg = Colors.white.withOpacity(0.8);
      glassBorder = Colors.black.withOpacity(0.08);
    }

    final highlightColor = isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE4E4E7);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: bottomPadding > 0 ? bottomPadding : 12,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36), // 1.2x of 30
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 204, // 1.2x of 170
              height: 65,  // 1.2x of 54
              decoration: BoxDecoration(
                color: glassBg,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: glassBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withOpacity(0.5) : Colors.black.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Shared sliding highlight pill container (butter smooth animation)
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    alignment: activeTab == 'dashboard'
                        ? const Alignment(-0.8, 0.0)
                        : const Alignment(0.8, 0.0),
                    child: Container(
                      width: 76,
                      height: 42,
                      decoration: BoxDecoration(
                        color: highlightColor,
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                  // Row of icons
                  Row(
                    children: [
                      _buildNavItem(
                        context: context,
                        tab: 'dashboard',
                        activeIcon: Icons.insights,
                        inactiveIcon: Icons.insights_outlined,
                      ),
                      _buildNavItem(
                        context: context,
                        tab: 'leaderboard',
                        activeIcon: Icons.leaderboard,
                        inactiveIcon: Icons.leaderboard_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required String tab,
    required IconData activeIcon,
    required IconData inactiveIcon,
  }) {
    final bool isActive = activeTab == tab;
    final theme = Theme.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(tab),
        child: Container(
          color: Colors.transparent, // Expand gesture hit box
          alignment: Alignment.center,
          child: Icon(
            isActive ? activeIcon : inactiveIcon,
            color: isActive ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
            size: 26, // 1.2x of 22
          ),
        ),
      ),
    );
  }
}
