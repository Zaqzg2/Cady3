import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/invoice.dart';
import '../models/receipt.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../utils/formatters.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';

/// سجل موحّد لكل الفواتير والسندات، مع تعديل/طباعة/حذف مباشرة
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
    setState(() => _loading = false);
  }

  Future<void> _deleteInvoice(Invoice inv) async {
    await context.read<AppProvider>().deleteInvoice(inv.id);
    _load();
  }

  Future<void> _deleteReceipt(Receipt r) async {
    await context.read<AppProvider>().deleteReceipt(r.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // دمج المستندين في قائمة واحدة مرتبة بالتاريخ تنازليًا
    final items = <_DocRow>[
      if (_filter == 'all' || _filter == 'sale' || _filter == 'return')
        ..._invoices
            .where((i) => _filter == 'all' ||
                (_filter == 'sale' && i.kind == InvoiceKind.sale) ||
                (_filter == 'return' && i.kind == InvoiceKind.saleReturn))
            .map((i) => _DocRow.invoice(i)),
      if (_filter == 'all' || _filter == 'receipt')
        ..._receipts.map((r) => _DocRow.receipt(r)),
    ]..sort((a, b) => b.date.compareTo(a.date));

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
          : items.isEmpty
              ? const Center(child: Text('لا توجد مستندات بعد'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final row = items[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: row.color.withOpacity(0.15),
                          child: Icon(row.icon, color: row.color),
                        ),
                        title: Text('${row.title}  #${row.docNumber}'),
                        subtitle: Text('${row.customerName} • ${Formatters.d(row.date)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(Formatters.money(row.amount),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  if (row.invoice != null) {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => InvoiceScreen(
                                                kind: row.invoice!.kind,
                                                existing: row.invoice)));
                                  } else if (row.receipt != null) {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                ReceiptScreen(existing: row.receipt)));
                                  }
                                  _load();
                                } else if (v == 'delete') {
                                  if (row.invoice != null) {
                                    _deleteInvoice(row.invoice!);
                                  } else if (row.receipt != null) {
                                    _deleteReceipt(row.receipt!);
                                  }
                                }
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(value: 'edit', child: Text('تعديل / طباعة')),
                                PopupMenuItem(value: 'delete', child: Text('حذف')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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

class _DocRow {
  final DateTime date;
  final String title;
  final String docNumber;
  final String customerName;
  final double amount;
  final Color color;
  final IconData icon;
  final Invoice? invoice;
  final Receipt? receipt;

  _DocRow({
    required this.date,
    required this.title,
    required this.docNumber,
    required this.customerName,
    required this.amount,
    required this.color,
    required this.icon,
    this.invoice,
    this.receipt,
  });

  factory _DocRow.invoice(Invoice i) => _DocRow(
        date: i.date,
        title: i.kind == InvoiceKind.sale ? 'فاتورة بيع' : 'فاتورة مرتجع',
        docNumber: i.docNumber,
        customerName: i.customerName,
        amount: i.grandTotal,
        color: i.kind == InvoiceKind.sale ? Colors.green : Colors.red,
        icon: i.kind == InvoiceKind.sale ? Icons.point_of_sale : Icons.assignment_return,
        invoice: i,
      );

  factory _DocRow.receipt(Receipt r) => _DocRow(
        date: r.date,
        title: 'سند قبض',
        docNumber: r.docNumber,
        customerName: r.customerName,
        amount: r.amount,
        color: Colors.amber.shade800,
        icon: Icons.payments,
        receipt: r,
      );
}
