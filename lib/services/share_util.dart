import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

/// مشاركة/تنزيل ملف من بايتات في الذاكرة مباشرة — بدون كتابته على القرص
/// أولًا. هذا يعمل بنفس الطريقة على الجوال (تفتح قائمة المشاركة) والويب
/// (تستخدم Web Share API لو مدعومة، أو تُنزّل الملف مباشرة تلقائيًا لو
/// غير مدعومة) — راجع توثيق share_plus لهذا السلوك بالضبط.
class ShareUtil {
  static Future<void> shareBytes(
    Uint8List bytes,
    String filename, {
    String mimeType = 'application/pdf',
    String? text,
  }) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType)],
      fileNameOverrides: [filename],
      text: text,
    ));
  }

  /// نفس الفكرة لكن لعدة ملفات دفعة واحدة (مثل تصدير عدة ملفات CSV معًا)
  static Future<void> shareMultiple(
    List<(Uint8List, String)> items, {
    String mimeType = 'text/csv',
    String? text,
  }) async {
    await SharePlus.instance.share(ShareParams(
      files: [for (final it in items) XFile.fromData(it.$1, mimeType: mimeType)],
      fileNameOverrides: [for (final it in items) it.$2],
      text: text,
    ));
  }
}
