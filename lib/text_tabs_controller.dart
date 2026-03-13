import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

class TextTabsController extends ChangeNotifier {
  TextTabsController(this._prefs);

  static const int tabCount = 9;
  static const _preferencesKeys = <String>[
    "editText1",
    "editText2",
    "editText3",
    "editText4",
    "editText5",
    "editText6",
    "editText7",
    "editText8",
    "editText9",
  ];

  final SharedPreferences _prefs;
  final List<String> _texts = List.filled(tabCount, "", growable: false);
  int _activeIndex = 0;

  int get activeIndex => _activeIndex;
  List<String> get texts => List.unmodifiable(_texts);
  String get activeText => _texts[_activeIndex];

  Future<void> load() async {
    for (var i = 0; i < tabCount; i++) {
      _texts[i] = _prefs.getString(_preferencesKeys[i]) ?? "";
    }
    notifyListeners();
  }

  void updateActiveText(String text, {bool persist = true}) {
    if (_texts[_activeIndex] == text) {
      return;
    }
    _texts[_activeIndex] = text;
    if (persist) {
      _prefs.setString(_preferencesKeys[_activeIndex], text);
    }
  }

  String switchTo(int index, {required String currentText}) {
    if (index < 0 || index >= tabCount) {
      throw RangeError.range(index, 0, tabCount - 1, "index");
    }
    if (index == _activeIndex) {
      updateActiveText(currentText);
      return _texts[_activeIndex];
    }
    updateActiveText(currentText);
    _activeIndex = index;
    notifyListeners();
    return _texts[_activeIndex];
  }

  String textFor(int index) {
    if (index < 0 || index >= tabCount) {
      throw RangeError.range(index, 0, tabCount - 1, "index");
    }
    return _texts[index];
  }

  Future<void> persistAll() async {
    for (var i = 0; i < tabCount; i++) {
      await _prefs.setString(_preferencesKeys[i], _texts[i]);
    }
  }
}
