import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import 'customer_statement_screen.dart';

/// إدارة العملاء: إضافة/تعديل/حذف + عرض رصيد كل عميل + دخول لكشف الحساب
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  Future<void> _editCustomer(BuildContext context, Customer? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final openingCtrl =
        TextEditingController(text: existing?.openingBalance.toString() ?? '0');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'إضافة عميل' : 'تعديل عميل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم العميل')),
              TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف')),
              TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'العنوان')),
              TextField(
                controller: openingCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'الرصيد الافتتاحي'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      final c = Customer(
        id: existing?.id ?? const Uuid().v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        openingBalance: double.tryParse(openingCtrl.text) ?? 0,
      );
      if (context.mounted) {
        await context.read<AppProvider>().saveCustomer(c);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editCustomer(context, null),
        child: const Icon(Icons.add),
      ),
      body: app.customers.isEmpty
          ? const Center(child: Text('لا يوجد عملاء بعد — اضغط + للإضافة'))
          : ListView.builder(
              itemCount: app.customers.length,
              itemBuilder: (ctx, i) {
                final c = app.customers[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(c.phone),
                    trailing: FutureBuilder<double>(
                      future: app.getCustomerBalance(c.id),
                      builder: (ctx, snap) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            snap.hasData ? Formatters.money(snap.data!) : '...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: (snap.data ?? 0) > 0 ? Colors.red : Colors.green,
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _editCustomer(context, c);
                              if (v == 'delete') app.deleteCustomer(c.id);
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CustomerStatementScreen(customer: c)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
