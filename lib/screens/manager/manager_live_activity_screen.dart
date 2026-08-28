import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/invoice.dart';
import '../../models/receipt.dart';
import '../../models/user_account.dart';
import '../../providers/app_provider.dart';
import '../../services/account_service.dart';
import '../../services/pdf_service.dart';
import '../../services/print_service.dart';
import '../../services/share_util.dart';
import '../../utils/formatters.dart';
import '../invoice_screen.dart';
import '../receipt_screen.dart';
import '../pdf_preview_screen.dart';

/// عرض مباشر (Live) لفواتير وسندات كل المندوبين من Firestore مباشرة —
/// بديل فوري لا يحتاج انتظار تصدير/استيراد JSON يدوي. يعتمد على صلاحية
/// المدير بقواعد الحماية (isManager يقرأ كل شي بغض النظر عن ownerUid).
/// يتحدّث تلقائيًا (StreamBuilder) لحظة ما يوصل أي مستند جديد من أي جهاز
/// مندوب متصل بالإنترنت — بدون أي زر "تحديث" يدوي.
///
/// الضغط على أي عنصر يفتح ورقة إجراءات: معاينة، طباعة، مشاركة، تحميل،
/// تعديل. التعديل يمرّ عبر نفس شاشات الفاتورة/السند المعتادة، وأي حفظ
/// منها يمرّ عبر db_service (الملكية الأصلية للمندوب تُحفَظ تلقائيًا،
/// راجع upsertInvoice/upsertReceipt).
class ManagerLiveActivityScreen extends StatefulWidget {
  final String? initialRepId;
  const ManagerLiveActivityScreen({super.key, this.initialRepId});

  @override
  State<ManagerLiveActivityScreen> createState() =>
      _ManagerLiveActivityScreenState();
}

