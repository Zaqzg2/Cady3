import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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

/// سجل عملية تصدير واحدة أُرسلت فعليًا — يبقى محفوظًا محليًا بعد اختفاء
/// رسالة النجاح، فيصير "الصادر" قائمة حقيقية تتصفّحها وتعيد مشاركة أي
/// دفعة سابقة منها بضغطة، بدل أن يتذكّر التطبيق آخر ملف فقط
class OutboxRecord {
  final String id;
  final String fileName;
  final DateTime createdAt;
  final String jsonContent;
  final int customersCount;
  final int productsCount;
  final int invoicesCount;
  final int receiptsCount;

  OutboxRecord({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.jsonContent,
    required this.customersCount,
    required this.productsCount,
    required this.invoicesCount,
    required this.receiptsCount,
  });

  int get totalRecords =>
      customersCount + productsCount + invoicesCount + receiptsCount;

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'createdAt': createdAt.toIso8601String(),
        'jsonContent': jsonContent,
        'customersCount': customersCount,
        'productsCount': productsCount,
        'invoicesCount': invoicesCount,
        'receiptsCount': receiptsCount,
      };

  factory OutboxRecord.fromMap(Map<String, dynamic> m) => OutboxRecord(
        id: m['id'] as String,
        fileName: m['fileName'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        jsonContent: m['jsonContent'] as String,
        customersCount: m['customersCount'] as int? ?? 0,
        productsCount: m['productsCount'] as int? ?? 0,
        invoicesCount: m['invoicesCount'] as int? ?? 0,
        receiptsCount: m['receiptsCount'] as int? ?? 0,
      );
}

/// سجل ملف وارد عُولج بنجاح (تأكيد مزامنة أو حزمة تحديث) — أثر يبقى
/// يمكن مراجعته لاحقًا لمعرفة "هل استوردت هذا فعلًا ومتى؟". لا يشمل
/// ملفات لم تُفتح بعد، لأن التطبيق لا يعرف بوجودها قبل أن يختارها
/// المستخدم يدويًا عبر منتقي الملفات
class InboxRecord {
  final String id;
  final DateTime receivedAt;
  final String type; // sync_ack | update_package
  final String summary;

  InboxRecord({
    required this.id,
    required this.receivedAt,
    required this.type,
    required this.summary,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'receivedAt': receivedAt.toIso8601String(),
        'type': type,
        'summary': summary,
      };

  factory InboxRecord.fromMap(Map<String, dynamic> m) => InboxRecord(
        id: m['id'] as String,
        receivedAt: DateTime.parse(m['receivedAt'] as String),
        type: m['type'] as String,
        summary: m['summary'] as String,
      );
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

  static const _outboxBoxName = 'sync_outbox_log';
  static const _inboxBoxName = 'sync_inbox_log';
  static const _maxKeptHistory = 30;
  final _uuid = const Uuid();

  Box? _outboxBox;
  Future<Box> get _outbox async {
    _outboxBox ??= await Hive.openBox(_outboxBoxName);
    return _outboxBox!;
  }

  Box? _inboxBox;
  Future<Box> get _inbox async {
    _inboxBox ??= await Hive.openBox(_inboxBoxName);
    return _inboxBox!;
  }

  Future<void> _saveOutboxRecord(SyncExportResult result) async {
    final record = OutboxRecord(
      id: _uuid.v4(),
      fileName: result.fileName,
      createdAt: DateTime.now(),
      jsonContent: result.json,
      customersCount: result.summary.customers.length,
      productsCount: result.summary.products.length,
      invoicesCount: result.summary.invoices.length,
      receiptsCount: result.summary.receipts.length,
    );
    final box = await _outbox;
    await box.put(record.id, record.toMap());
    await _pruneOutbox(box);
  }

  Future<void> _pruneOutbox(Box box) async {
    if (box.length <= _maxKeptHistory) return;
    final records = box.values
        .map((v) => OutboxRecord.fromMap(Map<String, dynamic>.from(v)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final old in records.skip(_maxKeptHistory)) {
      await box.delete(old.id);
    }
  }

  /// كل عمليات التصدير المُرسلة سابقًا، الأحدث أولًا
  Future<List<OutboxRecord>> listOutbox() async {
    final box = await _outbox;
    final records = box.values
        .map((v) => OutboxRecord.fromMap(Map<String, dynamic>.from(v)))
        .toList();
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  /// يعيد مشاركة دفعة صادرة سابقة بعينها (مو الأخيرة بالضرورة) دون
  /// توليدها من جديد
  Future<void> reShareOutboxRecord(OutboxRecord record) async {
    final bytes = Uint8List.fromList(utf8.encode(record.jsonContent));
    await ShareUtil.shareBytes(bytes, record.fileName,
        mimeType: 'application/json', text: 'إعادة إرسال ملف مزامنة');
  }

  Future<void> _saveInboxRecord(String type, String summary) async {
    final record = InboxRecord(
      id: _uuid.v4(),
      receivedAt: DateTime.now(),
      type: type,
      summary: summary,
    );
    final box = await _inbox;
    await box.put(record.id, record.toMap());
    await _pruneInbox(box);
  }

  Future<void> _pruneInbox(Box box) async {
    if (box.length <= _maxKeptHistory) return;
    final records = box.values
        .map((v) => InboxRecord.fromMap(Map<String, dynamic>.from(v)))
        .toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    for (final old in records.skip(_maxKeptHistory)) {
      await box.delete(old.id);
    }
  }

  /// كل الملفات الواردة التي عُولجت بنجاح سابقًا، الأحدث أولًا
  Future<List<InboxRecord>> listInbox() async {
    final box = await _inbox;
    final records = box.values
        .map((v) => InboxRecord.fromMap(Map<String, dynamic>.from(v)))
        .toList();
    records.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return records;
  }

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
    await _saveOutboxRecord(result);
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
      await _saveInboxRecord('sync_ack', 'تأكيد مزامنة — $count عملية اعتُمدت');
      return IncomingSyncResult(type: 'sync_ack', ackedCount: count);
    }
    if (type == 'update_package') {
      final result = await _applyUpdatePackage(data);
      await _saveInboxRecord(
        'update_package',
        'تحديث — ${result.productsUpdated} منتج، ${result.customersUpdated} عميل'
            '${result.settingsUpdated ? '، وبيانات الشركة' : ''}',
      );
      return result;
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
