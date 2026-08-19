import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/user_account.dart';
import '../models/sync_log_entry.dart';
import '../models/export_log_entry.dart';

/// طبقة الوصول لقاعدة بيانات التطبيق — Hive محليًا (المصدر الأساسي،
/// يعمل دائمًا حتى بدون إنترنت) + مزامنة أفضل-جهد مع Cloud Firestore
/// بالخلفية (best-effort, fire-and-forget) للعملاء/المنتجات/الفواتير/
/// السندات. الحفظ المحلي لا ينتظر نجاح الشبكة أبدًا — مهم لمندوب ميداني
/// قد يعمل بلا تغطية لفترات طويلة؛ أي فشل مزامنة سحابية يُسجَّل بس بدون
/// ما يوقف أو يبطّئ الحفظ المحلي.
///
/// كل سجل عميل/فاتورة/سند يُنسب لأول من أنشأه (ownerUid = Firebase UID)
/// ولا يتغيّر بعدها حتى لو عدّله شخص ثاني (مدير مثلًا) — هذا يطابق
/// قواعد حماية Firestore (firestore.rules) اللي تحصر كل مندوب ببياناته
/// هو فقط، والمدير يشوف الكل.
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

  // ---------------- مزامنة Firestore (أفضل-جهد، بالخلفية) ----------------

  /// يجلب معرّف المستخدم الحالي على Firebase بأمان — يرجع null بدل ما
  /// يرمي استثناءً لو Firebase أصلًا فشلت تهيئته (راجع البانر بـ
  /// main.dart) حتى لا يتعطّل الحفظ المحلي بسبب هذا وحده.
  String? _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// يكتب مستند على Firestore بدون انتظار (fire-and-forget) — أي خطأ
  /// (لا إنترنت، لا صلاحية، أو حتى Firebase نفسها فشلت تهيئتها) يُسجَّل
  /// فقط ولا يصل للمستدعي أبدًا، حتى لا يتعطّل أو يتبطّأ أي حفظ محلي.
  void _syncSet(String collection, String id, Map<String, dynamic> data) {
    try {
      unawaited(
        FirebaseFirestore.instance.collection(collection).doc(id).set(data).catchError(
          (e) {
            // ignore: avoid_print
            print('تنبيه: تعذّرت مزامنة $collection/$id مع Firestore: $e');
          },
        ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('تنبيه: تعذّرت مزامنة $collection/$id مع Firestore: $e');
    }
  }

  void _syncDelete(String collection, String id) {
    try {
      unawaited(
        FirebaseFirestore.instance.collection(collection).doc(id).delete().catchError(
          (e) {
            // ignore: avoid_print
            print('تنبيه: تعذّر حذف $collection/$id من Firestore: $e');
          },
        ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('تنبيه: تعذّر حذف $collection/$id من Firestore: $e');
    }
  }

  // ---------------- سحب من Firestore (Pull Sync) ----------------
  //
  // upsertX أعلاه يرفع فقط (محلي → سحابة). هذا القسم بالاتجاه المعاكس:
  // يسحب كل ما هو متاح للمستخدم الحالي من Firestore ويدمجه بـ Hive
  // محليًا. لازم لسببين:
  // 1) بعد تثبيت جديد/حذف التطبيق، Hive المحلية فاضية تمامًا حتى لو
  //    البيانات موجودة فعليًا بالسحابة (من هذا الجهاز نفسه سابقًا أو من
  //    أجهزة أخرى) — كل شاشات التطبيق (لوحة التحكم، العملاء...) تقرأ من
  //    Hive فقط، فتظهر فاضية بدون هذي الخطوة رغم وجود البيانات بفايرستور.
  // 2) تحديثات من مندوبين/مدير آخرين على أجهزة ثانية ما توصل تلقائيًا
  //    بدون إعادة تشغيل التطبيق — هذا يتيح تحديث يدوي فوري (زر "مزامنة
  //    بالنت").
  //
  // الدمج last-write-wins بمقارنة updatedAt: لو النسخة المحلية أحدث من
  // السحابية (تعديل محلي لم يوصل السحابة بعد)، تُحفَظ المحلية ولا تُستبدَل.
  // ملاحظة: هذا يسحب فقط (إضافة/تحديث) ولا يحذف محليًا أي سجل غير موجود
  // بالنتيجة السحابية — حذف من جهاز آخر لا ينعكس هنا بعد.

  Future<void> _mergeIncoming<T>({
    required Box box,
    required String id,
    required Map<String, dynamic> remoteMap,
    required T Function(Map<String, dynamic>) fromMap,
    required DateTime Function(T) getUpdatedAt,
  }) async {
    final existingRaw = box.get(id);
    if (existingRaw != null) {
      final existing = fromMap(_asStringMap(existingRaw));
      final remote = fromMap(remoteMap);
      if (getUpdatedAt(existing).isAfter(getUpdatedAt(remote))) {
        return; // النسخة المحلية أحدث — تجاهل نسخة فايرستور
      }
    }
    await box.put(id, remoteMap);
  }

  /// يسحب العملاء/المنتجات/الفواتير/السندات من Firestore ويدمجها محليًا.
  /// [isManager] يوسّع النطاق ليشمل كل المندوبين (يطابق صلاحية القراءة
  /// بقواعد الحماية)؛ خلاف ذلك يقتصر على بيانات المستخدم الحالي فقط.
  /// يرجع رسالة عربية جاهزة للعرض مباشرة بواجهة المستخدم (SnackBar).
  Future<String> pullFromFirestore({required bool isManager}) async {
    await _ensureReady();
    final uid = _currentUid();
    if (uid == null) return 'تعذّر التحقق من هوية المستخدم — سجّل الدخول مرة أخرى';

    try {
      int custN = 0, prodN = 0, invN = 0, recN = 0;

      Query<Map<String, dynamic>> scoped(String collection) {
        final col = FirebaseFirestore.instance.collection(collection);
        return isManager ? col : col.where('ownerUid', isEqualTo: uid);
      }

      final custSnap = await scoped('customers').get();
      for (final doc in custSnap.docs) {
        await _mergeIncoming<Customer>(
          box: _customersBox,
          id: doc.id,
          remoteMap: doc.data(),
          fromMap: Customer.fromMap,
          getUpdatedAt: (c) => c.updatedAt,
        );
        custN++;
      }

      // المنتجات كتالوج مشترك للكل — بلا فلترة ownerUid
      final prodSnap = await FirebaseFirestore.instance.collection('products').get();
      for (final doc in prodSnap.docs) {
        await _productsBox.put(doc.id, doc.data());
        prodN++;
      }

      final invSnap = await scoped('invoices').get();
      for (final doc in invSnap.docs) {
        await _mergeIncoming<Invoice>(
          box: _invoicesBox,
          id: doc.id,
          remoteMap: doc.data(),
          fromMap: Invoice.fromMap,
          getUpdatedAt: (i) => i.updatedAt,
        );
        invN++;
      }

      final recSnap = await scoped('receipts').get();
      for (final doc in recSnap.docs) {
        await _mergeIncoming<Receipt>(
          box: _receiptsBox,
          id: doc.id,
          remoteMap: doc.data(),
          fromMap: Receipt.fromMap,
          getUpdatedAt: (r) => r.updatedAt,
        );
        recN++;
      }

      return 'تمت المزامنة: $custN عميل، $prodN منتج، $invN فاتورة، $recN سند';
    } catch (e) {
      return 'فشلت المزامنة مع Firestore: $e';
    }
  }

  // ---------------- العملاء ----------------
  Future<void> upsertCustomer(Customer c) async {
    await _ensureReady();
    final existingRaw = _customersBox.get(c.id);
    if (existingRaw != null) {
      // سجل موجود: يبقى منسوبًا لأول من أنشأه دائمًا مهما عدّله لاحقًا
      c.ownerUid = Customer.fromMap(_asStringMap(existingRaw)).ownerUid;
    } else if (c.ownerUid.isEmpty) {
      c.ownerUid = _currentUid() ?? '';
    }
    await _customersBox.put(c.id, c.toMap());
    _syncSet('customers', c.id, c.toMap());
  }

  Future<void> deleteCustomer(String id) async {
    await _ensureReady();
    await _customersBox.delete(id);
    _syncDelete('customers', id);
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
    _syncSet('products', p.id, p.toMap());
  }

  Future<void> deleteProduct(String id) async {
    await _ensureReady();
    await _productsBox.delete(id);
    _syncDelete('products', id);
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
    final existingRaw = _invoicesBox.get(inv.id);
    if (existingRaw != null) {
      inv.ownerUid = Invoice.fromMap(_asStringMap(existingRaw)).ownerUid;
    } else if (inv.ownerUid.isEmpty) {
      inv.ownerUid = _currentUid() ?? '';
    }
    await _invoicesBox.put(inv.id, inv.toMap());
    _syncSet('invoices', inv.id, inv.toMap());
  }

  Future<void> deleteInvoice(String id) async {
    await _ensureReady();
    await _invoicesBox.delete(id);
    _syncDelete('invoices', id);
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
    final existingRaw = _receiptsBox.get(r.id);
    if (existingRaw != null) {
      r.ownerUid = Receipt.fromMap(_asStringMap(existingRaw)).ownerUid;
    } else if (r.ownerUid.isEmpty) {
      r.ownerUid = _currentUid() ?? '';
    }
    await _receiptsBox.put(r.id, r.toMap());
    _syncSet('receipts', r.id, r.toMap());
  }

  Future<void> deleteReceipt(String id) async {
    await _ensureReady();
    await _receiptsBox.delete(id);
    _syncDelete('receipts', id);
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
  // ملاحظة: مزامنة Firestore لملفات المستخدمين تمر عبر AccountService
  // مباشرة (تحتاج منطقًا خاصًا: إنشاء حساب Auth أولًا، لا مجرد كتابة
  // مستند) — الدوال هنا محلية بحتة كما كانت قبل.
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
