import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/company_settings.dart';

/// حفظ واسترجاع إعدادات الشركة (الشعار، بيانات الشركة، اسم المندوب،
/// جدول الأصناف، الطابعة، الوضع الليلي) بشكل دائم على الجهاز
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _key = 'company_settings_json';

  // ترحيل لمرة واحدة عند الترقية لإصدار العلامة التجارية الحمراء (2026):
  // قبل هذا التحديث كان الفيروزي (0xFF00838F) هو أول عنصر بلوحة الألوان،
  // فأي مستخدم فتح شاشة الإعدادات وحفظ أي شيء (حتى بدون لمس المظهر) كان
  // يُخزَّن معه هذا اللون صراحةً بالـJSON المحفوظ. تغيير ترتيب اللوحة
  // وحده لا يغيّر شيئًا لهذا المستخدم بعد الترقية، لأن fromJson يقرأ
  // القيمة المخزَّنة الصريحة مباشرة ولا يصل أبدًا لقيمة fallback الجديدة.
  // هذا الترحيل يفحص هذه الحالة تحديدًا ويصحّحها مرة واحدة فقط، ولا يمسّ
  // أي مستخدم اختار لونًا آخر غير الفيروزي الافتراضي القديم عمدًا.
  static const _oldDefaultThemeColorValue = 0xFF00838F;
  static const _migrationFlagKey = 'migrated_brand_red_2026';

  Future<CompanySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    CompanySettings settings;
    if (raw == null) {
      settings = CompanySettings();
    } else {
      try {
        settings = CompanySettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        settings = CompanySettings();
      }
    }

    if (raw != null && !(prefs.getBool(_migrationFlagKey) ?? false)) {
      if (settings.themeColorValue == _oldDefaultThemeColorValue) {
        settings.themeColorValue = kBrandColorPalette.first.value;
        await save(settings);
      }
      await prefs.setBool(_migrationFlagKey, true);
    }

    return settings;
  }

  Future<void> save(CompanySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
