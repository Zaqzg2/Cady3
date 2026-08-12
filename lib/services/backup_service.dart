import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/company_settings.dart';
import 'db_service.dart';
import 'settings_service.dart';
import 'numbering_service.dart';
import 'share_util.dart';

/// نسخ احتياطي كامل لكل بيانات التطبيق (عملاء، منتجات، فواتير، سندات،
/// إعدادات) إلى JSON يمكن مشاركته أو حفظه (Google Drive، بريد، واتساب...)،
/// مع إمكانية استيراده لاحقًا على نفس الجهاز أو جهاز آخر. كل شيء يعمل في
/// الذاكرة (بدون كتابة ملفات على القرص) حتى يعمل على الجوال والويب معًا.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _formatVersion = 1;

  Future<Map<String, dynamic>> _buildBackupJson() async {
    final customers = await DbService.instance.getCustomers();
    final products = await DbService.instance.getProducts();
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();
    final settings = await SettingsService.instance.load();

    return {
      'formatVersion': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'customers': customers.map((c) => c.toMap()).toList(),
      'products': products.map((p) => p.toMap()).toList(),
      'invoices': invoices.map((i) => i.toMap()).toList(),
      'receipts': receipts.map((r) => r.toMap()).toList(),
      'settings': settings.toJson(),
    };
  }

  /// يبني محتوى النسخة الاحتياطية كنص JSON (بدون أي كتابة على القرص)
  Future<String> exportToJsonString() async {
    final data = await _buildBackupJson();
    return jsonEncode(data);
  }

  String _backupFileName() {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'كادي_نسخة_احتياطية_$stamp.json';
  }

  /// يبني النسخة الاحتياطية ثم يفتح واجهة المشاركة (حفظ في Drive / واتساب
  /// / بريد... أو تنزيل مباشر على الويب)
  Future<void> exportAndShare() async {
    final json = await exportToJsonString();
    final bytes = Uint8List.fromList(utf8.encode(json));
    await ShareUtil.shareBytes(bytes, _backupFileName(),
        mimeType: 'application/json',
        text: 'نسخة احتياطية - تطبيق كادي للمنظفات');
  }

  /// يفتح منتقي ملفات ليختار المستخدم ملف JSON للاستيراد، ويعيد محتواه
  /// كنص مباشرة (withData: true تضمن توفر البايتات على كل المنصات، بما
  /// فيها الويب حيث لا يوجد مسار ملف حقيقي أصلاً)
  Future<String?> pickBackupContent() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  /// يستورد نسخة احتياطية من نص JSON، ويدمج البيانات (upsert بالمعرف) دون
  /// حذف أي بيانات حالية غير موجودة بالنسخة المستوردة.
  Future<void> importFromJson(String jsonContent) async {
    final Map<String, dynamic> data = jsonDecode(jsonContent);

    final customers = (data['customers'] as List? ?? [])
        .map((e) => Customer.fromMap(Map<String, dynamic>.from(e)));
    for (final c in customers) {
      await DbService.instance.upsertCustomer(c);
    }

    final products = (data['products'] as List? ?? [])
        .map((e) => Product.fromMap(Map<String, dynamic>.from(e)));
    for (final p in products) {
      await DbService.instance.upsertProduct(p);
    }

    final invoices = (data['invoices'] as List? ?? [])
        .map((e) => Invoice.fromMap(Map<String, dynamic>.from(e)));
    for (final inv in invoices) {
      await DbService.instance.upsertInvoice(inv);
      await NumberingService.instance.commitUsedNumber(
          inv.kind == InvoiceKind.sale ? 'sale' : 'return', inv.docNumber);
    }

    final receipts = (data['receipts'] as List? ?? [])
        .map((e) => Receipt.fromMap(Map<String, dynamic>.from(e)));
    for (final r in receipts) {
      await DbService.instance.upsertReceipt(r);
      await NumberingService.instance.commitUsedNumber('receipt', r.docNumber);
    }

    if (data['settings'] != null) {
      final settings =
          CompanySettings.fromJson(Map<String, dynamic>.from(data['settings']));
      await SettingsService.instance.save(settings);
    }
  }
}
