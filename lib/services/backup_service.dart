import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/company_settings.dart';
import 'db_service.dart';
import 'settings_service.dart';
import 'numbering_service.dart';
import 'share_util.dart';

/// مصدر إنشاء النسخة: يدوي (زر "نسخ احتياطي فوري") أو تلقائي (فحص عند
/// فتح التطبيق حسب الجدولة). يُستخدم فقط لعرض تصنيف صحيح بقائمة النسخ —
/// لا يُغيّر آلية الاستعادة أو المشاركة، فكلاهما JSON بنفس البنية تمامًا
enum BackupSource { manual, auto }

/// سجل نسخة احتياطية واحدة — يُخزَّن محتواه كاملًا محليًا (Hive) حتى تصير
/// النسخ الاحتياطية قائمة واحدة موحّدة (يدوية وتلقائية معًا) تقدر تستعرضها
/// وتستعيد أو تشارك أي وحدة منها بضغطة، بدل عملية "أنشئ وشارك فورًا" لمرة
/// وحدة بلا أي أثر بعدها.
class BackupRecord {
  final String id;
  final String fileName;
  final DateTime createdAt;
  final int sizeBytes;
  final String jsonContent;
  final BackupSource source;

  BackupRecord({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
    required this.jsonContent,
    this.source = BackupSource.manual,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'createdAt': createdAt.toIso8601String(),
        'sizeBytes': sizeBytes,
        'jsonContent': jsonContent,
        'source': source.name,
      };

  factory BackupRecord.fromMap(Map<String, dynamic> m) => BackupRecord(
        id: m['id'] as String,
        fileName: m['fileName'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        sizeBytes: m['sizeBytes'] as int,
        jsonContent: m['jsonContent'] as String,
        // النسخ المحفوظة قبل إضافة هذا الحقل ليس لها 'source' بالخريطة —
        // نفترضها يدوية افتراضيًا بدل رمي استثناء عليها
        source: BackupSource.values.firstWhere(
          (s) => s.name == m['source'],
          orElse: () => BackupSource.manual,
        ),
      );

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes بايت';
    return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
  }
}

/// نسخ احتياطي كامل لكل بيانات التطبيق (عملاء، منتجات، فواتير، سندات،
/// إعدادات) إلى JSON يمكن مشاركته أو حفظه (Google Drive، بريد، واتساب...)،
/// مع إمكانية استيراده لاحقًا على نفس الجهاز أو جهاز آخر. كل شيء يعمل في
/// الذاكرة (بدون كتابة ملفات على القرص) حتى يعمل على الجوال والويب معًا.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _formatVersion = 1;
  static const _logBoxName = 'backup_log';
  static const _maxKeptBackups = 15;
  final _uuid = const Uuid();

  Box? _logBox;
  Future<Box> get _log async {
    if (_logBox != null) return _logBox!;
    _logBox = await Hive.openBox(_logBoxName);
    return _logBox!;
  }

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

  /// يبني النسخة الاحتياطية، يحفظها بسجل محلي متصفَّح (راجع listBackups)،
  /// ثم يفتح واجهة المشاركة (حفظ في Drive / واتساب / بريد... أو تنزيل
  /// مباشر على الويب) — نفس السلوك السابق بالضبط، بإضافة الحفظ بالسجل فقط
  Future<void> exportAndShare() async {
    final record = await _createBackupRecord();
    final bytes = Uint8List.fromList(utf8.encode(record.jsonContent));
    await ShareUtil.shareBytes(bytes, record.fileName,
        mimeType: 'application/json',
        text: 'نسخة احتياطية - تطبيق كادي للمنظفات');
  }

  /// يبني نسخة احتياطية ويحفظها بالسجل المحلي بدون فتح أي واجهة مشاركة —
  /// تُستخدم من شاشة "إدارة النسخ الاحتياطية" (زر إنشاء، source: manual)
  /// وأيضًا من النسخ التلقائي الدوري (source: auto) — كلاهما بنفس السجل
  /// الموحّد الآن حتى تظهر النسخ التلقائية بنفس القائمة القابلة للاستعراض
  Future<BackupRecord> _createBackupRecord({BackupSource source = BackupSource.manual}) async {
    final json = await exportToJsonString();
    final record = BackupRecord(
      id: _uuid.v4(),
      fileName: _backupFileName(),
      createdAt: DateTime.now(),
      sizeBytes: utf8.encode(json).length,
      jsonContent: json,
      source: source,
    );
    final box = await _log;
    await box.put(record.id, record.toMap());
    await _pruneOldBackups(box);
    return record;
  }

  /// نسخة عامة من _createBackupRecord لاستخدام شاشة الإدارة والنسخ التلقائي
  Future<BackupRecord> createBackupRecord({BackupSource source = BackupSource.manual}) =>
      _createBackupRecord(source: source);

  Future<void> _pruneOldBackups(Box box) async {
    if (box.length <= _maxKeptBackups) return;
    final records = box.values
        .map((v) => BackupRecord.fromMap(Map<String, dynamic>.from(v)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final old in records.skip(_maxKeptBackups)) {
      await box.delete(old.id);
    }
  }

  /// كل النسخ الاحتياطية المحفوظة محليًا، الأحدث أولًا
  Future<List<BackupRecord>> listBackups() async {
    final box = await _log;
    final records = box.values
        .map((v) => BackupRecord.fromMap(Map<String, dynamic>.from(v)))
        .toList();
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  Future<void> deleteBackup(String id) async {
    final box = await _log;
    await box.delete(id);
  }

  Future<void> shareBackup(BackupRecord record) async {
    final bytes = Uint8List.fromList(utf8.encode(record.jsonContent));
    await ShareUtil.shareBytes(bytes, record.fileName,
        mimeType: 'application/json',
        text: 'نسخة احتياطية - تطبيق كادي للمنظفات');
  }

  Future<void> restoreBackup(BackupRecord record) => importFromJson(record.jsonContent);

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
