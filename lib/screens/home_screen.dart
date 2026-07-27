import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../widgets/big_card.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';
import 'documents_list_screen.dart';
import 'settings_screen.dart';

/// الشاشة الرئيسية: بطاقات كبيرة بالترتيب المطلوب
/// عميل نقدي / فاتورة مرتجع / فاتورة بيع / سند قبض
/// + أيقونة سجل السندات والفواتير أعلى يمين، وأيقونة الإعدادات أعلى يسار
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DocumentsListScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.05,
          children: [
            BigCard(
              icon: Icons.person,
              title: 'عميل نقدي',
              subtitle: 'بيع سريع بدون تسجيل عميل',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InvoiceScreen(
                    kind: InvoiceKind.sale,
                    forceCashCustomer: true,
                  ),
                ),
              ),
            ),
            BigCard(
              icon: Icons.assignment_return,
              title: 'فاتورة مرتجع',
              color: Colors.red.shade100,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InvoiceScreen(kind: InvoiceKind.saleReturn),
                ),
              ),
            ),
            BigCard(
              icon: Icons.point_of_sale,
              title: 'فاتورة بيع',
              color: Colors.green.shade100,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InvoiceScreen(kind: InvoiceKind.sale),
                ),
              ),
            ),
            BigCard(
              icon: Icons.payments,
              title: 'سند قبض',
              color: Colors.amber.shade100,
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ReceiptScreen())),
            ),
          ],
        ),
      ),
    );
  }
}
