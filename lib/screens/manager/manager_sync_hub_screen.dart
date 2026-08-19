import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'manager_import_screen.dart';
import 'manager_export_screen.dart';
import 'manager_sync_log_screen.dart';
import 'manager_live_activity_screen.dart';
import '../../providers/app_provider.dart';
import '../../services/db_service.dart';
import '../../models/user_account.dart';

/// مركز المزامنة عند المدير: عرض مباشر من Firestore (تلقائي، يحتاج نت)
/// + مزامنة بالنت يدوية (تسحب فورًا بدون تسجيل خروج/دخول)
/// + استيراد/تصدير يدوي عبر JSON (يشتغل حتى بدون نت لأي طرف)
class ManagerSyncHubScreen extends StatefulWidget {
  const ManagerSyncHubScreen({super.key});

  @override
  State<ManagerSyncHubScreen> createState() => _ManagerSyncHubScreenState();
}

class _ManagerSyncHubScreenState extends State<ManagerSyncHubScreen> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final isManager = context.read<AppProvider>().currentUser?.role == UserRole.manager;
    final message = await DbService.instance.pullFromFirestore(isManager: isManager);
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: _syncing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              title: const Text('مزامنة بالنت'),
              subtitle: const Text('سحب فوري لآخر البيانات من Firestore لهذا الجهاز'),
              trailing: const Icon(Icons.chevron_left),
              onTap: _syncing ? null : _syncNow,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('نشاط مباشر'),
              subtitle: const Text('فواتير وسندات كل المندوبين لحظيًا من Firestore'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ManagerLiveActivityScreen())),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('الطريقة اليدوية (بدون إنترنت)',
                style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('استيراد ملف مندوب'),
              subtitle: const Text('معاينة الأرقام ثم اعتماد أو إلغاء'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ManagerImportScreen())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('إنشاء تحديث'),
              subtitle: const Text('تصدير المنتجات/الأسعار/العملاء لمندوب أو للجميع'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ManagerExportScreen())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('سجل المزامنة'),
              subtitle: const Text('كل عمليات الاستيراد السابقة'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ManagerSyncLogScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
