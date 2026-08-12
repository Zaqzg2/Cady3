import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/sync_status.dart';
import '../models/sync_log_entry.dart';
import '../models/export_log_entry.dart';
import 'db_service.dart';
import 'account_service.dart';
import 'numbering_service.dart';
import 'settings_service.dart';
import 'share_util.dart';

/// نتيجة تحليل ملف مزامنة وارد من مندوب — معاينة كاملة قبل أي كتابة
/// لقاعدة بيانات المدير
class ImportPreview {
  final List<Customer> customers;
  final List<Product> products;
  final List<Invoice> invoices;
  final List<Receipt> receipts;
  final int newCustomersCount;
  final int duplicatesCount;
  final int errorsCount;
  final String repId;
  final String repDisplayName;
  final String fileName;

  const ImportPreview({
    required this.customers,
    required this.products,
    required this.invoices,
    required this.receipts,
    required this.newCustomersCount,
    required this.duplicatesCount,
    required this.errorsCount,
    required this.repId,
    required this.repDisplayName,
    required this.fileName,
  });

  int get invoicesCount => invoices.length;
  int get receiptsCount => receipts.length;
}

/// جانب المدير من المزامنة: قراءة ومعاينة ملف مندوب قبل الاعتماد، الكتابة
/// الفعلية لقاعدة البيانات عند الاعتماد، تسجيل العملية في سجل المزامنة،
/// وبناء ملف "تأكيد استلام" يُشارَك مع المندوب لتحويل حالته المحلية إلى
/// "متزامن" (راجع SyncService.importIncomingFile في جانب المندوب)
class ManagerSyncService {
  ManagerSyncService._();
  static final ManagerSyncService instance = ManagerSyncService._();
  final _uuid = const Uuid();

