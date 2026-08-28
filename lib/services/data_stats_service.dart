import 'dart:convert';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'db_service.dart';

class DataStats {
  final int customers;
  final int products;
  final int invoices;
  final int receipts;
  final int totalBytes;

  const DataStats({
    required this.customers,
    required this.products,
    required this.invoices,
    required this.receipts,
    required this.totalBytes,
  });

  String get formattedSize {
    if (totalBytes < 1024) return '$totalBytes بايت';
    final kb = totalBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} كيلوبايت';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} ميجابايت';
  }
}

class DataStatsService {
  static const _boxNames = [
    'customers',
    'products',
    'invoices',
    'receipts',
    'images',
    'auto_backups',
  ];

  /// تقدير حجم البيانات المخزّنة فعليًا (بايتات محتوى JSON/Base64 داخل
  /// Hive) — يعمل بنفس الطريقة على الجوال والويب معًا، بخلاف حساب حجم
  /// ملفات فعلية على القرص (غير متاح على الويب أصلاً)
  static Future<int> _estimateStoredBytes() async {
    int total = 0;
    for (final name in _boxNames) {
      try {
        final box = await Hive.openBox(name);
        for (final v in box.values) {
          try {
            total += utf8.encode(jsonEncode(v)).length;
          } catch (_) {
            total += v.toString().length;
          }
        }
      } catch (_) {}
    }
    return total;
  }

  static Future<DataStats> collect() async {
    final customers = await DbService.instance.getCustomers();
    final products = await DbService.instance.getProducts();
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();
    final totalBytes = await _estimateStoredBytes();

    return DataStats(
      customers: customers.length,
      products: products.length,
      invoices: invoices.length,
      receipts: receipts.length,
      totalBytes: totalBytes,
    );
  }
}
