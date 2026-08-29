import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/doc_row.dart';
import '../providers/app_provider.dart';
import '../widgets/big_card.dart';
import '../widgets/document_card.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';
import 'documents_list_screen.dart';
import 'settings_screen.dart';

/// الشاشة الرئيسية: بطاقات كبيرة بالترتيب المطلوب
/// عميل نقدي / فاتورة مرتجع / فاتورة بيع / سند قبض
/// + قسم "آخر العمليات" أسفلها
/// + أيقونة سجل السندات والفواتير أعلى يمين، وأيقونة الإعدادات أعلى يسار
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> _recentFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _recentFuture = context.read<AppProvider>().getRecentDocuments(limit: 5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('كادي للمنظفات'),
        leading: IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'الإعدادات',
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'سجل السندات والفواتير',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DocumentsListScreen()));
              setState(_reload);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.05,
              children: [
                BigCard(
                  icon: Icons.person,
                  title: 'عميل نقدي',
                  subtitle: 'بيع سريع بدون تسجيل عميل',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InvoiceScreen(
                          kind: InvoiceKind.sale,
                          forceCashCustomer: true,
                        ),
                      ),
                    );
                    setState(_reload);
                  },
                ),
                BigCard(
                  icon: Icons.assignment_return,
                  title: 'فاتورة مرتجع',
                  color: Colors.red.shade100,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InvoiceScreen(kind: InvoiceKind.saleReturn),
                      ),
                    );
                    setState(_reload);
                  },
                ),
                BigCard(
                  icon: Icons.point_of_sale,
                  title: 'فاتورة بيع',
                  color: Colors.green.shade100,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InvoiceScreen(kind: InvoiceKind.sale),
                      ),
                    );
                    setState(_reload);
                  },
                ),
                BigCard(
                  icon: Icons.payments,
                  title: 'سند قبض',
                  color: Colors.amber.shade100,
                  onTap: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ReceiptScreen()));
                    setState(_reload);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('آخر العمليات',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const DocumentsListScreen()));
                    setState(_reload);
                  },
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            FutureBuilder<List<dynamic>>(
              future: _recentFuture,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('لا توجد عمليات بعد')),
                  );
                }
                return Column(
                  children: items.map((d) {
                    final row = d is Invoice
                        ? DocRow.fromInvoice(d)
                        : DocRow.fromReceipt(d as Receipt);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      child: DocumentCard(
                        row: row,
                        onChanged: () => setState(_reload),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
