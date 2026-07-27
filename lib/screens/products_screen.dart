import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../widgets/big_card.dart';

/// شاشة المنتجات: بطاقات كبيرة + إضافة/حذف منتج والسعر
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  Future<void> _editProduct(BuildContext context, Product? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toString() ?? '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'قطعة');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'إضافة منتج' : 'تعديل منتج'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم المنتج')),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر (ريال يمني)'),
            ),
            TextField(
                controller: unitCtrl,
                decoration: const InputDecoration(labelText: 'الوحدة')),
          ],
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
      final p = Product(
        id: existing?.id ?? const Uuid().v4(),
        name: nameCtrl.text.trim(),
        price: double.tryParse(priceCtrl.text) ?? 0,
        unit: unitCtrl.text.trim(),
      );
      if (context.mounted) {
        await context.read<AppProvider>().saveProduct(p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('المنتجات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editProduct(context, null),
        child: const Icon(Icons.add),
      ),
      body: app.products.isEmpty
          ? const Center(child: Text('لا توجد منتجات بعد — اضغط + للإضافة'))
          : GridView.count(
              padding: const EdgeInsets.all(14),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
              children: app.products.map((p) {
                return GestureDetector(
                  onLongPress: () => showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Wrap(children: [
                        ListTile(
                          leading: const Icon(Icons.edit),
                          title: const Text('تعديل'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _editProduct(context, p);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete, color: Colors.red),
                          title: const Text('حذف'),
                          onTap: () {
                            Navigator.pop(ctx);
                            app.deleteProduct(p.id);
                          },
                        ),
                      ]),
                    ),
                  ),
                  child: BigCard(
                    icon: Icons.inventory_2,
                    title: p.name,
                    subtitle: '${Formatters.money(p.price)} / ${p.unit}',
                    onTap: () => _editProduct(context, p),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
