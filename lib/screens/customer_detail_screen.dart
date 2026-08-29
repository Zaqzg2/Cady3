import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../models/customer_stats.dart';
import '../models/company_settings.dart' show StatementFormat;
import '../models/ledger_entry.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../providers/app_provider.dart';
import '../services/pdf_service.dart';
import '../services/print_service.dart';
import '../services/share_util.dart';
import '../utils/formatters.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';
import 'pdf_preview_screen.dart';
import '../widgets/customer_card.dart' show kOverdueAfterDays;

/// صفحة العميل الكاملة: رأس بمعلومات العميل، بطاقات مؤشرات، إجراءات كشف
/// الحساب، وسجل نشاط تفصيلي (Timeline) لكل فاتورة/سند مع إجراءات سريعة
class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<List<LedgerEntry>> _entriesFuture;
  late Future<CustomerStats> _statsFuture;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _reload() {
    final app = context.read<AppProvider>();
    _entriesFuture = app.getCustomerStatement(widget.customer.id);
    _statsFuture = app.getCustomerStats(widget.customer.id);
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  Customer get _customer {
    final app = context.read<AppProvider>();
    return app.customers.firstWhere((c) => c.id == widget.customer.id,
        orElse: () => widget.customer);
  }

  // ---------------- كشف الحساب (PDF كامل) ----------------
  Future<Uint8List> _buildStatementPdf() async {
    final entries = await _entriesFuture;
    final app = context.read<AppProvider>();
    return PdfService.instance
        .generateStatementPdf(_customer.name, entries, app.settings);
  }

  Future<void> _previewStatement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: 'كشف حساب ${_customer.name}',
          shareFileName: 'كشف_حساب_${_customer.name}.pdf',
          buildPdf: _buildStatementPdf,
        ),
      ),
    );
  }

  Future<void> _printStatement() async {
    final bytes = await _buildStatementPdf();
    final app = context.read<AppProvider>();
    // صيغة A4 قد تكون عدّة صفحات، ولا معنى لإرسالها لطابعة حرارية 80مم
    // عبر البلوتوث (تطبع الصفحة الأولى فقط بعرض ملتوٍ). لذلك تُفتَح هنا
    // بحوار الطباعة العادي بالنظام، الذي يدعم أي طابعة متاحة أو الحفظ PDF.
    if (app.settings.defaultStatementFormat == StatementFormat.a4) {
      await Printing.layoutPdf(onLayout: (format) async => bytes);
      return;
    }
    if (!mounted) return;
    await printDocument(context, bytes,
        printerMac: app.settings.printerAddress,
        preferSystem: app.settings.preferSystemPrintDialog,
        blackThreshold: app.settings.printBlackThreshold);
  }

  Future<void> _shareStatement() async {
    final bytes = await _buildStatementPdf();
    await ShareUtil.shareBytes(bytes, 'كشف_حساب_${_customer.name}.pdf',
        text: 'كشف حساب ${_customer.name}');
  }

  Future<void> _downloadStatement() async {
    final bytes = await _buildStatementPdf();
    await ShareUtil.shareBytes(bytes, 'كشف_حساب_${_customer.name}.pdf',
        text: 'كشف حساب ${_customer.name}');
  }

  // ---------------- إجراءات الاتصال/واتساب/الموقع ----------------
  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _call() async {
    if (_customer.phone.trim().isEmpty) return _snack('لا يوجد رقم هاتف لهذا العميل');
    try {
      await launchUrl(Uri(scheme: 'tel', path: _customer.phone.trim()));
    } catch (_) {
      _snack('تعذّر فتح تطبيق الاتصال');
    }
  }

  Future<void> _whatsapp() async {
    if (_customer.phone.trim().isEmpty) return _snack('لا يوجد رقم هاتف لهذا العميل');
    final digits = _customer.phone.replaceAll(RegExp(r'[^0-9]'), '');
    try {
      await launchUrl(Uri.parse('https://wa.me/$digits'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack('تعذّر فتح واتساب');
    }
  }

  Future<void> _openLocation() async {
    if (_customer.address.trim().isEmpty) return _snack('لا يوجد عنوان لهذا العميل');
    final q = Uri.encodeComponent(_customer.address.trim());
    try {
      await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack('تعذّر فتح الخريطة');
    }
  }

  Future<void> _togglePin() async {
    await context.read<AppProvider>().togglePinCustomer(_customer.id);
    if (mounted) setState(() {});
  }

  Future<void> _editNote() async {
    final ctrl = TextEditingController(text: _customer.notes);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملاحظة عن العميل'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'اكتب ملاحظة...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (result == true) {
      final c = _customer;
      c.notes = ctrl.text.trim();
      await context.read<AppProvider>().saveCustomer(c);
      if (mounted) setState(() {});
    }
  }

  // ---------------- إجراءات إضافة جديد ----------------
  Future<void> _openNewInvoice(InvoiceKind kind) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => InvoiceScreen(kind: kind, initialCustomer: _customer)),
    );
    setState(_reload);
  }

  Future<void> _openNewReceipt() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ReceiptScreen(initialCustomer: _customer)),
    );
    setState(_reload);
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined, color: Colors.teal),
              title: const Text('فاتورة بيع'),
              onTap: () {
                Navigator.pop(ctx);
                _openNewInvoice(InvoiceKind.sale);
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined, color: Colors.green),
              title: const Text('سند قبض'),
              onTap: () {
                Navigator.pop(ctx);
                _openNewReceipt();
              },
            ),
            ListTile(
              leading: const Icon(Icons.undo, color: Colors.orange),
              title: const Text('فاتورة مرتجع'),
              onTap: () {
                Navigator.pop(ctx);
                _openNewInvoice(InvoiceKind.saleReturn);
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text('ملاحظة'),
              onTap: () {
                Navigator.pop(ctx);
                _editNote();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- إجراءات مستند فردي في السجل ----------------
  Future<Uint8List?> _entryPdfBytes(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale ||
        e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null) return null;
      return PdfService.instance.generateInvoicePdf(inv, app.settings);
    } else if (e.docType == LedgerDocType.receipt) {
      final r = await app.getReceiptById(e.docId);
      if (r == null) return null;
      return PdfService.instance.generateReceiptPdf(r, app.settings);
    }
    return null;
  }

  Future<void> _previewEntry(LedgerEntry e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: e.description,
          shareFileName: '${e.description}_${e.docNumber}.pdf',
          buildPdf: () async => (await _entryPdfBytes(e))!,
        ),
      ),
    );
  }

  Future<void> _printEntry(LedgerEntry e) async {
    final bytes = await _entryPdfBytes(e);
    if (bytes == null) return;
    if (!mounted) return;
    final app = context.read<AppProvider>();
    await printDocument(context, bytes,
        printerMac: app.settings.printerAddress,
        preferSystem: app.settings.preferSystemPrintDialog,
        blackThreshold: app.settings.printBlackThreshold);
  }

  Future<void> _shareEntry(LedgerEntry e) async {
    final bytes = await _entryPdfBytes(e);
    if (bytes == null) return;
    await ShareUtil.shareBytes(bytes, '${e.description}_${e.docNumber}.pdf',
        text: '${e.description} ${e.docNumber}');
  }

  Future<void> _downloadEntry(LedgerEntry e) async {
    final bytes = await _entryPdfBytes(e);
    if (bytes == null) return;
    await ShareUtil.shareBytes(bytes, '${e.description}_${e.docNumber}.pdf',
        text: '${e.description} ${e.docNumber}');
  }

  void _copyDocNumber(LedgerEntry e) {
    Clipboard.setData(ClipboardData(text: e.docNumber));
    _snack('تم نسخ رقم المستند');
  }

  Future<void> _openEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale ||
        e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null) return;
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => InvoiceScreen(kind: inv.kind, existing: inv)));
      setState(_reload);
    } else if (e.docType == LedgerDocType.receipt) {
      final r = await app.getReceiptById(e.docId);
      if (r == null) return;
      if (!mounted) return;
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReceiptScreen(existing: r)));
      setState(_reload);
    }
  }

  Future<void> _duplicateEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale ||
        e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null) return;
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
      );
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => InvoiceScreen(kind: inv.kind, existing: copy)));
      setState(_reload);
    } else if (e.docType == LedgerDocType.receipt) {
      final r = await app.getReceiptById(e.docId);
      if (r == null) return;
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
      );
      if (!mounted) return;
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReceiptScreen(existing: copy)));
      setState(_reload);
    }
  }

  Future<void> _deleteEntry(LedgerEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا المستند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm != true) return;
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale || e.docType == LedgerDocType.invoiceReturn) {
      await app.deleteInvoice(e.docId);
    } else if (e.docType == LedgerDocType.receipt) {
      await app.deleteReceipt(e.docId);
    }
    setState(_reload);
  }

  void _showEntryMenu(LedgerEntry e) {
    final isOpening = e.docType == LedgerDocType.opening;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isOpening) ...[
              ListTile(
                leading: const Icon(Icons.remove_red_eye_outlined),
                title: const Text('معاينة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _previewEntry(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('تعديل'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openEntry(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('طباعة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _printEntry(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('مشاركة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareEntry(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('تحميل PDF'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadEntry(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('نسخ رقم المستند'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyDocNumber(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: const Text('تكرار'),
                onTap: () {
                  Navigator.pop(ctx);
                  _duplicateEntry(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('حذف', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteEntry(e);
                },
              ),
            ] else
              const ListTile(title: Text('الرصيد الافتتاحي — لا توجد إجراءات')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_customer.name)),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildStatCards(),
            const SizedBox(height: 12),
            _buildStatementActions(),
            const SizedBox(height: 16),
            const Text('سجل النشاط', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            _buildTimeline(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final c = _customer;
    return FutureBuilder<CustomerStats>(
      future: _statsFuture,
      builder: (context, snap) {
        final stats = snap.data;
        final balance = stats?.balance ?? 0;
        final creditRatio = stats != null ? stats.creditUsageRatio(c.creditLimit) : null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const CircleAvatar(radius: 30, child: Icon(Icons.person, size: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                          if (c.phone.isNotEmpty)
                            Text(c.phone, style: TextStyle(color: Colors.grey.shade600)),
                          Text(c.isActive ? 'نشط' : 'متوقف',
                              style: TextStyle(
                                  color: c.isActive ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(c.isPinned ? Icons.star : Icons.star_border,
                          color: c.isPinned ? Colors.amber : null),
                      onPressed: _togglePin,
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Text('الرصيد',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    const Spacer(),
                    Text(
                      stats == null ? '...' : Formatters.money(balance),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: balance > 0
                            ? Colors.red
                            : (balance < 0 ? Colors.green : Colors.grey),
                      ),
                    ),
                  ],
                ),
                if (creditRatio != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: creditRatio.clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade300,
                      color: creditRatio >= 1
                          ? Colors.red
                          : (creditRatio >= 0.8 ? Colors.orange : Colors.teal),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الحد الائتماني: ${Formatters.money(c.creditLimit)} — مستخدم ${(creditRatio * 100).clamp(0, 999).toStringAsFixed(0)}٪',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
                if (stats != null && balance > 0 &&
                    (stats.daysSinceLastActivity == null ||
                        stats.daysSinceLastActivity! > kOverdueAfterDays))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 14, color: Colors.red),
                        const SizedBox(width: 4),
                        Text('متأخر السداد', style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'آخر نشاط: ${stats?.lastActivityDate != null ? Formatters.d(stats!.lastActivityDate!) : 'لا يوجد'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _headerIcon(Icons.call, 'اتصال', _call),
                    _headerIcon(Icons.chat_bubble_outline, 'واتساب', _whatsapp),
                    _headerIcon(Icons.location_on_outlined, 'الموقع', _openLocation),
                    _headerIcon(Icons.note_alt_outlined, 'ملاحظة', _editNote),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _headerIcon(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    return FutureBuilder<CustomerStats>(
      future: _statsFuture,
      builder: (context, snap) {
        final s = snap.data;
        return Row(
          children: [
            _statCard('الرصيد', s == null ? '...' : Formatters.money(s.balance),
                Icons.account_balance_wallet_outlined, Colors.indigo),
            _statCard('الفواتير', s == null ? '...' : '${s.invoicesCount}',
                Icons.receipt_long_outlined, Colors.teal),
            _statCard('المقبوض', s == null ? '...' : Formatters.money(s.receivedTotal),
                Icons.payments_outlined, Colors.green),
            _statCard('المرتجع', s == null ? '...' : Formatters.money(s.returnsTotal),
                Icons.undo_outlined, Colors.orange),
          ],
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
              Text(value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 2),
              Text(title, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatementActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('📄 كشف حساب PDF', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _headerIcon(Icons.remove_red_eye_outlined, 'معاينة', _previewStatement),
                _headerIcon(Icons.print_outlined, 'طباعة', _printStatement),
                _headerIcon(Icons.share_outlined, 'مشاركة', _shareStatement),
                _headerIcon(Icons.download_outlined, 'تحميل', _downloadStatement),
                _headerIcon(Icons.vertical_align_top, 'أعلى الصفحة', _scrollToTop),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return FutureBuilder<List<LedgerEntry>>(
      future: _entriesFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final entries = snap.data!.reversed.toList(); // الأحدث أولاً
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('لا توجد حركات لهذا العميل')),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          itemBuilder: (ctx, i) => _timelineTile(entries[i]),
        );
      },
    );
  }

  Widget _timelineTile(LedgerEntry e) {
    final isOpening = e.docType == LedgerDocType.opening;
    Color dotColor;
    IconData dotIcon;
    switch (e.docType) {
      case LedgerDocType.receipt:
        dotColor = Colors.green;
        dotIcon = Icons.payments_outlined;
        break;
      case LedgerDocType.invoiceSale:
        dotColor = Colors.blue;
        dotIcon = Icons.shopping_cart_outlined;
        break;
      case LedgerDocType.invoiceReturn:
        dotColor = Colors.orange;
        dotIcon = Icons.undo;
        break;
      case LedgerDocType.opening:
        dotColor = Colors.grey;
        dotIcon = Icons.flag_outlined;
        break;
    }

    final tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isOpening ? null : () => _previewEntry(e),
        onLongPress: () => _showEntryMenu(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                  radius: 16, backgroundColor: dotColor.withOpacity(0.15),
                  child: Icon(dotIcon, size: 16, color: dotColor)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${e.docNumber} — ${Formatters.d(e.date)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    e.debit > 0
                        ? '+${Formatters.money(e.debit)}'
                        : (e.credit > 0 ? '-${Formatters.money(e.credit)}' : '-'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: e.debit > 0 ? Colors.red : Colors.green,
                    ),
                  ),
                  Text(Formatters.money(e.runningBalance),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (isOpening) return tile;

    return Slidable(
      key: ValueKey(e.docId),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.6,
        children: [
          SlidableAction(
            onPressed: (_) => _printEntry(e),
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
            icon: Icons.print_outlined,
            label: 'طباعة',
          ),
          SlidableAction(
            onPressed: (_) => _shareEntry(e),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            icon: Icons.share_outlined,
            label: 'مشاركة',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.6,
        children: [
          SlidableAction(
            onPressed: (_) => _openEntry(e),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'تعديل',
          ),
          SlidableAction(
            onPressed: (_) => _duplicateEntry(e),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            icon: Icons.content_copy_outlined,
            label: 'تكرار',
          ),
          SlidableAction(
            onPressed: (_) => _deleteEntry(e),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'حذف',
          ),
        ],
      ),
      child: tile,
    );
  }
}
