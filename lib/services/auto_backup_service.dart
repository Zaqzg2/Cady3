import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company_settings.dart';
import 'backup_service.dart';

/// نسخ احتياطي تلقائي (يومي/أسبوعي). بما أن التطبيق لا يعمل في الخلفية
/// (لا خدمة نظام دائمة)، يتم التحقق من الاستحقاق في كل مرة يُفتح فيها
/// التطبيق: إن مرّ الوقت الكافي منذ آخر نسخة، يُنشئ نسخة جديدة بصمت دون
/// مقاطعة المستخدم بشاشة مشاركة. النسخ اليدوي (زر "نسخ احتياطي فوري")
/// يبقى دائمًا يفتح شاشة المشاركة كما هو.
///
/// تُحفَظ النسخ داخل Hive نفسه (بدل ملفات على القرص) — هذا يعمل بنفس
/// الطريقة على الجوال والويب معًا، بدون أي فرع كود خاص بالمنصة.
class AutoBackupService {
  static const _boxName = 'auto_backups';
  static const _lastRunKey = 'auto_backup_last_run_at';
  static const _keepCount = 5;

  static Future<Box> _box() => Hive.openBox(_boxName);

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

      final json = await BackupService.instance.exportToJsonString();
      final box = await _box();
      final key = DateTime.now().toIso8601String();
      await box.put(key, json);
      await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());
      await _pruneOld(box);
    } catch (_) {
      // فشل صامت — نسخة تلقائية فاشلة لا يجب أن تُزعج المستخدم عند فتح التطبيق
    }
  }

  static Future<DateTime?> lastRunAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastRunKey);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  /// أحدث نسخة تلقائية محفوظة (نص JSON)، أو null إن لم توجد أي نسخة بعد
  static Future<String?> latestSnapshot() async {
    final box = await _box();
    if (box.isEmpty) return null;
    final keys = box.keys.cast<String>().toList()..sort();
    return box.get(keys.last) as String?;
  }

  static Future<void> _pruneOld(Box box) async {
    final keys = box.keys.cast<String>().toList()..sort();
    if (keys.length <= _keepCount) return;
    final toRemove = keys.sublist(0, keys.length - _keepCount);
    for (final k in toRemove) {
      await box.delete(k);
    }
  }
}
