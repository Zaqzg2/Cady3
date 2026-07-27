import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/company_settings.dart';
import 'db_service.dart';
import 'settings_service.dart';
import 'numbering_service.dart';

/// نسخ احتياطي كامل لكل بيانات التطبيق (عملاء، منتجات، فواتير، سندات،
/// إعدادات) إلى ملف JSON واحد يمكن مشاركته أو حفظه (Google Drive، بريد،
/// واتساب...)، مع إمكانية استيراده لاحقًا على نفس الجهاز أو جهاز آخر.
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

  /// يُنشئ ملف النسخة الاحتياطية محليًا ويعيد مساره
  Future<File> exportToFile() async {
    final data = await _buildBackupJson();
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/كادي_نسخة_احتياطية_$stamp.json');
    await file.writeAsString(jsonEncode(data));
    return file;
  }

  /// يُنشئ الملف ثم يفتح واجهة المشاركة (حفظ في Drive / واتساب / بريد...)
  Future<File> exportAndShare() async {
    final file = await exportToFile();
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'نسخة احتياطية - تطبيق كادي للمنظفات'));
    return file;
  }

  /// يفتح منتقي ملفات ليختار المستخدم ملف JSON للاستيراد
  Future<String?> pickBackupFilePath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return null;
    return result.files.single.path;
  }

  /// يستورد نسخة احتياطية من مسار ملف، ويدمج البيانات (upsert بالمعرف)
  /// دون حذف أي بيانات حالية غير موجودة في الملف المستورد.
  Future<void> importFromFile(String path) async {
    final content = await File(path).readAsString();
    final Map<String, dynamic> data = jsonDecode(content);

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
