import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/invoice.dart';
import '../providers/app_provider.dart';
import '../widgets/customer_card.dart';
import 'customer_detail_screen.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';

/// إدارة العملاء: إضافة/تعديل/حذف + بطاقة عميل غنية (رصيد، حالة، آخر نشاط،
/// إجراءات سريعة) + دخول لصفحة العميل الكاملة
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  Future<void> _editCustomer(BuildContext context, Customer? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final openingCtrl =
        TextEditingController(text: existing?.openingBalance.toString() ?? '0');
    final creditLimitCtrl =
        TextEditingController(text: existing?.creditLimit.toString() ?? '0');
    bool isActive = existing?.isActive ?? true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
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
                  decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي'),
                ),
                TextField(
                  controller: creditLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'الحد الائتماني (اختياري)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('عميل نشط'),
                  value: isActive,
                  onChanged: (v) => setState(() => isActive = v),
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
      ),
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      final c = Customer(
        id: existing?.id ?? const Uuid().v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        openingBalance: double.tryParse(openingCtrl.text) ?? 0,
        creditLimit: double.tryParse(creditLimitCtrl.text) ?? 0,
        isActive: isActive,
        isPinned: existing?.isPinned ?? false,
        notes: existing?.notes ?? '',
      );
      if (context.mounted) {
        await context.read<AppProvider>().saveCustomer(c);
      }
    }
  }

  Future<void> _openInvoice(BuildContext context, Customer c, InvoiceKind kind) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => InvoiceScreen(kind: kind, initialCustomer: c)),
    );
  }

  Future<void> _openReceipt(BuildContext context, Customer c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReceiptScreen(initialCustomer: c)),
    );
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
              padding: const EdgeInsets.only(top: 6, bottom: 80),
              itemCount: app.customers.length,
              itemBuilder: (ctx, i) {
                final c = app.customers[i];
                return CustomerCard(
                  customer: c,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CustomerDetailScreen(customer: c)),
                  ),
                  onEdit: () => _editCustomer(context, c),
                  onDelete: () => app.deleteCustomer(c.id),
                  onTogglePin: () => app.togglePinCustomer(c.id),
                  onNewInvoice: () => _openInvoice(context, c, InvoiceKind.sale),
                  onNewReceipt: () => _openReceipt(context, c),
                );
              },
            ),
    );
  }
}
