import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company_settings.dart';
import '../providers/app_provider.dart';
import '../services/backup_service.dart';
import '../services/auto_backup_service.dart';
import '../services/data_stats_service.dart';
import '../services/cleanup_service.dart';
import '../services/csv_export_service.dart';
import '../utils/formatters.dart';

/// البيانات والنسخ الاحتياطي: نسخ يدوي فوري، نسخ تلقائي دوري، استيراد،
/// حجم البيانات الحالي، تنظيف الصور غير المستخدمة، وتصدير Excel/CSV
class SettingsDataScreen extends StatefulWidget {
  const SettingsDataScreen({super.key});

  @override
  State<SettingsDataScreen> createState() => _SettingsDataScreenState();
}

class _SettingsDataScreenState extends State<SettingsDataScreen> {
  bool _busy = false;
  DateTime? _lastAutoRun;
  late Future<DataStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = DataStatsService.collect();
    AutoBackupService.lastRunAt().then((v) {
      if (mounted) setState(() => _lastAutoRun = v);
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _update(void Function(CompanySettings s) mutate) async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    mutate(s);
    await app.saveSettings(s);
    setState(() {});
  }

  Future<void> _manualBackup() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.exportAndShare();
      _snack('تم إنشاء النسخة الاحتياطية بنجاح');
    } catch (e) {
      _snack('تعذّر إنشاء النسخة الاحتياطية: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final content = await BackupService.instance.pickBackupContent();
    if (content == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: const Text(
            'سيتم دمج بيانات الملف المختار مع البيانات الحالية (لن يتم حذف أي شيء). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استيراد')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await BackupService.instance.importFromJson(content);
      if (mounted) {
        await context.read<AppProvider>().init();
        setState(() => _statsFuture = DataStatsService.collect());
        _snack('تم استيراد النسخة الاحتياطية بنجاح');
      }
    } catch (e) {
      _snack('تعذّر استيراد الملف: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cleanup() async {
    setState(() => _busy = true);
    try {
      final n = await CleanupService.cleanUnusedSignatures();
      _snack(n > 0 ? 'تم حذف $n صورة غير مستخدمة' : 'لا توجد صور غير مستخدمة');
      setState(() => _statsFuture = DataStatsService.collect());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      await CsvExportService.exportAndShare();
    } catch (e) {
      _snack('تعذّر التصدير: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppProvider>().settings;
    return Scaffold(
      appBar: AppBar(title: const Text('البيانات والنسخ الاحتياطي')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('نسخ احتياطي', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('يشمل: العملاء، المنتجات، الفواتير، السندات، والإعدادات',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('نسخ احتياطي يدوي فوري'),
                  onPressed: _manualBackup,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('استيراد نسخة سابقة'),
                  onPressed: _importBackup,
                ),
              ),
              const Divider(height: 32),

              const Text('نسخ احتياطي تلقائي', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<AutoBackupFrequency>(
                segments: const [
                  ButtonSegment(value: AutoBackupFrequency.off, label: Text('معطّل')),
                  ButtonSegment(value: AutoBackupFrequency.daily, label: Text('يومي')),
                  ButtonSegment(value: AutoBackupFrequency.weekly, label: Text('أسبوعي')),
                ],
                selected: {s.autoBackupFrequency},
                onSelectionChanged: (v) => _update((s) => s.autoBackupFrequency = v.first),
              ),
              if (s.autoBackupFrequency != AutoBackupFrequency.off) ...[
                const SizedBox(height: 12),
                const Text('مكان الحفظ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                RadioListTile<AutoBackupLocation>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('محلي على الجهاز فقط'),
                  value: AutoBackupLocation.local,
                  groupValue: s.autoBackupLocation,
                  onChanged: (v) => _update((s) => s.autoBackupLocation = v!),
                ),
                RadioListTile<AutoBackupLocation>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('جوجل درايف'),
                  subtitle: const Text(
                      'تُحفَظ النسخة محليًا تلقائيًا، وتقدر ترفعها لجوجل درايف بضغطة من زر "نسخ احتياطي يدوي فوري" أعلاه',
                      style: TextStyle(fontSize: 11)),
                  value: AutoBackupLocation.driveShare,
                  groupValue: s.autoBackupLocation,
                  onChanged: (v) => _update((s) => s.autoBackupLocation = v!),
                ),
                const SizedBox(height: 4),
                Text(
                  _lastAutoRun != null
                      ? 'آخر نسخة تلقائية: ${Formatters.d(_lastAutoRun!)}'
                      : 'لم يتم إنشاء نسخة تلقائية بعد — ستُنشأ عند فتح التطبيق القادم',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
              const Divider(height: 32),

              const Text('حجم البيانات الحالي', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              FutureBuilder<DataStats>(
                future: _statsFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    );
                  }
                  final d = snap.data!;
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _statRow('عدد الفواتير', '${d.invoices}'),
                          _statRow('عدد السندات', '${d.receipts}'),
                          _statRow('عدد العملاء', '${d.customers}'),
                          _statRow('عدد المنتجات', '${d.products}'),
                          const Divider(),
                          _statRow('المساحة المستخدمة', d.formattedSize, bold: true),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('تنظيف الصور القديمة غير المستخدمة'),
                  onPressed: _cleanup,
                ),
              ),
              const Divider(height: 32),

              const Text('تصدير للمراجعة اليدوية', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('ملف Excel/CSV منفصل عن النسخة الاحتياطية — للاطّلاع والمراجعة فقط',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('تصدير كل البيانات (Excel/CSV)'),
                  onPressed: _exportCsv,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}
