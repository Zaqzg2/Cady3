import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';

/// اهتزاز و/أو صوت تنبيه عند نجاح حفظ فاتورة أو سند — حسب تفضيلات
/// المستخدم في إعدادات المظهر. يستخدم واجهات النظام المدمجة في فلاتر
/// (بدون الحاجة لأي حزمة صوت خارجية أو ملف صوتي إضافي).
class FeedbackService {
  static void onSaved(BuildContext context) {
    final settings = context.read<AppProvider>().settings;
    if (settings.hapticOnSave) {
      HapticFeedback.mediumImpact();
    }
    if (settings.soundOnSave) {
      SystemSound.play(SystemSoundType.click);
    }
  }
}
