import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeViewModel extends ChangeNotifier {
  ThemeViewModel._();
  static final ThemeViewModel instance = ThemeViewModel._();

  String _themeMode = 'light'; // 'light' | 'dark' | 'amoled'
  String get themeMode => _themeMode;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = prefs.getString('themeMode') ?? 'light';
    _applySystemUI();
    notifyListeners();
  }

  Future<void> updateTheme(String newMode) async {
    if (_themeMode == newMode) return;
    _themeMode = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', newMode);
    _applySystemUI();
    notifyListeners();
  }

  void _applySystemUI() {
    final bool isDark = _themeMode == 'dark' || _themeMode == 'amoled';
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));
  }

  ThemeData getThemeData() {
    switch (_themeMode) {
      case 'dark':
        return _buildDarkTheme();
      case 'amoled':
        return _buildAmoledTheme();
      case 'light':
      default:
        return _buildLightTheme();
    }
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF4F4F5), // Zinc light background
      dividerColor: const Color(0xFFE4E4E7), // Border color
      cardColor: const Color(0xFFFAFAFA),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF18181B),
        secondary: Color(0xFFD85A30), // Warm clay accent
        surface: Color(0xFFFAFAFA),
        onSurface: Color(0xFF18181B),
        onSurfaceVariant: Color(0xFF71717A),
      ),
      fontFamily: 'sans-serif',
      cardTheme: CardThemeData(
        color: const Color(0xFFFAFAFA),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF18181B)),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF09090B), // Zinc dark background
      dividerColor: const Color(0xFF27272A), // Border color
      cardColor: const Color(0xFF18181B),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFAFAFA),
        secondary: Color(0xFFD85A30), // Warm clay accent
        surface: Color(0xFF18181B),
        onSurface: Color(0xFFFAFAFA),
        onSurfaceVariant: Color(0xFFA1A1AA),
      ),
      fontFamily: 'sans-serif',
      cardTheme: CardThemeData(
        color: const Color(0xFF18181B),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF27272A), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFFAFAFA)),
      ),
    );
  }

  ThemeData _buildAmoledTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF000000), // Pure Black background
      dividerColor: const Color(0xFF18181B), // Border color
      cardColor: const Color(0xFF09090B),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFFFFF),
        secondary: Color(0xFFD85A30), // Warm clay accent
        surface: Color(0xFF09090B),
        onSurface: Color(0xFFFFFFFF),
        onSurfaceVariant: Color(0xFFA1A1AA),
      ),
      fontFamily: 'sans-serif',
      cardTheme: CardThemeData(
        color: const Color(0xFF09090B),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF18181B), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFFFFFFF)),
      ),
    );
  }
}
