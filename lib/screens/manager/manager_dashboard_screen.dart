import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../models/user_account.dart';
import '../../models/sync_log_entry.dart';
import '../../models/export_log_entry.dart';
import '../../services/manager_sync_service.dart';
import '../../theme/app_theme.dart';
import 'manager_sync_hub_screen.dart';

/// لوحة تحكم المدير: نظرة سريعة على عدد المندوبين وحالتهم، وبطاقة نشاط
/// المزامنة الأخير (من سجلّي الاستيراد والتصدير الفعليين) تفتح على مركز
/// المزامنة الكامل عند الضغط
class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key});

  Future<_SyncActivity?> _loadLatestSyncActivity() async {
    final imports = await ManagerSyncService.instance.getLog();
    final exports = await ManagerSyncService.instance.getExportLog();

    SyncLogEntry? latestImport;
    for (final e in imports) {
      if (latestImport == null || e.importedAt.isAfter(latestImport.importedAt)) {
        latestImport = e;
      }
    }
    ExportLogEntry? latestExport;
    for (final e in exports) {
      if (latestExport == null || e.createdAt.isAfter(latestExport.createdAt)) {
        latestExport = e;
      }
    }

    if (latestImport == null && latestExport == null) return null;

    final importIsNewer = latestExport == null ||
        (latestImport != null &&
            latestImport.importedAt.isAfter(latestExport.createdAt));

    if (importIsNewer && latestImport != null) {
      return _SyncActivity(
        time: latestImport.importedAt,
        text: 'استيراد من ${latestImport.repDisplayName.isNotEmpty ? latestImport.repDisplayName : 'مندوب'}',
        hasError: latestImport.errorsCount > 0,
      );
    }
    return _SyncActivity(
      time: latestExport!.createdAt,
      text: 'تحديث أُرسل ← ${latestExport.targetLabel}',
      hasError: false,
    );
  }

  String _relativeTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) {
      final time =
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      return 'اليوم $time';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday = d.year == yesterday.year &&
        d.month == yesterday.month &&
        d.day == yesterday.day;
    if (wasYesterday) return 'أمس';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

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
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'مندوبون نشطون',
                      value: '$activeReps',
                      icon: Icons.check_circle,
                      color: AppTheme.syncSuccess,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FutureBuilder<_SyncActivity?>(
                future: _loadLatestSyncActivity(),
                builder: (context, syncSnap) {
                  final loading = syncSnap.connectionState == ConnectionState.waiting;
                  final activity = syncSnap.data;
                  final hasError = activity?.hasError ?? false;
                  final iconColor = activity == null
                      ? Colors.grey.shade500
                      : hasError
                          ? AppTheme.syncError
                          : AppTheme.syncSuccess;
                  final iconBg = activity == null
                      ? Colors.grey.shade200
                      : hasError
                          ? AppTheme.syncErrorSoft
                          : AppTheme.syncSuccessSoft;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ManagerSyncHubScreen()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
                              child: Icon(
                                activity == null
                                    ? Icons.cloud_outlined
                                    : hasError
                                        ? Icons.error_outline
                                        : Icons.check_circle_outline,
                                size: 20,
                                color: iconColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loading
                                        ? 'جارٍ التحقّق من المزامنة...'
                                        : activity == null
                                            ? 'لا يوجد نشاط مزامنة بعد'
                                            : 'آخر نشاط: ${activity.text}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    loading
                                        ? ' '
                                        : activity == null
                                            ? 'استورد أول ملف من مندوب لتبدأ'
                                            : _relativeTime(activity.time),
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_left, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SyncActivity {
  final DateTime time;
  final String text;
  final bool hasError;
  const _SyncActivity({required this.time, required this.text, required this.hasError});
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
