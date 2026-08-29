import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/sync_status.dart';
import '../models/user_account.dart';
import 'db_service.dart';
import 'settings_service.dart';
import 'share_util.dart';

/// كل العمليات المعلّقة (بانتظار المزامنة) الآن، مجمّعة حسب النوع
class PendingSummary {
  final List<Customer> customers;
  final List<Product> products;
  final List<Invoice> invoices;
  final List<Receipt> receipts;

  const PendingSummary({
    required this.customers,
    required this.products,
    required this.invoices,
    required this.receipts,
  });

  int get total =>
      customers.length + products.length + invoices.length + receipts.length;
}

/// ملف تصدير مُنشَأ لحظة الطلب: نصّه الجاهز للمشاركة، اسم الملف، وملخّص
/// بما احتواه وقت الإنشاء
class SyncExportResult {
  final String json;
  final String fileName;
  final PendingSummary summary;

  const SyncExportResult(
      {required this.json, required this.fileName, required this.summary});
}

/// جانب المندوب من المزامنة: تجميع العمليات المعلّقة، تصديرها كملف JSON
/// للمشاركة مع المدير، وتخزين آخر ملف صُدِّر لإعادة إرساله عند الحاجة
/// بدون توليده من جديد. لا يُغيّر أي سجل حالته هنا إلى "متزامن" — هذا
/// يحدث فقط بعد اعتماد المدير للاستيراد (مرحلة قادمة).
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _lastExportJsonKey = 'last_export_json';
  static const _lastExportNameKey = 'last_export_name';
  static const _lastExportAtKey = 'last_export_at';

  Future<PendingSummary> getPendingSummary() async {
    final customers = (await DbService.instance.getCustomers())
        .where((c) => c.syncStatus == SyncStatus.pending)
        .toList();
    final products = (await DbService.instance.getProducts())
        .where((p) => p.syncStatus == SyncStatus.pending)
        .toList();
    final invoices = (await DbService.instance.getInvoices())
        .where((i) => i.syncStatus == SyncStatus.pending)
        .toList();
    final receipts = (await DbService.instance.getReceipts())
        .where((r) => r.syncStatus == SyncStatus.pending)
        .toList();
    return PendingSummary(
        customers: customers,
        products: products,
        invoices: invoices,
        receipts: receipts);
  }

  String _fileNameFor(UserAccount rep) {
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final label = rep.repNumber.isNotEmpty ? rep.repNumber : rep.username;
    return 'kady_sync_${label}_$stamp.json';
  }

  /// يجمع كل العمليات المعلّقة الآن ويبني نص التصدير — دون مشاركته أو
  /// حفظه بعد؛ استخدم exportAndShare للمسار الكامل
  Future<SyncExportResult> buildExport(UserAccount rep) async {
    final summary = await getPendingSummary();
    final payload = {
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'repId': rep.id,
      'repUsername': rep.username,
      'repDisplayName': rep.displayName,
      'repNumber': rep.repNumber,
      'deviceName': rep.deviceName,
      'customers': summary.customers.map((e) => e.toMap()).toList(),
      'products': summary.products.map((e) => e.toMap()).toList(),
      'invoices': summary.invoices.map((e) => e.toMap()).toList(),
      'receipts': summary.receipts.map((e) => e.toMap()).toList(),
    };
    return SyncExportResult(
      json: const JsonEncoder.withIndent('  ').convert(payload),
      fileName: _fileNameFor(rep),
      summary: summary,
    );
  }

  /// يبني ملف تصدير جديد، يشاركه عبر واجهة المشاركة، ويخزّنه كـ"آخر ملف"
  /// لإعادة الإرسال لاحقًا. لا يُعلَّم أي سجل كـ"متزامن" هنا.
  Future<SyncExportResult> exportAndShare(UserAccount rep) async {
    final result = await buildExport(rep);
    final bytes = Uint8List.fromList(utf8.encode(result.json));
    await ShareUtil.shareBytes(
      bytes,
      result.fileName,
      mimeType: 'application/json',
      text: 'ملف مزامنة - ${rep.displayName}',
    );
    await _cacheLastExport(result);
    return result;
  }

  Future<void> _cacheLastExport(SyncExportResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastExportJsonKey, result.json);
    await prefs.setString(_lastExportNameKey, result.fileName);
    await prefs.setString(_lastExportAtKey, DateTime.now().toIso8601String());
  }

  Future<({String json, String fileName, DateTime at})?> getLastExport() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_lastExportJsonKey);
    final name = prefs.getString(_lastExportNameKey);
    final atStr = prefs.getString(_lastExportAtKey);
    if (json == null || name == null || atStr == null) return null;
    return (json: json, fileName: name, at: DateTime.parse(atStr));
  }

  /// يعيد مشاركة آخر ملف مُصدَّر بالضبط دون توليده من جديد — مفيد لو
  /// فشل النقل أو انقطع أثناء الإرسال في المرة الأولى
  Future<bool> reExportLast() async {
    final last = await getLastExport();
    if (last == null) return false;
    final bytes = Uint8List.fromList(utf8.encode(last.json));
    await ShareUtil.shareBytes(bytes, last.fileName,
        mimeType: 'application/json', text: 'إعادة إرسال ملف مزامنة');
    return true;
  }

  /// يفتح منتقي ملفات لاختيار ملف وارد من المدير (تأكيد مزامنة أو
  /// حزمة تحديث). يعيد null إن أُلغِيت العملية
  Future<String?> pickAckFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  /// يقرأ ملفًا واردًا من المدير ويوجّهه حسب نوعه: "sync_ack" يحوّل
  /// السجلات المذكورة فيه من معلّق إلى متزامن، و"update_package" يطبّق
  /// منتجات/عملاء/إعدادات جديدة مباشرة (وتُعتبر متزامنة فور استلامها)
  Future<IncomingSyncResult> importIncomingFile(String jsonContent) async {
    final Map<String, dynamic> data = jsonDecode(jsonContent);
    final type = data['type'] as String?;
    if (type == 'sync_ack') {
      final count = await _applyAck(data);
      return IncomingSyncResult(type: 'sync_ack', ackedCount: count);
    }
    if (type == 'update_package') {
      return _applyUpdatePackage(data);
    }
    throw const FormatException('نوع ملف غير معروف — تأكد أن الملف من تطبيق كادي');
  }

  Future<int> _applyAck(Map<String, dynamic> data) async {
    final synced = Map<String, dynamic>.from(data['syncedIds'] as Map? ?? {});
    int count = 0;

    final customerIds =
        ((synced['customers'] as List?) ?? []).cast<String>().toSet();
    if (customerIds.isNotEmpty) {
      for (final c in await DbService.instance.getCustomers()) {
        if (customerIds.contains(c.id) && c.syncStatus == SyncStatus.pending) {
          c.syncStatus = SyncStatus.synced;
          await DbService.instance.upsertCustomer(c);
          count++;
        }
      }
    }

    final productIds =
        ((synced['products'] as List?) ?? []).cast<String>().toSet();
    if (productIds.isNotEmpty) {
      for (final p in await DbService.instance.getProducts()) {
        if (productIds.contains(p.id) && p.syncStatus == SyncStatus.pending) {
          p.syncStatus = SyncStatus.synced;
          await DbService.instance.upsertProduct(p);
          count++;
        }
      }
    }

    final invoiceIds =
        ((synced['invoices'] as List?) ?? []).cast<String>().toSet();
    if (invoiceIds.isNotEmpty) {
      for (final inv in await DbService.instance.getInvoices()) {
        if (invoiceIds.contains(inv.id) && inv.syncStatus == SyncStatus.pending) {
          inv.syncStatus = SyncStatus.synced;
          await DbService.instance.upsertInvoice(inv);
          count++;
        }
      }
    }

    final receiptIds =
        ((synced['receipts'] as List?) ?? []).cast<String>().toSet();
    if (receiptIds.isNotEmpty) {
      for (final r in await DbService.instance.getReceipts()) {
        if (receiptIds.contains(r.id) && r.syncStatus == SyncStatus.pending) {
          r.syncStatus = SyncStatus.synced;
          await DbService.instance.upsertReceipt(r);
          count++;
        }
      }
    }

    return count;
  }

  Future<IncomingSyncResult> _applyUpdatePackage(Map<String, dynamic> data) async {
    int productsUpdated = 0;
    int customersUpdated = 0;
    bool settingsUpdated = false;

    if (data['products'] != null) {
      for (final e in (data['products'] as List)) {
        try {
          final p = Product.fromMap(Map<String, dynamic>.from(e as Map));
          p.syncStatus = SyncStatus.synced;
          await DbService.instance.upsertProduct(p);
          productsUpdated++;
        } catch (_) {
          // سجل تالف داخل الملف — يُتخطّى دون إيقاف بقية الاستيراد
        }
      }
    }

    if (data['customers'] != null) {
      for (final e in (data['customers'] as List)) {
        try {
          final c = Customer.fromMap(Map<String, dynamic>.from(e as Map));
          c.syncStatus = SyncStatus.synced;
          await DbService.instance.upsertCustomer(c);
          customersUpdated++;
        } catch (_) {
          // سجل تالف داخل الملف — يُتخطّى دون إيقاف بقية الاستيراد
        }
      }
    }

    if (data['settings'] != null) {
      final incoming = Map<String, dynamic>.from(data['settings'] as Map);
      final current = await SettingsService.instance.load();
      if (incoming['companyName'] != null) {
        current.companyName = incoming['companyName'] as String;
      }
      if (incoming['companyPhone'] != null) {
        current.companyPhone = incoming['companyPhone'] as String;
      }
      if (incoming['companyAddress'] != null) {
        current.companyAddress = incoming['companyAddress'] as String;
      }
      if (incoming['invoiceFooterText'] != null) {
        current.invoiceFooterText = incoming['invoiceFooterText'] as String;
      }
      await SettingsService.instance.save(current);
      settingsUpdated = true;
    }

    return IncomingSyncResult(
      type: 'update_package',
      productsUpdated: productsUpdated,
      customersUpdated: customersUpdated,
      settingsUpdated: settingsUpdated,
    );
  }
}

/// نتيجة استيراد ملف وارد من المدير — إما تأكيد مزامنة أو حزمة تحديث
class IncomingSyncResult {
  final String type;
  final int ackedCount;
  final int productsUpdated;
  final int customersUpdated;
  final bool settingsUpdated;

  const IncomingSyncResult({
    required this.type,
    this.ackedCount = 0,
    this.productsUpdated = 0,
    this.customersUpdated = 0,
    this.settingsUpdated = false,
  });
}
