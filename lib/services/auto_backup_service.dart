import 'package:shared_preferences/shared_preferences.dart';

import '../models/company_settings.dart';
import 'backup_service.dart';

/// نسخ احتياطي تلقائي (يومي/أسبوعي). بما أن التطبيق لا يعمل في الخلفية
/// (لا خدمة نظام دائمة)، يتم التحقق من الاستحقاق في كل مرة يُفتح فيها
/// التطبيق: إن مرّ الوقت الكافي منذ آخر نسخة، يُنشئ نسخة جديدة بصمت دون
/// مقاطعة المستخدم بشاشة مشاركة. النسخ اليدوي (زر "نسخ احتياطي فوري")
/// يبقى دائمًا يفتح شاشة المشاركة كما هو.
///
/// تُحفَظ كل نسخة (تلقائية أو يدوية) بنفس سجلّ BackupService الموحّد —
/// سابقًا كانت النسخ التلقائية بصندوق Hive منفصل تمامًا وغير مرئي بشاشة
/// إدارة النسخ؛ الآن تظهر بنفس القائمة القابلة للاستعراض والاستعادة
/// والمشاركة، فقط موسومة source: auto لتمييزها.
class AutoBackupService {
  static const _lastRunKey = 'auto_backup_last_run_at';

  static Future<void> runIfDue(CompanySettings settings) async {
    if (settings.autoBackupFrequency == AutoBackupFrequency.off) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRunStr = prefs.getString(_lastRunKey);
      final lastRun = lastRunStr != null ? DateTime.tryParse(lastRunStr) : null;
      final due = settings.autoBackupFrequency == AutoBackupFrequency.daily
          ? const Duration(days: 1)
          : const Duration(days: 7);
      if (lastRun != null && DateTime.now().difference(lastRun) < due) return;

      await BackupService.instance.createBackupRecord(source: BackupSource.auto);
      await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());
    } catch (_) {
      // فشل صامت — نسخة تلقائية فاشلة لا يجب أن تُزعج المستخدم عند فتح التطبيق
    }
  }

  static Future<DateTime?> lastRunAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastRunKey);
    return raw != null ? DateTime.tryParse(raw) : null;
  }
}
