import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/backup_service.dart';
import '../services/auto_backup_service.dart';
import '../services/csv_export_service.dart';
import '../models/company_settings.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/sync/sync_section_header.dart';
import '../widgets/sync/sync_status_panel.dart';
import 'settings_data_screen.dart';

/// إدارة النسخ الاحتياطية: ثلاث بطاقات فعل (CSV، تلقائي، يدوي)، ثم قائمة
/// موحّدة لكل نسخة محفوظة (يدوية وتلقائية معًا، موسومة بمصدرها) — كل نسخة
/// تُستعاد أو تُشارك أو تُحذف مباشرة من نفس الشاشة
class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen> {
  late Future<List<BackupRecord>> _future;
  DateTime? _autoLastRun;
  DateTime? _csvLastExport;
  bool _loadingExtras = true;
  // فقط لعمليتَي المشاركة والحذف السريعتين بالقائمة؛ الإنشاء والاستعادة
  // وتصدير CSV تمرّ كلّها عبر لوحة الحالة التي تمنع تكرار الضغط بنفسها
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = BackupService.instance.listBackups();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final auto = await AutoBackupService.lastRunAt();
    final csv = await CsvExportService.lastExportAt();
    if (!mounted) return;
    setState(() {
      _autoLastRun = auto;
      _csvLastExport = csv;
      _loadingExtras = false;
    });
  }

  void _refresh() {
    setState(() => _future = BackupService.instance.listBackups());
    _loadExtras();
  }

  Future<void> _createManual() async {
    final ok = await showSyncStatusPanel(
      context,
      title: 'نسخ احتياطي يدوي',
      runningLabel: 'جاري تجهيز النسخة',
      action: () async {
        await BackupService.instance.createBackupRecord(source: BackupSource.manual);
        return 'تم إنشاء نسخة احتياطية جديدة';
      },
    );
    if (ok == true) _refresh();
  }

  Future<void> _exportCsv() async {
    final ok = await showSyncStatusPanel(
      context,
      title: 'تصدير CSV',
      runningLabel: 'جاري تجهيز الملفات وفتح المشاركة',
      action: () async {
        await CsvExportService.exportAndShare();
        return 'تم تجهيز ملفات CSV للمشاركة';
      },
    );
    if (ok == true) _refresh();
  }

  Future<void> _restoreFromFile() async {
    final content = await BackupService.instance.pickBackupContent();
    if (content == null) return;
    if (!mounted) return;
    final confirmed = await _confirmRestore(fromExternalFile: true);
    if (confirmed != true) return;
    if (!mounted) return;
    final ok = await showSyncStatusPanel(
      context,
      title: 'استعادة من ملف',
      runningLabel: 'جاري دمج البيانات',
      action: () async {
        await BackupService.instance.importFromJson(content);
        if (mounted) await context.read<AppProvider>().init();
        return 'تمت الاستعادة بنجاح';
      },
    );
    if (ok == true) _refresh();
  }

  Future<void> _restoreFromRecord(BackupRecord r) async {
    final confirmed = await _confirmRestore(fromExternalFile: false, fileName: r.fileName);
    if (confirmed != true) return;
    if (!mounted) return;
    final ok = await showSyncStatusPanel(
      context,
      title: 'استعادة نسخة احتياطية',
      runningLabel: 'جاري دمج البيانات',
      action: () async {
        await BackupService.instance.restoreBackup(r);
        if (mounted) await context.read<AppProvider>().init();
        return 'تمت الاستعادة بنجاح';
      },
    );
    if (ok == true) _refresh();
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

  Future<void> _delete(BackupRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف النسخة الاحتياطية'),
        content: Text(
            'حذف "${r.fileName}"؟ هذا لا يؤثر على بيانات التطبيق الحالية، بس يحذف هذي النسخة من القائمة فقط.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.syncError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await BackupService.instance.deleteBackup(r.id);
      _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAuto(bool enabled) async {
    final app = context.read<AppProvider>();
    final settings = app.settings;
    settings.autoBackupFrequency = enabled ? AutoBackupFrequency.daily : AutoBackupFrequency.off;
    await app.saveSettings(settings);
    if (mounted) setState(() {});
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return 'لم يحدث بعد';
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'اليوم $time';
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday =
        d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
    if (wasYesterday) return 'أمس $time';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppProvider>().settings;
    final autoEnabled = settings.autoBackupFrequency != AutoBackupFrequency.off;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('النسخ الاحتياطي', style: TextStyle(fontSize: 17)),
            Text('احفظ بياناتك بأمان.. في أي وقت',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<BackupRecord>>(
          future: _future,
          builder: (context, snap) {
            final loadingList = !snap.hasData;
            final records = snap.data ?? const <BackupRecord>[];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.grid_on_outlined,
                          color: AppTheme.syncSuccess,
                          softColor: AppTheme.syncSuccessSoft,
                          title: 'نسخ CSV',
                          description: 'حفظ البيانات بصيغة CSV للاستخدام في Excel وغيره',
                          buttonLabel: 'إنشاء نسخة',
                          buttonIcon: Icons.file_download_outlined,
                          onPressed: _exportCsv,
                          footer: _loadingExtras
                              ? null
                              : 'آخر تصدير: ${_formatDateTime(_csvLastExport)}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.sync,
                          color: Theme.of(context).colorScheme.tertiary,
                          softColor: Theme.of(context).colorScheme.tertiary.withOpacity(0.12),
                          title: 'نسخ تلقائي',
                          description: 'نسخة احتياطية تلقائية عند فتح التطبيق حسب الجدول',
                          toggleValue: autoEnabled,
                          onToggle: _toggleAuto,
                          buttonLabel: 'إعداد الجدول',
                          buttonIcon: Icons.tune,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsDataScreen()),
                          ),
                          footer: _loadingExtras
                              ? null
                              : (autoEnabled
                                  ? 'آخر تنفيذ: ${_formatDateTime(_autoLastRun)}'
                                  : 'معطّل حاليًا'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.archive_outlined,
                          color: AppTheme.primary,
                          softColor: AppTheme.primary.withOpacity(0.08),
                          title: 'نسخ يدوي',
                          description: 'نسخة احتياطية فورية من جميع بياناتك الآن',
                          buttonLabel: 'ابدأ الآن',
                          buttonIcon: Icons.upload_outlined,
                          onPressed: _createManual,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _restoreFromFile,
                    icon: const Icon(Icons.restore, size: 17),
                    label: const Text('استعادة من ملف خارجي'),
                  ),
                ),
                const SizedBox(height: 6),
                SyncSectionHeader(
                  title: 'النسخ الاحتياطية المحفوظة',
                  actionLabel: 'تحديث',
                  onAction: _refresh,
                ),
                if (loadingList)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (records.isEmpty)
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text('لا توجد نسخ احتياطية محفوظة بعد',
                            style: TextStyle(color: Colors.grey.shade600)),
                      ),
                    ),
                  )
                else
                  for (final r in records) ...[
                    _BackupRecordCard(
                      record: r,
                      busy: _busy,
                      onTap: () => _restoreFromRecord(r),
                      onShare: () => BackupService.instance.shareBackup(r),
                      onDelete: () => _delete(r),
                    ),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.syncSuccessSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined, color: AppTheme.syncSuccess, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('حماية بياناتك أولويتنا',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            const SizedBox(height: 2),
                            Text('يمكنك استعادة بياناتك في أي وقت من نسخة محفوظة',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                      if (records.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Icon(Icons.check_circle, color: AppTheme.syncSuccess, size: 16),
                            const SizedBox(height: 2),
                            Text(_formatDateTime(records.first.createdAt),
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color softColor;
  final String title;
  final String description;
  final String buttonLabel;
  final IconData buttonIcon;
  final VoidCallback onPressed;
  final bool? toggleValue;
  final ValueChanged<bool>? onToggle;
  final String? footer;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.softColor,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onPressed,
    this.toggleValue,
    this.onToggle,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: softColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              if (toggleValue != null) ...[
                const Spacer(),
                Transform.scale(
                  scale: 0.7,
                  child: Switch(value: toggleValue!, activeColor: color, onChanged: onToggle),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.3),
          ),
          if (footer != null) ...[
            const SizedBox(height: 4),
            Text(footer!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          ],
          const Spacer(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(buttonIcon, size: 14),
              label: Text(buttonLabel, style: const TextStyle(fontSize: 10.5)),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupRecordCard extends StatelessWidget {
  final BackupRecord record;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _BackupRecordCard({
    required this.record,
    required this.busy,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isAuto = record.source == BackupSource.auto;
    final tagColor = isAuto ? Theme.of(context).colorScheme.tertiary : AppTheme.primary;
    final time =
        '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: tagColor.withOpacity(0.12),
                child: Icon(Icons.archive_outlined, color: tagColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(isAuto ? 'نسخة تلقائية' : 'نسخة يدوية',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: tagColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(isAuto ? 'تلقائي' : 'يدوي',
                              style: TextStyle(
                                  fontSize: 9.5, fontWeight: FontWeight.bold, color: tagColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${Formatters.d(record.createdAt)}  $time • ${record.formattedSize}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 20),
                tooltip: 'مشاركة',
                onPressed: busy ? null : onShare,
              ),
              PopupMenuButton<String>(
                enabled: !busy,
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, size: 18, color: AppTheme.syncError),
                        const SizedBox(width: 8),
                        const Text('حذف'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
