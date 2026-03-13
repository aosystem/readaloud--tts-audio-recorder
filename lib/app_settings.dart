import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  static const _themeKey = "themeNumber";
  static const _localeKey = "localeLanguage";

  final SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.light;
  Locale? _locale;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  bool get isDarkTheme => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    final themeNumber = _prefs.getInt(_themeKey);
    switch (themeNumber) {
      case 1:
        _themeMode = ThemeMode.dark;
        break;
      case 2:
        _themeMode = ThemeMode.system;
        break;
      default:
        _themeMode = ThemeMode.light;
        break;
    }

    final localeCode = _prefs.getString(_localeKey) ?? "";
    _locale = localeCode.isNotEmpty ? Locale(localeCode) : null;
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    final value = switch (mode) {
      ThemeMode.dark => 1,
      ThemeMode.system => 2,
      _ => 0,
    };
    _prefs.setInt(_themeKey, value);
    notifyListeners();
  }

  void setDarkTheme(bool isDark) =>
      setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);

  void setLocaleCode(String? code) {
    final normalized = code?.trim() ?? "";
    final newLocale = normalized.isEmpty ? null : Locale(normalized);
    if (_locale == newLocale) {
      return;
    }
    _locale = newLocale;
    if (normalized.isEmpty) {
      _prefs.remove(_localeKey);
    } else {
      _prefs.setString(_localeKey, normalized);
    }
    notifyListeners();
  }

  void useSystemLocale() => setLocaleCode(null);
}
