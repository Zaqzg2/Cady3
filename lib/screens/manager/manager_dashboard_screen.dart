import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../models/user_account.dart';

/// لوحة تحكم المدير: نظرة سريعة على عدد المندوبين وحالتهم. أعمدة
/// المزامنة (آخر مزامنة/عدد العمليات) ستُفعَّل مع شاشتي الاستيراد
/// والتصدير القادمتين
class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final app = context.read<AppProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content:
            Text('تسجيل الخروج من حساب ${app.currentUser?.displayName ?? ''}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تسجيل الخروج')),
        ],
      ),
    );
    if (confirmed == true) await app.logout();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: FutureBuilder<List<UserAccount>>(
        future: app.getAllUsers(),
        builder: (context, snapshot) {
          final users = snapshot.data ?? [];
          final reps = users.where((u) => u.role == UserRole.rep).toList();
          final activeReps = reps.where((u) => u.isActive).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('أهلًا، ${app.currentUser?.displayName ?? ''} 👋',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'إجمالي المندوبين',
                      value: '${reps.length}',
                      icon: Icons.groups,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'مندوبون نشطون',
                      value: '$activeReps',
                      icon: Icons.check_circle,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey.shade600),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'بيانات المزامنة (آخر مزامنة، عدد العمليات المستلمة) ستظهر هنا بعد تفعيل شاشتي الاستيراد والتصدير',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
