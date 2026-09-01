import 'dart:convert';
import 'dart:typed_data';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:uuid/uuid.dart';

/// تخزين الصور (توقيعات العملاء/المندوب، شعار الشركة) داخل Hive نفسه
/// (كنص Base64) بدل كتابتها كملفات على القرص. هذا يجعلها تعمل بنفس
/// الطريقة تمامًا على الجوال والويب (لا يوجد نظام ملفات حقيقي بالمتصفح)
/// دون أي فرع كود خاص بكل منصة.
///
/// القيمة المُخزَّنة بكل حقل (logoPath, signaturePath, ...) في باقي
/// الموديلات تبقى String? كما هي، لكنها الآن "مفتاح" بهذا المخزن بدل
/// مسار ملف فعلي.
class ImageStore {
  ImageStore._();
  static final ImageStore instance = ImageStore._();

  static const _boxName = 'images';
  Box? _box;

  Future<Box> _ensureBox() async {
    _box ??= await Hive.openBox(_boxName);
    return _box!;
  }

  /// يحفظ بايتات صورة ويرجع مفتاحًا لاسترجاعها لاحقًا. لو مُرِّر [key]
  /// موجود مسبقًا، يُستبدل محتواه بدل إنشاء إدخال جديد (مفيد عند تحديث
  /// شعار أو توقيع محفوظ مسبقًا بنفس المكان).
  Future<String> save(Uint8List bytes, {String? key}) async {
    final box = await _ensureBox();
    final k = key ?? const Uuid().v4();
    await box.put(k, base64Encode(bytes));
    return k;
  }

  Future<Uint8List?> load(String? key) async {
    if (key == null || key.isEmpty) return null;
    final box = await _ensureBox();
    final raw = box.get(key);
    if (raw == null) return null;
    try {
      return base64Decode(raw as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String? key) async {
    if (key == null) return;
    final box = await _ensureBox();
    await box.delete(key);
  }

  Future<List<String>> allKeys() async {
    final box = await _ensureBox();
    return box.keys.cast<String>().toList();
  }
}
