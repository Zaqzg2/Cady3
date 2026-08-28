import 'package:flutter/material.dart';

import 'invoice.dart';
import 'receipt.dart';

enum DocKind { sale, saleReturn, receipt }

/// صف موحّد يمثل فاتورة أو سند قبض، تستخدمه بطاقة المستند في الصفحة
/// الرئيسية وسجل السندات والفواتير
class DocRow {
  final String id;
  final DateTime date;
  final String title;
  final String docNumber;
  final String customerName;
  final String customerId;
  final double amount;
  final double balanceAfter;
  final Color color;
  final IconData icon;
  final DocKind kind;
  final bool isPrinted;
  final bool isShared;
  final bool isPinned;
  final bool hasAttachment;
  final bool isCollected; // تم التحصيل نقداً (لفواتير البيع النقدية)
  final Invoice? invoice;
  final Receipt? receipt;

  DocRow({
    required this.id,
    required this.date,
    required this.title,
    required this.docNumber,
    required this.customerName,
    required this.customerId,
    required this.amount,
    required this.balanceAfter,
    required this.color,
    required this.icon,
    required this.kind,
    required this.isPrinted,
    required this.isShared,
    required this.isPinned,
    required this.hasAttachment,
    required this.isCollected,
    this.invoice,
    this.receipt,
  });

  factory DocRow.fromInvoice(Invoice i) => DocRow(
        id: i.id,
        date: i.date,
        title: i.kind == InvoiceKind.sale ? 'فاتورة بيع' : 'فاتورة مرتجع',
        docNumber: i.docNumber,
        customerName: i.customerName,
        customerId: i.customerId,
        amount: i.grandTotal,
        balanceAfter: i.balanceAfter,
        color: i.kind == InvoiceKind.sale ? Colors.blue : Colors.orange,
        icon: i.kind == InvoiceKind.sale
            ? Icons.point_of_sale
            : Icons.assignment_return,
        kind: i.kind == InvoiceKind.sale ? DocKind.sale : DocKind.saleReturn,
        isPrinted: i.isPrinted,
        isShared: i.isShared,
        isPinned: i.isPinned,
        hasAttachment: i.signaturePath != null,
        isCollected: i.kind == InvoiceKind.sale && i.paymentMode == PaymentMode.cash,
        invoice: i,
      );

  factory DocRow.fromReceipt(Receipt r) => DocRow(
        id: r.id,
        date: r.date,
        title: 'سند قبض',
        docNumber: r.docNumber,
        customerName: r.customerName,
        customerId: r.customerId,
        amount: r.amount,
        balanceAfter: r.balanceAfter,
        color: Colors.green,
        icon: Icons.payments,
        kind: DocKind.receipt,
        isPrinted: r.isPrinted,
        isShared: r.isShared,
        isPinned: r.isPinned,
        hasAttachment: r.repSignaturePath != null,
        isCollected: true, // سند القبض هو تحصيل بحد ذاته
        receipt: r,
      );
}
