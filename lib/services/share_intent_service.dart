import 'package:flutter/services.dart';

/// يتحقق من وجود ملف وصل التطبيق عبر مشاركة أندرويد (مثلاً: مستخدم يضغط
/// "مشاركة" على ملف من واتساب ويختار كادي) بدل اضطرار المستخدم لفتح
/// منتقي الملفات والبحث عن الملف بنفسه. الطرف الأصلي (native/
/// ShareIntentBridge.kt) يحتفظ بأي نية واردة لم تُقرأ بعد ويُسلّمها هنا
/// حين يُستدعى getPendingShare — وتُستهلك فور تسليمها فلا تُعاد بطلب لاحق.
///
/// يعتمد على قناة native مباشرة (لا حزمة pub خارجية) مربوطة عبر
/// scripts/patch_add_share_intent_bridge.py في كل بناء — راجع تعليق ذلك
/// السكربت لتفاصيل الآلية.
class ShareIntentService {
  static const _channel = MethodChannel('com.cady.cadysalesapp/share_intent');

  static Future<({String fileName, String content})?> getPendingShare() async {
    try {
      final result = await _channel.invokeMapMethod<String, String>('getPendingShare');
      final fileName = result?['fileName'];
      final content = result?['content'];
      if (fileName == null || content == null) return null;
      return (fileName: fileName, content: content);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // طبيعي على أي منصة غير أندرويد، أو قبل أن يربط سكربت البناء القناة
      return null;
    }
  }
}
