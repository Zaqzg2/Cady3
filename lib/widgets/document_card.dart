import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../models/doc_row.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../providers/app_provider.dart';
import '../services/pdf_service.dart';
import '../services/print_service.dart';
import '../services/share_util.dart';
import '../utils/formatters.dart';
import '../screens/invoice_screen.dart';
import '../screens/receipt_screen.dart';
import '../screens/pdf_preview_screen.dart';
import '../screens/customer_detail_screen.dart';

/// بطاقة مستند (فاتورة أو سند) تُستخدم في "آخر العمليات" بالصفحة الرئيسية
/// وفي سجل السندات والفواتير: أيقونة دائرية، 3 أسطر معلومات، إجراءات سريعة،
/// سحب يمين/يسار، ضغط مطول، ومؤشرات حالة صغيرة
class DocumentCard extends StatelessWidget {
  final DocRow row;
  final VoidCallback onChanged;
  final bool compact;

  const DocumentCard({
    super.key,
    required this.row,
    required this.onChanged,
    this.compact = false,
  });

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<Uint8List> _pdfBytes(BuildContext context) async {
    final app = context.read<AppProvider>();
    if (row.invoice != null) {
      return PdfService.instance.generateInvoicePdf(row.invoice!, app.settings);
    }
    return PdfService.instance.generateReceiptPdf(row.receipt!, app.settings);
  }

