import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/sync_service.dart';
import '../models/invoice.dart';

/// عرض تفصيلي لكل العمليات بانتظار المزامنة الآن، مجمّعة حسب النوع
class SyncPendingPreviewScreen extends StatelessWidget {
  const SyncPendingPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('العمليات المعلّقة')),
      body: FutureBuilder<PendingSummary>(
        future: app.getPendingSyncSummary(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snapshot.data!;
          if (s.total == 0) {
            return const Center(child: Text('لا توجد عمليات معلّقة — كل شيء متزامن'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (s.invoices.isNotEmpty) ...[
                _SectionHeader(title: 'فواتير', count: s.invoices.length),
                for (final inv in s.invoices)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        inv.kind == InvoiceKind.saleReturn
                            ? Icons.assignment_return_outlined
                            : Icons.receipt_long_outlined,
                      ),
                      title: Text('${inv.docNumber} • ${inv.customerName}'),
                      subtitle: Text(
                          '${inv.grandTotal.toStringAsFixed(2)} • ${inv.date.toString().split(' ').first}'),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (s.receipts.isNotEmpty) ...[
                _SectionHeader(title: 'سندات قبض', count: s.receipts.length),
                for (final r in s.receipts)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text('${r.docNumber} • ${r.customerName}'),
                      subtitle: Text(
                          '${r.amount.toStringAsFixed(2)} • ${r.date.toString().split(' ').first}'),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (s.customers.isNotEmpty) ...[
                _SectionHeader(title: 'عملاء جدد أو مُعدَّلون', count: s.customers.length),
                for (final c in s.customers)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.name),
                      subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (s.products.isNotEmpty) ...[
                _SectionHeader(title: 'منتجات جديدة أو مُعدَّلة', count: s.products.length),
                for (final p in s.products)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(p.name),
                      subtitle: Text('${p.price.toStringAsFixed(2)} / ${p.unit}'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
