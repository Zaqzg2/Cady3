import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import '../models/customer_stats.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';

/// عدد الأيام التي بعدها يُعتبر العميل "متأخر السداد" إن كان عليه رصيد مدين
const int kOverdueAfterDays = 30;

/// بطاقة عميل في قائمة العملاء: الاسم، الحالة، الرصيد، آخر نشاط وآخر فاتورة،
/// مع إجراءات سريعة، سحب يمين/يسار، وضغط مطول لقائمة إجراءات إضافية
class CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onNewInvoice;
  final VoidCallback onNewReceipt;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.onNewInvoice,
    required this.onNewReceipt,
  });

  Future<void> _call(BuildContext context) async {
    if (customer.phone.trim().isEmpty) {
      _snack(context, 'لا يوجد رقم هاتف لهذا العميل');
      return;
    }
    final uri = Uri(scheme: 'tel', path: customer.phone.trim());
    try {
      await launchUrl(uri);
    } catch (_) {
      if (context.mounted) _snack(context, 'تعذّر فتح تطبيق الاتصال');
    }
  }

  Future<void> _whatsapp(BuildContext context) async {
    if (customer.phone.trim().isEmpty) {
      _snack(context, 'لا يوجد رقم هاتف لهذا العميل');
      return;
    }
    final digits = customer.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) _snack(context, 'تعذّر فتح واتساب');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف العميل "${customer.name}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm == true) onDelete();
  }

  void _showLongPressMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_red_eye_outlined),
              title: const Text('معاينة'),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(customer.isPinned ? Icons.star : Icons.star_border,
                  color: customer.isPinned ? Colors.amber : null),
              title: Text(customer.isPinned ? 'إلغاء التثبيت' : 'تثبيت'),
              onTap: () {
                Navigator.pop(ctx);
                onTogglePin();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _lastActivityLabel(CustomerStats s) {
    if (s.lastActivityDate == null) return 'لا يوجد';
    final days = s.daysSinceLastActivity ?? 0;
    if (days <= 0) return 'اليوم';
    if (days == 1) return 'أمس';
    return 'منذ $days يوم';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return FutureBuilder<CustomerStats>(
      future: app.getCustomerStats(customer.id),
      builder: (context, snap) {
        final stats = snap.data;
        final balance = stats?.balance ?? 0;
        final overdue = stats != null &&
            balance > 0 &&
            (stats.daysSinceLastActivity == null ||
                stats.daysSinceLastActivity! > kOverdueAfterDays);
        final creditRatio =
            stats != null ? stats.creditUsageRatio(customer.creditLimit) : null;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Slidable(
            key: ValueKey(customer.id),
            startActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.6,
              children: [
                SlidableAction(
                  onPressed: (_) => onNewInvoice(),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  icon: Icons.shopping_cart_outlined,
                  label: 'فاتورة',
                ),
                SlidableAction(
                  onPressed: (_) => onNewReceipt(),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  icon: Icons.payments_outlined,
                  label: 'سند قبض',
                ),
                SlidableAction(
                  onPressed: (_) => _call(context),
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  icon: Icons.call,
                  label: 'اتصال',
                ),
              ],
            ),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.6,
              children: [
                SlidableAction(
                  onPressed: (_) => onEdit(),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  icon: Icons.edit_outlined,
                  label: 'تعديل',
                ),
                SlidableAction(
                  onPressed: (_) => onTogglePin(),
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  icon: Icons.star_border,
                  label: 'مفضلة',
                ),
                SlidableAction(
                  onPressed: (_) => _confirmDelete(context),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: Icons.delete_outline,
                  label: 'حذف',
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: overdue
                    ? const Border(right: BorderSide(color: Colors.red, width: 4))
                    : null,
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                onLongPress: () => _showLongPressMenu(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // السطر الأول: الاسم + الحالة
                      Row(
                        children: [
                          if (customer.isPinned)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.star, size: 16, color: Colors.amber),
                            ),
                          Expanded(
                            child: Text(
                              customer.name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: customer.isActive ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // السطر الثاني: الرصيد
                      Row(
                        children: [
                          const Text('الرصيد: ', style: TextStyle(color: Colors.grey)),
                          Text(
                            stats == null ? '...' : Formatters.money(balance),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: balance > 0
                                  ? Colors.red
                                  : (balance < 0 ? Colors.green : Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      if (creditRatio != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: creditRatio.clamp(0, 1).toDouble(),
                            minHeight: 5,
                            backgroundColor: Colors.grey.shade300,
                            color: creditRatio >= 1
                                ? Colors.red
                                : (creditRatio >= 0.8 ? Colors.orange : Colors.teal),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      // السطر الثالث: آخر زيارة / آخر فاتورة
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'آخر نشاط: ${stats == null ? '...' : _lastActivityLabel(stats)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.receipt_long,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            stats?.lastInvoiceNumber != null
                                ? '#${stats!.lastInvoiceNumber}'
                                : 'لا يوجد',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // السطر الرابع: إجراءات سريعة
                      Row(
                        children: [
                          _quickIcon(context, Icons.call, 'اتصال', () => _call(context)),
                          _quickIcon(context, Icons.chat_bubble_outline, 'واتساب',
                              () => _whatsapp(context)),
                          _quickIcon(context, Icons.shopping_cart_outlined, 'فاتورة',
                              onNewInvoice),
                          _quickIcon(context, Icons.payments_outlined, 'سند قبض',
                              onNewReceipt),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _quickIcon(
      BuildContext context, IconData icon, String tooltip, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
