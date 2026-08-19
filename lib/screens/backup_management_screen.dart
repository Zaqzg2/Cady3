import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/backup_service.dart';
import '../utils/formatters.dart';

/// إدارة النسخ الاحتياطية: إنشاء/استعادة بالأعلى، وقائمة بكل النسخة
/// المحفوظة محليًا (بمحتواها الكامل، بدون حاجة لملف خارجي) — كل وحدة
/// فيها تقدر تستعيدها أو تشاركها أو تحذفها مباشرة من نفس الشاشة.
class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen> {
  bool _busy = false;
  late Future<List<BackupRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = BackupService.instance.listBackups();
  }

  void _refresh() => setState(() => _future = BackupService.instance.listBackups());

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.createBackupRecord();
      _snack('تم إنشاء نسخة احتياطية جديدة');
      _refresh();
    } catch (e) {
      _snack('تعذّر إنشاء النسخة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromFile() async {
    final content = await BackupService.instance.pickBackupContent();
    if (content == null) return;
    final ok = await _confirmRestore(fromExternalFile: true);
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await BackupService.instance.importFromJson(content);
      await _afterRestore();
    } catch (e) {
      _snack('تعذّر استيراد الملف: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromRecord(BackupRecord r) async {
    final ok = await _confirmRestore(fromExternalFile: false, fileName: r.fileName);
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await BackupService.instance.restoreBackup(r);
      await _afterRestore();
    } catch (e) {
      _snack('تعذّرت الاستعادة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmRestore({required bool fromExternalFile, String? fileName}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: Text(fromExternalFile
            ? 'سيتم دمج بيانات الملف المختار مع البيانات الحالية (لن يُحذف أي شيء). هل تريد المتابعة؟'
            : 'سيتم دمج بيانات "$fileName" مع البيانات الحالية (لن يُحذف أي شيء). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
        ],
      ),
    );
  }

  Future<void> _afterRestore() async {
    if (!mounted) return;
    await context.read<AppProvider>().init();
    _snack('تمت الاستعادة بنجاح');
    _refresh();
  }

  Future<void> _delete(BackupRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف النسخة الاحتياطية'),
        content: Text('حذف "${r.fileName}"؟ هذا لا يؤثر على بيانات التطبيق الحالية، بس يحذف هذي النسخة من القائمة فقط.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BackupService.instance.deleteBackup(r.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطية')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.restore),
                        label: const Text('استعادة نسخة'),
                        onPressed: _restoreFromFile,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('إنشاء نسخة'),
                        onPressed: _create,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<BackupRecord>>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final records = snap.data!;
                    if (records.isEmpty) {
                      return const Center(child: Text('لا توجد نسخ احتياطية محفوظة بعد'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = records[i];
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _restoreFromRecord(r),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(r.fileName,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      const Icon(Icons.archive_outlined, size: 20),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${Formatters.d(r.createdAt)}  ${r.createdAt.hour.toString().padLeft(2, '0')}:${r.createdAt.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.sd_storage_outlined, size: 15),
                                        const SizedBox(width: 6),
                                        Text('الحجم: ${r.formattedSize}', style: const TextStyle(fontSize: 12.5)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          label: const Text('حذف', style: TextStyle(color: Colors.red)),
                                          onPressed: () => _delete(r),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(Icons.share_outlined, size: 18),
                                          label: const Text('مشاركة'),
                                          onPressed: () => BackupService.instance.shareBackup(r),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
