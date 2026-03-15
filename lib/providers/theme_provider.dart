import 'package:flutter/material.dart';

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = true;
  bool _isGlassyUi = false;

  bool get isDarkMode => _isDarkMode;
  bool get isGlassyUi => _isGlassyUi;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void toggleGlassyUi() {
    _isGlassyUi = !_isGlassyUi;
    notifyListeners();
  }
}
