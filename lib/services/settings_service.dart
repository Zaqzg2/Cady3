import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/company_settings.dart';

/// حفظ واسترجاع إعدادات الشركة (الشعار، بيانات الشركة، اسم المندوب،
/// جدول الأصناف، الطابعة، الوضع الليلي) بشكل دائم على الجهاز
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _key = 'company_settings_json';

  Future<CompanySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return CompanySettings();
    try {
      return CompanySettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return CompanySettings();
    }
  }

  Future<void> save(CompanySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
