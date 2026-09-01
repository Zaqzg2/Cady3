import 'package:shared_preferences/shared_preferences.dart';

/// خدمة ترقيم المستندات (فاتورة بيع / فاتورة مرتجع / سند قبض)
/// القاعدة: عند تعديل المستخدم لرقم المستند يدويًا، يجب أن يتابع الرقم
/// التالي من الرقم الجديد ولا يعود إلى التسلسل القديم أبدًا.
/// لذلك نُخزّن "أعلى رقم استُخدم" لكل نوع مستند، ونقترح دائمًا: أعلى رقم + 1
class NumberingService {
  NumberingService._();
  static final NumberingService instance = NumberingService._();

  static const _prefixSale = 'counter_sale';
  static const _prefixReturn = 'counter_return';
  static const _prefixReceipt = 'counter_receipt';

  Future<int> _get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? 0;
  }

  Future<void> _set(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  String _keyFor(String docType) {
    switch (docType) {
      case 'sale':
        return _prefixSale;
      case 'return':
        return _prefixReturn;
      case 'receipt':
        return _prefixReceipt;
      default:
        throw ArgumentError('نوع مستند غير معروف: $docType');
    }
  }

  /// يرجع رقم المستند التالي المقترح (كنص) بدون حجزه بعد
  Future<String> peekNextNumber(String docType) async {
    final current = await _get(_keyFor(docType));
    return (current + 1).toString();
  }

  /// يستخرج الجزء الرقمي من نص الرقم (يدعم بادئات مثل INV-0012)
  int _extractNumeric(String docNumber) {
    final match = RegExp(r'(\d+)').allMatches(docNumber).lastOrNull;
    if (match == null) return 0;
    return int.tryParse(match.group(1) ?? '0') ?? 0;
  }

  /// يُستدعى بعد حفظ المستند فعليًا: يحدّث العداد ليكون بحيث
  /// أن أي رقم تالٍ سيكون دائمًا أكبر من الرقم الذي استخدمه المستخدم للتو،
  /// حتى لو كان قد عدّله يدويًا إلى رقم أكبر أو أصغر من المتسلسل.
  Future<void> commitUsedNumber(String docType, String usedDocNumber) async {
    final key = _keyFor(docType);
    final usedNumeric = _extractNumeric(usedDocNumber);
    final current = await _get(key);
    if (usedNumeric > current) {
      await _set(key, usedNumeric);
    }
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
