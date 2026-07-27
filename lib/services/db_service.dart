import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';

/// طبقة الوصول لقاعدة بيانات SQLite المحلية (كل شيء يُخزَّن على الجهاز)
class DbService {
  DbService._();
  static final DbService instance = DbService._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'cady_sales.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            openingBalance REAL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            unit TEXT,
            imagePath TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE invoices (
            id TEXT PRIMARY KEY,
            docNumber TEXT,
            date TEXT,
            data TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE receipts (
            id TEXT PRIMARY KEY,
            docNumber TEXT,
            date TEXT,
            data TEXT
          )
        ''');
      },
    );
  }

  // ---------------- العملاء ----------------
  Future<void> upsertCustomer(Customer c) async {
    final d = await db;
    await d.insert('customers', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCustomer(String id) async {
    final d = await db;
    await d.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Customer>> getCustomers() async {
    final d = await db;
    final rows = await d.query('customers', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  // ---------------- المنتجات ----------------
  Future<void> upsertProduct(Product p) async {
    final d = await db;
    await d.insert('products', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteProduct(String id) async {
    final d = await db;
    await d.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Product>> getProducts() async {
    final d = await db;
    final rows = await d.query('products', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  // ---------------- الفواتير ----------------
  Future<void> upsertInvoice(Invoice inv) async {
    final d = await db;
    await d.insert(
      'invoices',
      {
        'id': inv.id,
        'docNumber': inv.docNumber,
        'date': inv.date.toIso8601String(),
        'data': jsonEncode(inv.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteInvoice(String id) async {
    final d = await db;
    await d.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Invoice>> getInvoices({String? customerId}) async {
    final d = await db;
    final rows = await d.query('invoices', orderBy: 'date DESC');
    final list = rows
        .map((r) => Invoice.fromMap(jsonDecode(r['data'] as String)))
        .toList();
    if (customerId != null) {
      return list.where((i) => i.customerId == customerId).toList();
    }
    return list;
  }

  Future<Invoice?> getInvoiceById(String id) async {
    final d = await db;
    final rows = await d.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Invoice.fromMap(jsonDecode(rows.first['data'] as String));
  }

  // ---------------- السندات ----------------
  Future<void> upsertReceipt(Receipt r) async {
    final d = await db;
    await d.insert(
      'receipts',
      {
        'id': r.id,
        'docNumber': r.docNumber,
        'date': r.date.toIso8601String(),
        'data': jsonEncode(r.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteReceipt(String id) async {
    final d = await db;
    await d.delete('receipts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Receipt>> getReceipts({String? customerId}) async {
    final d = await db;
    final rows = await d.query('receipts', orderBy: 'date DESC');
    final list =
        rows.map((r) => Receipt.fromMap(jsonDecode(r['data'] as String))).toList();
    if (customerId != null) {
      return list.where((r) => r.customerId == customerId).toList();
    }
    return list;
  }

  Future<Receipt?> getReceiptById(String id) async {
    final d = await db;
    final rows = await d.query('receipts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Receipt.fromMap(jsonDecode(rows.first['data'] as String));
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
