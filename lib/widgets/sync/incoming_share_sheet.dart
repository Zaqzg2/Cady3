import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../models/user_account.dart';
import '../../services/backup_service.dart';
import '../../screens/manager/manager_import_screen.dart';
import 'sync_status_panel.dart';

/// تُعرض حين يصل التطبيق ملف عبر مشاركة أندرويد (راجع ShareIntentService)
/// — تسمح بتوجيهه مباشرة للمسار الصحيح دون فتح منتقي ملفات إطلاقًا.
/// الخيارات تختلف حسب دور المستخدم الحالي لأن معنى "استيراد" يختلف بين
/// المندوب (تحديث من مديره) والمدير (ملف من مندوب، أو نسخة احتياطية كاملة).
Future<void> showIncomingShareSheet(
  BuildContext context, {
  required String fileName,
  required String content,
}) {
  final role = context.read<AppProvider>().currentUser?.role;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _IncomingShareSheet(
      fileName: fileName,
      content: content,
      role: role,
    ),
  );
}

class _IncomingShareSheet extends StatelessWidget {
  final String fileName;
  final String content;
  final UserRole? role;

  const _IncomingShareSheet({required this.fileName, required this.content, required this.role});

  Future<void> _importAsRep(BuildContext context) async {
    Navigator.pop(context); // أغلق الورقة قبل فتح لوحة الحالة
    await showSyncStatusPanel(
      context,
      title: 'استيراد التحديثات',
      runningLabel: 'جاري معالجة الملف',
      action: () async {
        final result = await context.read<AppProvider>().importIncomingSyncFile(content);
        return result.type == 'sync_ack'
            ? 'تم تأكيد مزامنة ${result.ackedCount} سجل'
            : 'تم استيراد ${result.productsUpdated} منتج و${result.customersUpdated} عميل';
      },
    );
  }

  void _importAsManagerRepFile(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManagerImportScreen(initialContent: content, initialFileName: fileName),
      ),
    );
  }

  Future<void> _restoreAsBackup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة كنسخة احتياطية'),
        content: Text(
            'سيتم دمج بيانات "$fileName" مع البيانات الحالية على هذا الجهاز (لن يُحذف أي شيء). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.pop(context);
    await showSyncStatusPanel(
      context,
      title: 'استعادة نسخة احتياطية',
      runningLabel: 'جاري دمج البيانات',
      action: () async {
        await BackupService.instance.importFromJson(content);
        if (context.mounted) await context.read<AppProvider>().init();
        return 'تمت الاستعادة بنجاح';
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.file_present_outlined,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تم استلام ملف',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (role == UserRole.manager) ...[
              FilledButton.icon(
                onPressed: () => _importAsManagerRepFile(context),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('استيراد كملف من مندوب'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _restoreAsBackup(context),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('استعادة كنسخة احتياطية كاملة'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () => _importAsRep(context),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('استيراد كتحديث من المدير'),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تجاهل'),
            ),
          ],
        ),
      ),
    );
  }
}
