import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/company_settings.dart';
import '../models/ledger_entry.dart';
import '../services/db_service.dart';
import '../services/numbering_service.dart';
import '../services/settings_service.dart';

/// المزوّد المركزي لحالة التطبيق: عملاء، منتجات، إعدادات، وعمليات
/// حفظ الفواتير/السندات مع حساب المديونية والترقيم التلقائي
class AppProvider extends ChangeNotifier {
  final _uuid = const Uuid();

  List<Customer> customers = [];
  List<Product> products = [];
  CompanySettings settings = CompanySettings();
  bool loading = true;
  String? initError;

  Future<void> init() async {
    loading = true;
    initError = null;
    notifyListeners();
    try {
      customers = await DbService.instance.getCustomers();
      products = await DbService.instance.getProducts();
      settings = await SettingsService.instance.load();
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

  // ---------------- عملاء ----------------
  Future<void> saveCustomer(Customer c) async {
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

  // ---------------- منتجات ----------------
  Future<void> saveProduct(Product p) async {
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

  // ---------------- حفظ سند قبض ----------------
  Future<void> saveReceipt(Receipt r) async {
    final baseBalance =
        await getCustomerBalanceExcluding(r.customerId, excludeReceiptId: r.id);
    r.balanceAfter = baseBalance - r.amount;
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
