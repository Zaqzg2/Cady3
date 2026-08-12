import 'package:flutter/material.dart';

import 'manager_import_screen.dart';
import 'manager_export_screen.dart';
import 'manager_sync_log_screen.dart';

/// مركز المزامنة عند المدير: استيراد ملف مندوب وسجل المزامنة فعّالان،
/// "إنشاء تحديث" (دفع منتجات/أسعار/عملاء للمندوبين) لسه قريبًا
class ManagerSyncHubScreen extends StatelessWidget {
  const ManagerSyncHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
