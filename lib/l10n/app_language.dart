import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';

class AppLanguage extends ChangeNotifier {
  AppLanguage(this.preferences) {
    final saved = preferences.getString('gesture.language');
    _code = AppStrings.names.containsKey(saved) ? saved! : 'en';
  }
  final SharedPreferences preferences;
  late String _code;
  String get code => _code;
  Locale get locale => Locale(_code);
  Future<void> select(String code) async {
    if (!AppStrings.names.containsKey(code) || code == _code) return;
    if (!await preferences.setString('gesture.language', code)) {
      throw StateError('Language preference could not be saved');
    }
    _code = code;
    notifyListeners();
  }
}
