import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/user_account.dart';
import '../models/sync_log_entry.dart';
import '../models/export_log_entry.dart';

/// طبقة الوصول لقاعدة بيانات التطبيق — Hive بالكامل (nosql محلي سريع
/// يعمل بنفس الطريقة على الجوال والويب عبر IndexedDB). كل سجل يُخزَّن
/// كـ Map بنفس صيغة toMap()/fromMap() الموجودة أصلاً بكل موديل، بالمفتاح
/// id — بدون أي TypeAdapter لأن كل القيم أصلاً أنواع أساسية
/// (String/num/bool/List/Map) يدعمها Hive مباشرة.
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  /// إصدار مخطط قاعدة البيانات — يُعرض في شاشة المزامنة عند المندوب
  static const int schemaVersion = 1;

  static const _customersBoxName = 'customers';
  static const _productsBoxName = 'products';
  static const _invoicesBoxName = 'invoices';
  static const _receiptsBoxName = 'receipts';
  static const _usersBoxName = 'users';
  static const _syncLogBoxName = 'sync_log';
  static const _exportLogBoxName = 'export_log';

  bool _ready = false;
  late Box _customersBox;
  late Box _productsBox;
  late Box _invoicesBox;
  late Box _receiptsBox;
  late Box _usersBox;
  late Box _syncLogBox;
  late Box _exportLogBox;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await Hive.initFlutter();
    _customersBox = await Hive.openBox(_customersBoxName);
    _productsBox = await Hive.openBox(_productsBoxName);
    _invoicesBox = await Hive.openBox(_invoicesBoxName);
    _receiptsBox = await Hive.openBox(_receiptsBoxName);
    _usersBox = await Hive.openBox(_usersBoxName);
    _syncLogBox = await Hive.openBox(_syncLogBoxName);
    _exportLogBox = await Hive.openBox(_exportLogBoxName);
    _ready = true;
  }

  /// يحوّل أي Map يعيدها Hive (قد تكون Map<dynamic, dynamic> وقت التشغيل)
  /// إلى Map<String, dynamic> التي تتوقعها دوال fromMap() في كل موديل
  Map<String, dynamic> _asStringMap(dynamic raw) =>
      Map<String, dynamic>.from(raw as Map);

  // ---------------- العملاء ----------------
  Future<void> upsertCustomer(Customer c) async {
    await _ensureReady();
    await _customersBox.put(c.id, c.toMap());
  }

  Future<void> deleteCustomer(String id) async {
    await _ensureReady();
    await _customersBox.delete(id);
  }

  Future<List<Customer>> getCustomers() async {
    await _ensureReady();
    final list = _customersBox.values
        .map((v) => Customer.fromMap(_asStringMap(v)))
        .toList();
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  // ---------------- المنتجات ----------------
  Future<void> upsertProduct(Product p) async {
    await _ensureReady();
    await _productsBox.put(p.id, p.toMap());
  }

  Future<void> deleteProduct(String id) async {
    await _ensureReady();
    await _productsBox.delete(id);
  }

  Future<List<Product>> getProducts() async {
    await _ensureReady();
    final list =
        _productsBox.values.map((v) => Product.fromMap(_asStringMap(v))).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // ---------------- الفواتير ----------------
  Future<void> upsertInvoice(Invoice inv) async {
    await _ensureReady();
    await _invoicesBox.put(inv.id, inv.toMap());
  }

  Future<void> deleteInvoice(String id) async {
    await _ensureReady();
    await _invoicesBox.delete(id);
  }

  Future<List<Invoice>> getInvoices({String? customerId}) async {
    await _ensureReady();
    var list =
        _invoicesBox.values.map((v) => Invoice.fromMap(_asStringMap(v))).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    if (customerId != null) {
      list = list.where((i) => i.customerId == customerId).toList();
    }
    return list;
  }

  Future<Invoice?> getInvoiceById(String id) async {
    await _ensureReady();
    final v = _invoicesBox.get(id);
    if (v == null) return null;
    return Invoice.fromMap(_asStringMap(v));
  }

  // ---------------- السندات ----------------
  Future<void> upsertReceipt(Receipt r) async {
    await _ensureReady();
    await _receiptsBox.put(r.id, r.toMap());
  }

  Future<void> deleteReceipt(String id) async {
    await _ensureReady();
    await _receiptsBox.delete(id);
  }

  Future<List<Receipt>> getReceipts({String? customerId}) async {
    await _ensureReady();
    var list =
        _receiptsBox.values.map((v) => Receipt.fromMap(_asStringMap(v))).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    if (customerId != null) {
      list = list.where((r) => r.customerId == customerId).toList();
    }
    return list;
  }

  Future<Receipt?> getReceiptById(String id) async {
    await _ensureReady();
    final v = _receiptsBox.get(id);
    if (v == null) return null;
    return Receipt.fromMap(_asStringMap(v));
  }

  // ---------------- المستخدمون (حسابات مدير/مندوب) ----------------
  Future<void> upsertUser(UserAccount u) async {
    await _ensureReady();
    await _usersBox.put(u.id, u.toMap());
  }

  Future<void> deleteUser(String id) async {
    await _ensureReady();
    await _usersBox.delete(id);
  }

  Future<List<UserAccount>> getUsers() async {
    await _ensureReady();
    final list = _usersBox.values
        .map((v) => UserAccount.fromMap(_asStringMap(v)))
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  // ---------------- سجل المزامنة (جانب المدير) ----------------
  Future<void> addSyncLogEntry(SyncLogEntry e) async {
    await _ensureReady();
    await _syncLogBox.put(e.id, e.toMap());
  }

  Future<List<SyncLogEntry>> getSyncLog() async {
    await _ensureReady();
    final list = _syncLogBox.values
        .map((v) => SyncLogEntry.fromMap(_asStringMap(v)))
        .toList();
    list.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return list;
  }

  // ---------------- سجل التصدير (جانب المدير) ----------------
  Future<void> addExportLogEntry(ExportLogEntry e) async {
    await _ensureReady();
    await _exportLogBox.put(e.id, e.toMap());
  }

  Future<List<ExportLogEntry>> getExportLog() async {
    await _ensureReady();
    final list = _exportLogBox.values
        .map((v) => ExportLogEntry.fromMap(_asStringMap(v)))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ---------------- حساب رصيد العميل ----------------
  Future<double> getCustomerBalance(String customerId, double openingBalance) async {
    final invoices = await getInvoices(customerId: customerId);
    final receipts = await getReceipts(customerId: customerId);
    double balance = openingBalance;
    for (final inv in invoices) {
      balance += inv.effect;
    }
    for (final r in receipts) {
      balance -= r.amount;
    }
    return balance;
  }
}