class _ManagerLiveActivityScreenState extends State<ManagerLiveActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<UserAccount> _reps = [];
  late String? _selectedRepId; // null = كل المندوبين

  @override
  void initState() {
    super.initState();
    _selectedRepId = widget.initialRepId;
    _tab = TabController(length: 2, vsync: this);
    _loadReps();
  }

  Future<void> _loadReps() async {
    final users = await AccountService.instance.getUsers();
    if (!mounted) return;
    setState(() {
      _reps = users.where((u) => u.role == UserRole.rep).toList();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _queryFor(String collection) {
    final col = FirebaseFirestore.instance.collection(collection);
    Query<Map<String, dynamic>> q = col.orderBy('date', descending: true);
    if (_selectedRepId != null) {
      q = col
          .where('ownerUid', isEqualTo: _selectedRepId)
          .orderBy('date', descending: true);
    }
    return q.limit(150);
  }

  String get _selectedRepLabel {
    if (_selectedRepId == null) return 'كل المندوبين';
    final r = _reps.where((r) => r.id == _selectedRepId).toList();
    if (r.isEmpty) return 'كل المندوبين';
    return r.first.displayName.isNotEmpty ? r.first.displayName : r.first.username;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نشاط مباشر'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'فرز حسب المندوب: $_selectedRepLabel',
            onSelected: (v) => setState(() => _selectedRepId = v),
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(value: null, child: Text('كل المندوبين')),
              const PopupMenuDivider(),
              for (final r in _reps)
                PopupMenuItem<String?>(
                  value: r.id,
                  child: Text(r.displayName.isNotEmpty ? r.displayName : r.username),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'الفواتير'), Tab(text: 'السندات')],
        ),
      ),
      body: Column(
        children: [
          if (_selectedRepId != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('مفروزة حسب: $_selectedRepLabel', style: const TextStyle(fontSize: 12.5))),
                  InkWell(
                    onTap: () => setState(() => _selectedRepId = null),
                    child: const Text('إلغاء', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _InvoicesStream(query: _queryFor('invoices')),
                _ReceiptsStream(query: _queryFor('receipts')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicesStream extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  const _InvoicesStream({required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBox(error: snap.error.toString());
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('ما فيه فواتير بعد'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final inv = Invoice.fromMap(docs[i].data());
            final isReturn = inv.kind == InvoiceKind.saleReturn;
            final color = isReturn ? Colors.orange : Colors.green;
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showInvoiceActionsSheet(context, inv),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(
                      isReturn ? Icons.undo : Icons.receipt_long_outlined,
                      color: color,
                      size: 18,
                    ),
                  ),
                  title: Text(inv.customerName),
                  subtitle: Text(
                      '${inv.repName} • ${Formatters.d(inv.date)} • ${isReturn ? "مرتجع" : "بيع"}'),
                  trailing: Text(
                    Formatters.money(inv.grandTotal),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReceiptsStream extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  const _ReceiptsStream({required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBox(error: snap.error.toString());
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('ما فيه سندات بعد'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = Receipt.fromMap(docs[i].data());
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showReceiptActionsSheet(context, r),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.withOpacity(0.12),
                    child: const Icon(Icons.payments_outlined,
                        color: Colors.indigo, size: 18),
                  ),
                  title: Text(r.customerName),
                  subtitle: Text('${r.repName} • ${Formatters.d(r.date)}'),
                  trailing: Text(
                    Formatters.money(r.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// ورقة إجراءات فاتورة: معاينة، طباعة، مشاركة، تحميل، تعديل — كلها تبني
/// نفس PDF عبر PdfService، وتحافظ على ownerUid الأصلي عند أي تعديل/حفظ
/// (راجع db_service.upsertInvoice: يحافظ على المالك الأصلي دائمًا).
void showInvoiceActionsSheet(BuildContext context, Invoice inv) {
  final settings = context.read<AppProvider>().settings;
  showModalBottomSheet(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('معاينة'),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PdfPreviewScreen(
                  title: 'فاتورة ${inv.docNumber}',
                  buildPdf: () => PdfService.instance.generateInvoicePdf(inv, settings),
                  shareFileName: 'فاتورة_${inv.docNumber}.pdf',
                ),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('طباعة'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final bytes = await PdfService.instance.generateInvoicePdf(inv, settings);
              if (!context.mounted) return;
              await printDocument(context, bytes);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('مشاركة'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final bytes = await PdfService.instance.generateInvoicePdf(inv, settings);
              await ShareUtil.shareBytes(bytes, 'فاتورة_${inv.docNumber}.pdf',
                  mimeType: 'application/pdf');
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('تحميل PDF'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final bytes = await PdfService.instance.generateInvoicePdf(inv, settings);
              await FilePicker.platform.saveFile(
                dialogTitle: 'اختر مكان حفظ الفاتورة',
                fileName: 'فاتورة_${inv.docNumber}.pdf',
                bytes: bytes,
                type: FileType.custom,
                allowedExtensions: ['pdf'],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('تعديل'),
            subtitle: Text('مندوب: ${inv.repName}', style: const TextStyle(fontSize: 11.5)),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => InvoiceScreen(kind: inv.kind, existing: inv),
              ));
            },
          ),
        ],
      ),
    ),
  );
}

/// ورقة إجراءات سند — نفس فكرة ورقة الفاتورة أعلاه
void showReceiptActionsSheet(BuildContext context, Receipt r) {
  final settings = context.read<AppProvider>().settings;
  showModalBottomSheet(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('معاينة'),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PdfPreviewScreen(
                  title: 'سند ${r.docNumber}',
                  buildPdf: () => PdfService.instance.generateReceiptPdf(r, settings),
                  shareFileName: 'سند_${r.docNumber}.pdf',
                ),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('طباعة'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final bytes = await PdfService.instance.generateReceiptPdf(r, settings);
              if (!context.mounted) return;
              await printDocument(context, bytes);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('مشاركة'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final bytes = await PdfService.instance.generateReceiptPdf(r, settings);
              await ShareUtil.shareBytes(bytes, 'سند_${r.docNumber}.pdf',
                  mimeType: 'application/pdf');
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('تحميل PDF'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final bytes = await PdfService.instance.generateReceiptPdf(r, settings);
              await FilePicker.platform.saveFile(
                dialogTitle: 'اختر مكان حفظ السند',
                fileName: 'سند_${r.docNumber}.pdf',
                bytes: bytes,
                type: FileType.custom,
                allowedExtensions: ['pdf'],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('تعديل'),
            subtitle: Text('مندوب: ${r.repName}', style: const TextStyle(fontSize: 11.5)),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ReceiptScreen(existing: r),
              ));
            },
          ),
        ],
      ),
    ),
  );
}

/// لو Firestore يحتاج فهرس مركّب (شائع مع فلتر + ترتيب معًا)، رسالة
/// الخطأ نفسها من Firebase تجيب رابط جاهز لإنشائه بضغطة وحدة
class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});

  @override
  Widget build(BuildContext context) {
    final needsIndex =
        error.contains('index') || error.contains('FAILED_PRECONDITION');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              needsIndex
                  ? 'Firestore يحتاج فهرس (index) لهذا الفلتر — افتح الرابط اللي بنص الخطأ تحت بالمتصفح واضغط Create Index، وبعد دقيقة أو دقيقتين ارجع لهذي الشاشة'
                  : 'تعذّر تحميل البيانات من Firestore',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
