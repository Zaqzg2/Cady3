import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/invoice.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../utils/formatters.dart';

/// تقارير مختصرة: إجمالي المبيعات، المرتجعات، التحصيلات، وإجمالي
/// مديونية العملاء — لفترة محددة
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  Future<Map<String, double>> _computeSummary() async {
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();

    final filteredInv = invoices.where((i) =>
        !i.date.isBefore(_from) && !i.date.isAfter(_to.add(const Duration(days: 1))));
    final filteredRec = receipts.where((r) =>
        !r.date.isBefore(_from) && !r.date.isAfter(_to.add(const Duration(days: 1))));

    double sales = 0, returns = 0, collected = 0;
    for (final i in filteredInv) {
      if (i.kind == InvoiceKind.sale) {
        sales += i.grandTotal;
      } else {
        returns += i.grandTotal;
      }
    }
    for (final r in filteredRec) {
      collected += r.amount;
    }

    return {
      'sales': sales,
      'returns': returns,
      'collected': collected,
      'net': sales - returns,
    };
  }

  Future<double> _totalOutstanding() async {
    final app = context.read<AppProvider>();
    double total = 0;
    for (final c in app.customers) {
      total += await app.getCustomerBalance(c.id);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text('من: ${Formatters.d(_from)}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: _from,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (picked != null) setState(() => _from = picked);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text('إلى: ${Formatters.d(_to)}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: _to,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (picked != null) setState(() => _to = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, double>>(
            future: _computeSummary(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final d = snap.data!;
              return Column(
                children: [
                  _reportCard('إجمالي المبيعات', d['sales']!, Colors.green, Icons.point_of_sale),
                  _reportCard('إجمالي المرتجعات', d['returns']!, Colors.red, Icons.assignment_return),
                  _reportCard('إجمالي التحصيلات', d['collected']!, Colors.blue, Icons.payments),
                  _reportCard('صافي المبيعات', d['net']!, Colors.teal, Icons.trending_up),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          FutureBuilder<double>(
            future: _totalOutstanding(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox();
              return _reportCard('إجمالي مديونية جميع العملاء (حاليًا)',
                  snap.data!, Colors.orange, Icons.account_balance_wallet);
            },
          ),
        ],
      ),
    );
  }

  Widget _reportCard(String title, double value, Color color, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
        title: Text(title),
        trailing: Text(
          Formatters.money(value),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
        ),
      ),
    );
  }
}
