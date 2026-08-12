import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/sync_status.dart';
import 'db_service.dart';
import 'sync_service.dart';

/// نتيجة عملية مزامنة سحابية
class CloudSyncResult {
  final bool success;
  final int uploaded;
  final int downloaded;
  final String? error;

  const CloudSyncResult({
    required this.success,
    this.uploaded = 0,
    this.downloaded = 0,
    this.error,
  });
}

/// مزامنة سحابية عبر Cloud Firestore.
///
/// المسارات:
///   reps/{repId}/customers/{id}
///   reps/{repId}/products/{id}
///   reps/{repId}/invoices/{id}
///   reps/{repId}/receipts/{id}
///   sync_logs/{autoId}
///
/// تعمل جنبًا إلى جنب مع المزامنة عبر ملفات JSON (SyncService)
/// ولا تستبدلها — يمكن استخدام الاثنتين.
class FirestoreSyncService {
  FirestoreSyncService._();
  static final FirestoreSyncService instance = FirestoreSyncService._();

  FirebaseFirestore? get _db {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// رفع كل السجلات المعلّقة للمندوب [repId] إلى Firestore
  Future<CloudSyncResult> uploadPending({required String repId}) async {
    if (!isAvailable || _db == null) {
      return const CloudSyncResult(
        success: false,
        error: 'Firebase غير مهيأ — تأكد من الربط',
      );
    }

    try {
      final pending = await SyncService.instance.getPendingSummary();
      final batch = _db!.batch();
      int count = 0;
      final repRef = _db!.collection('reps').doc(repId);

      for (final c in pending.customers) {
        final ref = repRef.collection('customers').doc(c.id);
        batch.set(ref, {
          ...c.toMap(),
          'syncStatus': 'pending',
          'uploadedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        count++;
      }
      for (final p in pending.products) {
        final ref = repRef.collection('products').doc(p.id);
        batch.set(ref, {
          ...p.toMap(),
          'syncStatus': 'pending',
          'uploadedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        count++;
      }
      for (final i in pending.invoices) {
        final ref = repRef.collection('invoices').doc(i.id);
        batch.set(ref, {
          ...i.toMap(),
          'syncStatus': 'pending',
          'uploadedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        count++;
      }
      for (final r in pending.receipts) {
        final ref = repRef.collection('receipts').doc(r.id);
        batch.set(ref, {
          ...r.toMap(),
          'syncStatus': 'pending',
          'uploadedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        count++;
      }

      if (count > 0) {
        // سجل المزامنة
        final logRef = _db!.collection('sync_logs').doc();
        batch.set(logRef, {
          'repId': repId,
          'type': 'upload',
          'count': count,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      }

      return CloudSyncResult(success: true, uploaded: count);
    } catch (e, st) {
      debugPrint('Firestore uploadPending error: $e\n$st');
      return CloudSyncResult(success: false, error: e.toString());
    }
  }

  /// سحب التحديثات المعتمدة من المدير ودمجها محلياً
  /// (السجلات التي وضع المدير عليها syncStatus = synced)
  Future<CloudSyncResult> downloadSynced({required String repId}) async {
    if (!isAvailable || _db == null) {
      return const CloudSyncResult(
        success: false,
        error: 'Firebase غير مهيأ',
      );
    }

    try {
      int downloaded = 0;
      final repRef = _db!.collection('reps').doc(repId);

      // عملاء
      final custSnap = await repRef
          .collection('customers')
          .where('syncStatus', isEqualTo: 'synced')
          .get();
      for (final doc in custSnap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['syncStatus'] = 'synced';
        final customer = Customer.fromMap(data);
        await DbService.instance.upsertCustomer(customer);
        downloaded++;
      }

      // منتجات
      final prodSnap = await repRef
          .collection('products')
          .where('syncStatus', isEqualTo: 'synced')
          .get();
      for (final doc in prodSnap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['syncStatus'] = 'synced';
        final product = Product.fromMap(data);
        await DbService.instance.upsertProduct(product);
        downloaded++;
      }

      // فواتير
      final invSnap = await repRef
          .collection('invoices')
          .where('syncStatus', isEqualTo: 'synced')
          .get();
      for (final doc in invSnap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['syncStatus'] = 'synced';
        final invoice = Invoice.fromMap(data);
        await DbService.instance.upsertInvoice(invoice);
        downloaded++;
      }

      // سندات
      final recSnap = await repRef
          .collection('receipts')
          .where('syncStatus', isEqualTo: 'synced')
          .get();
      for (final doc in recSnap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['syncStatus'] = 'synced';
        final receipt = Receipt.fromMap(data);
        await DbService.instance.upsertReceipt(receipt);
        downloaded++;
      }

      return CloudSyncResult(success: true, downloaded: downloaded);
    } catch (e, st) {
      debugPrint('Firestore downloadSynced error: $e\n$st');
      return CloudSyncResult(success: false, error: e.toString());
    }
  }

  /// مزامنة كاملة: رفع ثم سحب
  Future<CloudSyncResult> syncAll({required String repId}) async {
    final up = await uploadPending(repId: repId);
    if (!up.success) return up;
    final down = await downloadSynced(repId: repId);
    return CloudSyncResult(
      success: down.success,
      uploaded: up.uploaded,
      downloaded: down.downloaded,
      error: down.error,
    );
  }

  /// للمدير: جلب كل العمليات المعلّقة من كل المندوبين
  Future<List<Map<String, dynamic>>> managerFetchAllPending() async {
    if (!isAvailable || _db == null) return [];
    final result = <Map<String, dynamic>>[];
    try {
      final reps = await _db!.collection('reps').get();
      for (final repDoc in reps.docs) {
        for (final col in ['customers', 'products', 'invoices', 'receipts']) {
          final snap = await repDoc.reference
              .collection(col)
              .where('syncStatus', isEqualTo: 'pending')
              .get();
          for (final doc in snap.docs) {
            result.add({
              'repId': repDoc.id,
              'collection': col,
              'id': doc.id,
              ...doc.data(),
            });
          }
        }
      }
    } catch (e) {
      debugPrint('managerFetchAllPending: $e');
    }
    return result;
  }

  /// للمدير: اعتماد سجل (تحويله إلى synced)
  Future<bool> managerApprove({
    required String repId,
    required String collection,
    required String docId,
  }) async {
    if (!isAvailable || _db == null) return false;
    try {
      await _db!
          .collection('reps')
          .doc(repId)
          .collection(collection)
          .doc(docId)
          .update({
        'syncStatus': 'synced',
        'approvedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('managerApprove: $e');
      return false;
    }
  }
}
