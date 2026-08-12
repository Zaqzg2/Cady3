import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/company_settings.dart';
import '../models/ledger_entry.dart';
import '../models/customer_stats.dart';
import '../models/user_account.dart';
import '../models/sync_status.dart';
import '../services/db_service.dart';
import '../services/numbering_service.dart';
import '../services/settings_service.dart';
import '../services/auto_backup_service.dart';
import '../services/account_service.dart';
import '../services/sync_service.dart';

/// المزوّد المركزي لحالة التطبيق: عملاء، منتجات، إعدادات، وعمليات
/// حفظ الفواتير/السندات مع حساب المديونية والترقيم التلقائي
class AppProvider extends ChangeNotifier {
  final _uuid = const Uuid();

  List<Customer> customers = [];
  List<Product> products = [];
  CompanySettings settings = CompanySettings();
  bool loading = true;
  String? initError;
  UserAccount? currentUser;
  bool usersExist = false;

  Future<void> init() async {
    loading = true;
    initError = null;
    notifyListeners();
    try {
      customers = await DbService.instance.getCustomers();
      products = await DbService.instance.getProducts();
      settings = await SettingsService.instance.load();
      usersExist = await AccountService.instance.hasAnyUsers();
      currentUser = await AccountService.instance.getCurrentUser();
      // نسخ احتياطي تلقائي (يومي/أسبوعي) إن كان مفعّلاً وحان وقته — فشله
      // لا يجب أن يمنع فتح التطبيق، لذا يُعالَج بصمت داخليًا
      unawaited(AutoBackupService.runIfDue(settings));
    } catch (e, st) {
      // نطبع الخطأ بالتفصيل في السجل (logcat) ونحفظه لعرضه في الواجهة أيضاً
      // بدل ترك المستخدم أمام شاشة بيضاء بلا أي توضيح لسبب التعليق.
      debugPrint('AppProvider.init() failed: $e');
      debugPrint('$st');
      initError = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  // ---------------- حسابات المستخدمين (مدير/مندوب) ----------------
  /// ينشئ أول حساب على الجهاز — يكون مديرًا دائمًا، ويبدأ جلسته فورًا
  Future<UserAccount> createFirstManager({
    required String username,
    required String rawPassword,
    required String displayName,
  }) async {
    final manager = await AccountService.instance.createUser(
      username: username,
      rawPassword: rawPassword,
      displayName: displayName,
      role: UserRole.manager,
    );
    await AccountService.instance.setSession(manager.id);
    usersExist = true;
    currentUser = manager;
    notifyListeners();
    return manager;
  }

  Future<bool> login(String username, String password) async {
    final user = await AccountService.instance.login(username, password);
    if (user == null) return false;
    currentUser = user;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    await AccountService.instance.logout();
    currentUser = null;
    notifyListeners();
  }

  Future<List<UserAccount>> getAllUsers() => AccountService.instance.getUsers();

  Future<bool> isUsernameTaken(String username, {String? excludingId}) =>
      AccountService.instance.isUsernameTaken(username, excludingId: excludingId);

  Future<UserAccount> addUser({
    required String username,
    required String rawPassword,
    required String displayName,
    required UserRole role,
    String repNumber = '',
  }) async {
    final user = await AccountService.instance.createUser(
      username: username,
      rawPassword: rawPassword,
      displayName: displayName,
      role: role,
      repNumber: repNumber,
    );
    notifyListeners();
    return user;
  }

  Future<void> updateUserAccount(UserAccount user) async {
    await AccountService.instance.updateUser(user);
    if (currentUser?.id == user.id) currentUser = user;
    notifyListeners();
  }

  Future<void> setUserPassword(UserAccount user, String rawPassword) async {
    await AccountService.instance.setPassword(user, rawPassword);
    notifyListeners();
  }

  Future<void> toggleUserActive(UserAccount user) async {
    user.isActive = !user.isActive;
    await AccountService.instance.updateUser(user);
    notifyListeners();
  }

  // ---------------- مزامنة (جانب المندوب) ----------------
  Future<PendingSummary> getPendingSyncSummary() =>
      SyncService.instance.getPendingSummary();

  Future<SyncExportResult> exportPendingData() async {
    final rep = currentUser;
    if (rep == null) throw StateError('لا يوجد مستخدم مسجّل الدخول');
    final result = await SyncService.instance.exportAndShare(rep);
    rep.lastSyncAt = DateTime.now();
    await AccountService.instance.updateUser(rep);
    notifyListeners();
    return result;
  }

  Future<({String json, String fileName, DateTime at})?> getLastExport() =>
      SyncService.instance.getLastExport();

  Future<bool> reExportLastSync() => SyncService.instance.reExportLast();

  Future<String?> pickSyncAckFile() => SyncService.instance.pickAckFile();

  /// يطبّق ملفًا واردًا من المدير (تأكيد مزامنة أو حزمة تحديث)، ثم يعيد
  /// تحميل العملاء/المنتجات (والإعدادات إن تغيّرت) من القرص حتى لا تبقى
  /// النسخة المحمَّلة في الذاكرة قديمة بعد كتابة SyncService مباشرة لها
  Future<IncomingSyncResult> importIncomingSyncFile(String jsonContent) async {
    final result = await SyncService.instance.importIncomingFile(jsonContent);
    customers = await DbService.instance.getCustomers();
    products = await DbService.instance.getProducts();
    if (result.settingsUpdated) {
      settings = await SettingsService.instance.load();
    }
    notifyListeners();
    return result;
  }

  Future<void> refreshCustomersAndProducts() async {
    customers = await DbService.instance.getCustomers();
    products = await DbService.instance.getProducts();
    notifyListeners();
  }

  Future<void> updateCurrentDeviceName(String name) async {
    final user = currentUser;
    if (user == null) return;
    user.deviceName = name.trim();
    await AccountService.instance.updateUser(user);
    notifyListeners();
  }

  // ---------------- عملاء ----------------
  Future<void> saveCustomer(Customer c) async {
    c.syncStatus = SyncStatus.pending;
    c.updatedAt = DateTime.now();
    await DbService.instance.upsertCustomer(c);
    customers = await DbService.instance.getCustomers();
    notifyListeners();
  }

  Future<void> deleteCustomer(String id) async {
    await DbService.instance.deleteCustomer(id);
    customers = await DbService.instance.getCustomers();
    notifyListeners();
  }

  Customer newCashCustomer() => Customer(id: _uuid.v4(), name: 'عميل نقدي');

  Future<void> togglePinCustomer(String id) async {
    final idx = customers.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    customers[idx].isPinned = !customers[idx].isPinned;
    await DbService.instance.upsertCustomer(customers[idx]);
    customers = await DbService.instance.getCustomers();
    notifyListeners();
  }

  /// ملخّص محسوب للعميل: الرصيد، عدد الفواتير، إجمالي المقبوض والمرتجع،
  /// وتاريخ آخر نشاط ورقم آخر فاتورة — تُستخدم في بطاقة العميل وصفحته
  Future<CustomerStats> getCustomerStats(String customerId) async {
    final c = customers.firstWhere((c) => c.id == customerId,
        orElse: () => Customer(id: customerId, name: ''));
    final invoices = await DbService.instance.getInvoices(customerId: customerId);
    final receipts = await DbService.instance.getReceipts(customerId: customerId);

    double balance = c.openingBalance;
    double received = 0;
    double returns = 0;
    int salesCount = 0;
    DateTime? lastActivity;
    String? lastInvoiceNumber;
    DateTime? lastInvoiceDate;

    for (final inv in invoices) {
      balance += inv.effect;
      if (inv.kind == InvoiceKind.sale) salesCount++;
      if (inv.kind == InvoiceKind.saleReturn) returns += inv.grandTotal;
      if (lastActivity == null || inv.date.isAfter(lastActivity)) {
        lastActivity = inv.date;
      }
      if (lastInvoiceDate == null || inv.date.isAfter(lastInvoiceDate)) {
        lastInvoiceDate = inv.date;
        lastInvoiceNumber = inv.docNumber;
      }
    }
    for (final r in receipts) {
      balance -= r.amount;
      received += r.amount;
      if (lastActivity == null || r.date.isAfter(lastActivity)) {
        lastActivity = r.date;
      }
    }

    return CustomerStats(
      balance: balance,
      invoicesCount: salesCount,
      receivedTotal: received,
      returnsTotal: returns,
      lastActivityDate: lastActivity,
      lastInvoiceNumber: lastInvoiceNumber,
      lastInvoiceDate: lastInvoiceDate,
    );
  }

  // ---------------- منتجات ----------------
  Future<void> saveProduct(Product p) async {
    p.syncStatus = SyncStatus.pending;
    p.updatedAt = DateTime.now();
    await DbService.instance.upsertProduct(p);
    products = await DbService.instance.getProducts();
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    await DbService.instance.deleteProduct(id);
    products = await DbService.instance.getProducts();
    notifyListeners();
  }

  // ---------------- إعدادات ----------------
  Future<void> saveSettings(CompanySettings s) async {
    settings = s;
    await SettingsService.instance.save(s);
    notifyListeners();
  }

  // ---------------- ترقيم المستندات ----------------
  Future<String> peekNextInvoiceNumber(InvoiceKind kind) {
    return NumberingService.instance
        .peekNextNumber(kind == InvoiceKind.sale ? 'sale' : 'return');
  }

  Future<String> peekNextReceiptNumber() {
    return NumberingService.instance.peekNextNumber('receipt');
  }

  // ---------------- رصيد العميل ----------------
  Future<double> getCustomerBalance(String customerId) async {
    final c = customers.firstWhere((c) => c.id == customerId,
        orElse: () => Customer(id: customerId, name: ''));
    return DbService.instance.getCustomerBalance(customerId, c.openingBalance);
  }

  /// يحسب الرصيد بعد استبعاد مستند مُعيَّن قيد التعديل حاليًا (لتفادي احتساب
  /// المستند مرتين عند إعادة حفظه)
  Future<double> getCustomerBalanceExcluding(
      String customerId, {String? excludeInvoiceId, String? excludeReceiptId}) async {
    final c = customers.firstWhere((c) => c.id == customerId,
        orElse: () => Customer(id: customerId, name: ''));
    final invoices = await DbService.instance.getInvoices(customerId: customerId);
    final receipts = await DbService.instance.getReceipts(customerId: customerId);
    double balance = c.openingBalance;
    for (final inv in invoices) {
      if (inv.id == excludeInvoiceId) continue;
      balance += inv.effect;
    }
    for (final r in receipts) {
      if (r.id == excludeReceiptId) continue;
      balance -= r.amount;
    }
    return balance;
  }

  // ---------------- حفظ فاتورة ----------------
  Future<void> saveInvoice(Invoice inv) async {
    final baseBalance = await getCustomerBalanceExcluding(inv.customerId,
        excludeInvoiceId: inv.id);
    inv.balanceAfter = baseBalance + inv.effect;
    inv.syncStatus = SyncStatus.pending;
    inv.updatedAt = DateTime.now();
    await DbService.instance.upsertInvoice(inv);
    await NumberingService.instance
        .commitUsedNumber(inv.kind == InvoiceKind.sale ? 'sale' : 'return',
            inv.docNumber);
    notifyListeners();
  }

  Future<void> deleteInvoice(String id) async {
    await DbService.instance.deleteInvoice(id);
    notifyListeners();
  }

  Future<Invoice?> getInvoiceById(String id) => DbService.instance.getInvoiceById(id);
  Future<Receipt?> getReceiptById(String id) => DbService.instance.getReceiptById(id);

  /// تعليم فاتورة/سند كمطبوع أو كمُشارَك، أو تثبيته أعلى سجل المستندات —
  /// بدون إعادة حساب الرصيد (على عكس saveInvoice/saveReceipt)
  Future<void> markInvoicePrinted(String id) async {
    final inv = await DbService.instance.getInvoiceById(id);
    if (inv == null) return;
    inv.isPrinted = true;
    await DbService.instance.upsertInvoice(inv);
    notifyListeners();
  }

  Future<void> markInvoiceShared(String id) async {
    final inv = await DbService.instance.getInvoiceById(id);
    if (inv == null) return;
    inv.isShared = true;
    await DbService.instance.upsertInvoice(inv);
    notifyListeners();
  }

  Future<void> toggleInvoicePinned(String id) async {
    final inv = await DbService.instance.getInvoiceById(id);
    if (inv == null) return;
    inv.isPinned = !inv.isPinned;
    await DbService.instance.upsertInvoice(inv);
    notifyListeners();
  }

  Future<void> markReceiptPrinted(String id) async {
    final r = await DbService.instance.getReceiptById(id);
    if (r == null) return;
    r.isPrinted = true;
    await DbService.instance.upsertReceipt(r);
    notifyListeners();
  }

  Future<void> markReceiptShared(String id) async {
    final r = await DbService.instance.getReceiptById(id);
    if (r == null) return;
    r.isShared = true;
    await DbService.instance.upsertReceipt(r);
    notifyListeners();
  }

  Future<void> toggleReceiptPinned(String id) async {
    final r = await DbService.instance.getReceiptById(id);
    if (r == null) return;
    r.isPinned = !r.isPinned;
    await DbService.instance.upsertReceipt(r);
    notifyListeners();
  }

  /// آخر N عملية (فواتير + سندات) عبر كل العملاء، مرتبة تنازليًا حسب التاريخ
  Future<List<dynamic>> getRecentDocuments({int limit = 5}) async {
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();
    final all = <dynamic>[...invoices, ...receipts];
    all.sort((a, b) {
      final da = a is Invoice ? a.date : (a as Receipt).date;
      final db = b is Invoice ? b.date : (b as Receipt).date;
      return db.compareTo(da);
    });
    return all.take(limit).toList();
  }

  // ---------------- حفظ سند قبض ----------------
  Future<void> saveReceipt(Receipt r) async {
    final baseBalance =
        await getCustomerBalanceExcluding(r.customerId, excludeReceiptId: r.id);
    r.balanceAfter = baseBalance - r.amount;
    r.syncStatus = SyncStatus.pending;
    r.updatedAt = DateTime.now();
    await DbService.instance.upsertReceipt(r);
    await NumberingService.instance.commitUsedNumber('receipt', r.docNumber);
    notifyListeners();
  }

  Future<void> deleteReceipt(String id) async {
    await DbService.instance.deleteReceipt(id);
    notifyListeners();
  }

  // ---------------- كشف حساب عميل ----------------
  Future<List<LedgerEntry>> getCustomerStatement(String customerId) async {
    final c = customers.firstWhere((c) => c.id == customerId,
        orElse: () => Customer(id: customerId, name: ''));
    final invoices = await DbService.instance.getInvoices(customerId: customerId);
    final receipts = await DbService.instance.getReceipts(customerId: customerId);

    final entries = <LedgerEntry>[];

    if (c.openingBalance != 0) {
      entries.add(LedgerEntry(
        date: DateTime(2000),
        description: 'رصيد افتتاحي',
        docNumber: '-',
        docId: 'opening',
        docType: LedgerDocType.opening,
        debit: c.openingBalance > 0 ? c.openingBalance : 0,
        credit: c.openingBalance < 0 ? -c.openingBalance : 0,
      ));
    }

    for (final inv in invoices) {
      final isReturn = inv.kind == InvoiceKind.saleReturn;
      entries.add(LedgerEntry(
        date: inv.date,
        description: isReturn ? 'فاتورة مرتجع' : 'فاتورة بيع',
        docNumber: inv.docNumber,
        docId: inv.id,
        docType: isReturn ? LedgerDocType.invoiceReturn : LedgerDocType.invoiceSale,
        debit: isReturn ? 0 : inv.grandTotal,
        credit: isReturn ? inv.grandTotal : 0,
      ));
    }

    for (final r in receipts) {
      entries.add(LedgerEntry(
        date: r.date,
        description: 'سند قبض',
        docNumber: r.docNumber,
        docId: r.id,
        docType: LedgerDocType.receipt,
        debit: 0,
        credit: r.amount,
      ));
    }

    entries.sort((a, b) => a.date.compareTo(b.date));

    double running = 0;
    for (final e in entries) {
      running += e.debit - e.credit;
      e.runningBalance = running;
    }

    return entries;
  }
}