  Future<void> _openDetails(BuildContext context) async {
    if (row.invoice != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                InvoiceScreen(kind: row.invoice!.kind, existing: row.invoice)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptScreen(existing: row.receipt)),
      );
    }
    onChanged();
  }

  Future<void> _preview(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: '${row.title} ${row.docNumber}',
          shareFileName: '${row.title}_${row.docNumber}.pdf',
          buildPdf: () => _pdfBytes(context),
        ),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    final bytes = await _pdfBytes(context);
    if (!context.mounted) return;
    final app = context.read<AppProvider>();
    await printDocument(
      context,
      bytes,
      printerMac: app.settings.printerAddress,
      preferSystem: app.settings.preferSystemPrintDialog,
      blackThreshold: app.settings.printBlackThreshold,
      onPrinted: () async {
        if (row.invoice != null) {
          await app.markInvoicePrinted(row.id);
        } else {
          await app.markReceiptPrinted(row.id);
        }
        onChanged();
      },
    );
  }

  Future<void> _share(BuildContext context) async {
    final bytes = await _pdfBytes(context);
    await ShareUtil.shareBytes(bytes, '${row.title}_${row.docNumber}.pdf',
        text: '${row.title} ${row.docNumber}');
    if (!context.mounted) return;
    final app = context.read<AppProvider>();
    if (row.invoice != null) {
      await app.markInvoiceShared(row.id);
    } else {
      await app.markReceiptShared(row.id);
    }
    onChanged();
  }

  Future<void> _download(BuildContext context) async {
    final bytes = await _pdfBytes(context);
    await ShareUtil.shareBytes(bytes, '${row.title}_${row.docNumber}.pdf',
        text: '${row.title} ${row.docNumber}');
  }

  void _copyNumber(BuildContext context) {
    Clipboard.setData(ClipboardData(text: row.docNumber));
    _snack(context, 'تم نسخ رقم المستند');
  }

  Future<void> _togglePin(BuildContext context) async {
    final app = context.read<AppProvider>();
    if (row.invoice != null) {
      await app.toggleInvoicePinned(row.id);
    } else {
      await app.toggleReceiptPinned(row.id);
    }
    onChanged();
  }

  Future<void> _duplicate(BuildContext context) async {
    final app = context.read<AppProvider>();
    // نسخة جديدة تُنشأ الآن فعليًا، فتُسجَّل باسم المندوب الحالي (وليس اسم
    // مندوب المستند الأصلي الذي رُبما لم يعد هو من يعمل على الجهاز الآن).
    final currentName = app.currentUser?.displayName.trim() ?? '';
    final repNameNow = currentName.isNotEmpty ? currentName : app.settings.repName;
    if (row.invoice != null) {
      final inv = row.invoice!;
      final newNumber = await app.peekNextInvoiceNumber(inv.kind);
      final copy = Invoice(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        docNumber: newNumber,
        date: DateTime.now(),
        kind: inv.kind,
        paymentMode: inv.paymentMode,
        customerId: inv.customerId,
        customerName: inv.customerName,
        items: inv.items,
        discountPercent: inv.discountPercent,
        discountAmount: inv.discountAmount,
        notes: inv.notes,
        repName: repNameNow,
      );
      if (!context.mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => InvoiceScreen(kind: inv.kind, existing: copy)));
    } else {
      final r = row.receipt!;
      final newNumber = await app.peekNextReceiptNumber();
      final copy = Receipt(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        docNumber: newNumber,
        date: DateTime.now(),
        amount: r.amount,
        method: r.method,
        customerId: r.customerId,
        customerName: r.customerName,
        notes: r.notes,
        repName: repNameNow,
      );
      if (!context.mounted) return;
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReceiptScreen(existing: copy)));
    }
    onChanged();
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف ${row.title} رقم ${row.docNumber}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm != true) return;
    final app = context.read<AppProvider>();
    if (row.invoice != null) {
      await app.deleteInvoice(row.id);
    } else {
      await app.deleteReceipt(row.id);
    }
    onChanged();
  }

  void _openCustomer(BuildContext context) {
    final app = context.read<AppProvider>();
    final c = app.customers.firstWhere((c) => c.id == row.customerId,
        orElse: () => Customer(id: row.customerId, name: row.customerName));
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailScreen(customer: c)),
    );
  }

  void _showLongPressMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_red_eye_outlined),
              title: const Text('معاينة مصغرة'),
              onTap: () {
                Navigator.pop(ctx);
                _preview(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _openDetails(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('طباعة'),
              onTap: () {
                Navigator.pop(ctx);
                _print(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF'),
              onTap: () {
                Navigator.pop(ctx);
                _download(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('مشاركة'),
              onTap: () {
                Navigator.pop(ctx);
                _share(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('نسخ الرقم'),
              onTap: () {
                Navigator.pop(ctx);
                _copyNumber(context);
              },
            ),
            ListTile(
              leading: Icon(row.isPinned ? Icons.star : Icons.star_border,
                  color: row.isPinned ? Colors.amber : null),
              title: Text(row.isPinned ? 'إلغاء التثبيت' : 'تثبيت بالأعلى'),
              onTap: () {
                Navigator.pop(ctx);
                _togglePin(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: row.isPinned
            ? Border.all(color: Colors.amber, width: 1.4)
            : null,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _preview(context),
        onLongPress: () => _showLongPressMenu(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _preview(context),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: row.color.withOpacity(0.15),
                  child: Icon(row.icon, color: row.color),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (row.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.star, size: 14, color: Colors.amber),
                          ),
                        Expanded(
                          child: Text(
                            '${row.title} #${row.docNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => _openCustomer(context),
                          child: Text(
                            row.customerName,
                            style: TextStyle(
                                color: Colors.red.shade400,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${Formatters.d(row.date)} • ${TimeOfDay.fromDateTime(row.date).format(context)}',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'الرصيد بعد العملية: ${Formatters.money(row.balanceAfter)}',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _statusIcon(row.isCollected, Icons.check_circle,
                              Colors.green, 'تم التحصيل'),
                          _statusIcon(!row.isPrinted, Icons.circle,
                              Colors.amber.shade700, 'غير مطبوع'),
                          _statusIcon(!row.isShared, Icons.circle,
                              Colors.red, 'غير مرسل'),
                          _statusIcon(row.hasAttachment, Icons.attach_file,
                              Colors.blueGrey, 'يوجد مرفق'),
                          const Spacer(),
                          Text(Formatters.money(row.amount),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _preview(context),
                            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
                            label: const Text('تفاصيل', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: const Size(0, 32)),
                          ),
                          TextButton.icon(
                            onPressed: () => _print(context),
                            icon: const Icon(Icons.print_outlined, size: 16),
                            label: const Text('طباعة', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: const Size(0, 32)),
                          ),
                        ],
                      ),
                    ] else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(Formatters.money(row.amount),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Slidable(
      key: ValueKey(row.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.55,
        children: [
          SlidableAction(
            onPressed: (_) => _preview(context),
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
            icon: Icons.remove_red_eye_outlined,
            label: 'معاينة',
          ),
          SlidableAction(
            onPressed: (_) => _print(context),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            icon: Icons.print_outlined,
            label: 'طباعة',
          ),
          SlidableAction(
            onPressed: (_) => _share(context),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            icon: Icons.share_outlined,
            label: 'مشاركة',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.55,
        children: [
          SlidableAction(
            onPressed: (_) => _openDetails(context),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'تعديل',
          ),
          SlidableAction(
            onPressed: (_) => _duplicate(context),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            icon: Icons.content_copy_outlined,
            label: 'تكرار',
          ),
          SlidableAction(
            onPressed: (_) => _delete(context),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'حذف',
          ),
        ],
      ),
      child: card,
    );
  }

  Widget _statusIcon(bool show, IconData icon, Color color, String tooltip) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Icon(icon, size: 13, color: color),
      ),
    );
  }
}