  Future<ImportPreview?> pickAndPreview() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    final fileName = result?.files.single.name ?? 'sync.json';
    final Map<String, dynamic> data = jsonDecode(utf8.decode(bytes));
    return _buildPreview(data, fileName);
  }

  Future<ImportPreview> _buildPreview(
      Map<String, dynamic> data, String fileName) async {
    int errors = 0;
    int duplicates = 0;
    int newCustomers = 0;

    final existingCustomerIds =
        (await DbService.instance.getCustomers()).map((c) => c.id).toSet();
    final existingProductIds =
        (await DbService.instance.getProducts()).map((p) => p.id).toSet();
    final existingInvoiceIds =
        (await DbService.instance.getInvoices()).map((i) => i.id).toSet();
    final existingReceiptIds =
        (await DbService.instance.getReceipts()).map((r) => r.id).toSet();

    final customers = <Customer>[];
    for (final e in (data['customers'] as List? ?? [])) {
      try {
        final c = Customer.fromMap(Map<String, dynamic>.from(e as Map));
        customers.add(c);
        existingCustomerIds.contains(c.id) ? duplicates++ : newCustomers++;
      } catch (_) {
        errors++;
      }
    }

    final products = <Product>[];
    for (final e in (data['products'] as List? ?? [])) {
      try {
        final p = Product.fromMap(Map<String, dynamic>.from(e as Map));
        products.add(p);
        if (existingProductIds.contains(p.id)) duplicates++;
      } catch (_) {
        errors++;
      }
    }

    final invoices = <Invoice>[];
    for (final e in (data['invoices'] as List? ?? [])) {
      try {
        final inv = Invoice.fromMap(Map<String, dynamic>.from(e as Map));
        invoices.add(inv);
        if (existingInvoiceIds.contains(inv.id)) duplicates++;
      } catch (_) {
        errors++;
      }
    }

    final receipts = <Receipt>[];
    for (final e in (data['receipts'] as List? ?? [])) {
      try {
        final r = Receipt.fromMap(Map<String, dynamic>.from(e as Map));
        receipts.add(r);
        if (existingReceiptIds.contains(r.id)) duplicates++;
      } catch (_) {
        errors++;
      }
    }

    return ImportPreview(
      customers: customers,
      products: products,
      invoices: invoices,
      receipts: receipts,
      newCustomersCount: newCustomers,
      duplicatesCount: duplicates,
      errorsCount: errors,
      repId: data['repId'] as String? ?? '',
      repDisplayName: data['repDisplayName'] as String? ?? 'غير معروف',
      fileName: fileName,
    );
  }

  /// يعتمد الاستيراد: يكتب كل السجلات (upsert) بحالة "متزامن" من منظور
  /// المدير، يسجّل العملية في سجل المزامنة، يحدّث آخر مزامنة لحساب
  /// المندوب المطابق إن وُجد لدى المدير، ويعيد نص ملف تأكيد الاستلام
  Future<String> commitImport(ImportPreview preview) async {
    for (final c in preview.customers) {
      c.syncStatus = SyncStatus.synced;
      await DbService.instance.upsertCustomer(c);
    }
    for (final p in preview.products) {
      p.syncStatus = SyncStatus.synced;
      await DbService.instance.upsertProduct(p);
    }
    for (final inv in preview.invoices) {
      inv.syncStatus = SyncStatus.synced;
      await DbService.instance.upsertInvoice(inv);
      await NumberingService.instance.commitUsedNumber(
          inv.kind == InvoiceKind.sale ? 'sale' : 'return', inv.docNumber);
    }
    for (final r in preview.receipts) {
      r.syncStatus = SyncStatus.synced;
      await DbService.instance.upsertReceipt(r);
      await NumberingService.instance.commitUsedNumber('receipt', r.docNumber);
    }

    if (preview.repId.isNotEmpty) {
      final users = await DbService.instance.getUsers();
      for (final u in users) {
        if (u.id == preview.repId) {
          u.lastSyncAt = DateTime.now();
          await AccountService.instance.updateUser(u);
          break;
        }
      }
    }

    await DbService.instance.addSyncLogEntry(SyncLogEntry(
      id: _uuid.v4(),
      fileName: preview.fileName,
      repId: preview.repId,
      repDisplayName: preview.repDisplayName,
      importedAt: DateTime.now(),
      customersCount: preview.customers.length,
      productsCount: preview.products.length,
      invoicesCount: preview.invoicesCount,
      receiptsCount: preview.receiptsCount,
      duplicatesCount: preview.duplicatesCount,
      errorsCount: preview.errorsCount,
    ));

    return _buildAckJson(preview);
  }

  String _buildAckJson(ImportPreview preview) {
    final ack = {
      'type': 'sync_ack',
      'confirmedAt': DateTime.now().toIso8601String(),
      'repId': preview.repId,
      'syncedIds': {
        'customers': preview.customers.map((e) => e.id).toList(),
        'products': preview.products.map((e) => e.id).toList(),
        'invoices': preview.invoices.map((e) => e.id).toList(),
        'receipts': preview.receipts.map((e) => e.id).toList(),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(ack);
  }

  Future<void> shareAck(String ackJson, String repDisplayName) async {
    final bytes = Uint8List.fromList(utf8.encode(ackJson));
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    await ShareUtil.shareBytes(
      bytes,
      'kady_ack_${repDisplayName}_$stamp.json',
      mimeType: 'application/json',
      text: 'تأكيد استلام مزامنة - $repDisplayName',
    );
  }

  Future<List<SyncLogEntry>> getLog() => DbService.instance.getSyncLog();

  /// ينشئ ملف "تحديث" يحتوي أي مزيج من المنتجات/العملاء/الإعدادات
  /// (بيانات الشركة الأساسية فقط، وليس تفضيلات الجهاز الشخصية كالطابعة
  /// أو المظهر)، ويسجّله في سجل التصدير. targetRepId فارغ يعني كل
  /// المندوبين — الملف نفسه لا يتغير حسب الهدف، فقط تسميته وسجلّه
  Future<String> buildUpdatePackage({
    required bool includeProducts,
    required bool includeCustomers,
    required bool includeSettings,
    required String targetRepId,
    required String targetLabel,
  }) async {
    final payload = <String, dynamic>{
      'type': 'update_package',
      'createdAt': DateTime.now().toIso8601String(),
      'targetRepId': targetRepId,
    };
    int productsCount = 0;
    int customersCount = 0;

    if (includeProducts) {
      final products = await DbService.instance.getProducts();
      payload['products'] = products.map((p) => p.toMap()).toList();
      productsCount = products.length;
    }
    if (includeCustomers) {
      final customers = await DbService.instance.getCustomers();
      payload['customers'] = customers.map((c) => c.toMap()).toList();
      customersCount = customers.length;
    }
    if (includeSettings) {
      final s = await SettingsService.instance.load();
      payload['settings'] = {
        'companyName': s.companyName,
        'companyPhone': s.companyPhone,
        'companyAddress': s.companyAddress,
        'invoiceFooterText': s.invoiceFooterText,
      };
    }

    await DbService.instance.addExportLogEntry(ExportLogEntry(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      targetLabel: targetLabel,
      includedProducts: includeProducts,
      includedCustomers: includeCustomers,
      includedSettings: includeSettings,
      productsCount: productsCount,
      customersCount: customersCount,
    ));

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> shareUpdatePackage(String json, String targetLabel) async {
    final bytes = Uint8List.fromList(utf8.encode(json));
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    await ShareUtil.shareBytes(
      bytes,
      'kady_update_${targetLabel}_$stamp.json',
      mimeType: 'application/json',
      text: 'تحديث بيانات - $targetLabel',
    );
  }

  Future<List<ExportLogEntry>> getExportLog() => DbService.instance.getExportLog();
}
