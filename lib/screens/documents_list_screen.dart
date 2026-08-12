import 'package:flutter/material.dart';

import '../models/doc_row.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../services/db_service.dart';
import '../widgets/document_card.dart';

/// سجل موحّد لكل الفواتير والسندات عبر كل العملاء، مع بطاقات غنية
/// (سحب/ضغط مطول/مؤشرات حالة) وتحديث بالسحب لأسفل
class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({super.key});

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  String _filter = 'all'; // all / sale / return / receipt
  List<Invoice> _invoices = [];
  List<Receipt> _receipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _invoices = await DbService.instance.getInvoices();
    _receipts = await DbService.instance.getReceipts();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = <DocRow>[
      if (_filter == 'all' || _filter == 'sale' || _filter == 'return')
        ..._invoices
            .where((i) => _filter == 'all' ||
                (_filter == 'sale' && i.kind == InvoiceKind.sale) ||
                (_filter == 'return' && i.kind == InvoiceKind.saleReturn))
            .map((i) => DocRow.fromInvoice(i)),
      if (_filter == 'all' || _filter == 'receipt')
        ..._receipts.map((r) => DocRow.fromReceipt(r)),
    ]..sort((a, b) {
        final pinCompare = (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0);
        if (pinCompare != 0) return pinCompare;
        return b.date.compareTo(a.date);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل السندات والفواتير'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'الكل'),
                  _filterChip('sale', 'فواتير بيع'),
                  _filterChip('return', 'فواتير مرتجع'),
                  _filterChip('receipt', 'سندات قبض'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: rows.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('لا توجد مستندات بعد')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) =>
                          DocumentCard(row: rows[i], onChanged: _load),
                    ),
            ),
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}
