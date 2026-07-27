import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../models/ledger_entry.dart';
import '../models/invoice.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';

/// كشف حساب العميل: التاريخ، البيان، رقم المستند، مدين، دائن، الرصيد
/// + إمكانية تعديل/طباعة/حذف أي فاتورة أو سند من نفس الشاشة
class CustomerStatementScreen extends StatefulWidget {
  final Customer customer;
  const CustomerStatementScreen({super.key, required this.customer});

  @override
  State<CustomerStatementScreen> createState() => _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  late Future<List<LedgerEntry>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<AppProvider>().getCustomerStatement(widget.customer.id);
  }

  Future<void> _openEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale ||
        e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null) return;
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InvoiceScreen(kind: inv.kind, existing: inv)));
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
    if (e.docType == LedgerDocType.invoiceSale ||
        e.docType == LedgerDocType.invoiceReturn) {
      await app.deleteInvoice(e.docId);
    } else if (e.docType == LedgerDocType.receipt) {
      await app.deleteReceipt(e.docId);
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('كشف حساب: ${widget.customer.name}')),
      body: FutureBuilder<List<LedgerEntry>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('لا توجد حركات لهذا العميل'));
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('التاريخ')),
                DataColumn(label: Text('البيان')),
                DataColumn(label: Text('رقم المستند')),
                DataColumn(label: Text('مدين')),
                DataColumn(label: Text('دائن')),
                DataColumn(label: Text('الرصيد')),
                DataColumn(label: Text('إجراءات')),
              ],
              rows: entries
                  .map((e) => DataRow(cells: [
                        DataCell(Text(Formatters.d(e.date))),
                        DataCell(Text(e.description)),
                        DataCell(Text(e.docNumber)),
                        DataCell(Text(e.debit > 0 ? Formatters.money(e.debit) : '-')),
                        DataCell(Text(e.credit > 0 ? Formatters.money(e.credit) : '-')),
                        DataCell(Text(Formatters.money(e.runningBalance))),
                        DataCell(
                          e.docType == LedgerDocType.opening
                              ? const SizedBox()
                              : Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _openEntry(e),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          size: 18, color: Colors.red),
                                      onPressed: () => _deleteEntry(e),
                                    ),
                                  ],
                                ),
                        ),
                      ]))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}
