import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/backup_service.dart';
import '../services/auto_backup_service.dart';
import '../models/company_settings.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/sync/sync_channel_card.dart';
import '../widgets/sync/sync_hero_card.dart';
import '../widgets/sync/sync_pulse.dart';
import 'settings_data_screen.dart';

/// إدارة النسخ الاحتياطية: بطاقة حالة رئيسية تجيب بلمحة "هل بياناتي
/// محفوظة؟"، ثم بطاقتا القناتين (تلقائي دوري، ويدوي فوري)، فقائمة كل
/// نسخة محفوظة محليًا بمحتواها الكامل — كل وحدة تُستعاد أو تُشارك أو
/// تُحذف مباشرة من نفس الشاشة، تمامًا كما كانت
class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen> {
  bool _busy = false;
  String? _lastError;
  Future<void> Function()? _lastAction;
  late Future<List<BackupRecord>> _future;
  DateTime? _autoLastRun;
  bool _loadingAuto = true;

  @override
  void initState() {
    super.initState();
    _future = BackupService.instance.listBackups();
    _loadAutoInfo();
  }

  Future<void> _loadAutoInfo() async {
    final t = await AutoBackupService.lastRunAt();
    if (!mounted) return;
    setState(() {
      _autoLastRun = t;
      _loadingAuto = false;
    });
  }

  void _refresh() {
    setState(() => _future = BackupService.instance.listBackups());
    _loadAutoInfo();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _create() async {
    _lastAction = _create;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await BackupService.instance.createBackupRecord();
      _snack('تم إنشاء نسخة احتياطية جديدة');
      _refresh();
    } catch (e) {
      setState(() => _lastError = 'تعذّر إنشاء النسخة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromFile() async {
    _lastAction = _restoreFromFile;
    final content = await BackupService.instance.pickBackupContent();
    if (content == null) return;
    final ok = await _confirmRestore(fromExternalFile: true);
    if (ok != true) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await BackupService.instance.importFromJson(content);
      await _afterRestore();
    } catch (e) {
      setState(() => _lastError = 'تعذّر استيراد الملف: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromRecord(BackupRecord r) async {
    final ok = await _confirmRestore(fromExternalFile: false, fileName: r.fileName);
    if (ok != true) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await BackupService.instance.restoreBackup(r);
      await _afterRestore();
    } catch (e) {
      setState(() => _lastError = 'تعذّرت الاستعادة: $e');
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
    await BackupService.instance.deleteBackup(r.id);
    _refresh();
  }

  String _formatDate(DateTime? d) {
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

  String _frequencyLabel(AutoBackupFrequency f) {
    switch (f) {
      case AutoBackupFrequency.off:
        return 'معطّل';
      case AutoBackupFrequency.daily:
        return 'يومي';
      case AutoBackupFrequency.weekly:
        return 'أسبوعي';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppProvider>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطية')),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();
        },
        child: FutureBuilder<List<BackupRecord>>(
          future: _future,
          builder: (context, snap) {
            final loadingList = !snap.hasData;
            final records = snap.data ?? const <BackupRecord>[];
            final hasBackups = records.isNotEmpty;

            SyncPulseState state;
            if (_busy) {
              state = SyncPulseState.syncing;
            } else if (_lastError != null) {
              state = SyncPulseState.failed;
            } else if (!loadingList && !hasBackups) {
              state = SyncPulseState.pending;
            } else {
              state = SyncPulseState.synced;
            }

            String title = '';
            String subtitle = '';
            String? ctaLabel;
            SyncHeroCta ctaKind = SyncHeroCta.solid;
            VoidCallback? onCta;

            switch (state) {
              case SyncPulseState.syncing:
                title = 'جارٍ التنفيذ';
                subtitle = 'برجاء الانتظار حتى تكتمل العملية';
                break;
              case SyncPulseState.failed:
                title = 'حدثت مشكلة';
                subtitle = _lastError ?? 'تعذّرت آخر عملية';
                ctaLabel = 'إعادة المحاولة';
                ctaKind = SyncHeroCta.danger;
                onCta = () => _lastAction?.call();
                break;
              case SyncPulseState.pending:
                title = 'لا توجد نسخة احتياطية بعد';
                subtitle = 'يُنصح بإنشاء نسخة الآن لحماية بياناتك';
                ctaLabel = 'إنشاء نسخة الآن';
                ctaKind = SyncHeroCta.solid;
                onCta = _create;
                break;
              case SyncPulseState.synced:
                title = 'بياناتك محفوظة';
                subtitle = loadingList
                    ? 'جارٍ التحقّق...'
                    : '${records.length} نسخة محفوظة · آخر نسخة ${_formatDate(records.first.createdAt)}';
                ctaLabel = 'إنشاء نسخة جديدة';
                ctaKind = SyncHeroCta.ghost;
                onCta = _create;
                break;
            }
            if (_busy) onCta = null;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SyncHeroCard(
                  state: state,
                  progress: null,
                  centerLabel: '!',
                  pendingCaption: 'بلا نسخة',
                  title: title,
                  subtitle: subtitle,
                  ctaLabel: ctaLabel,
                  ctaKind: ctaKind,
                  onCtaPressed: onCta,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SyncChannelCard(
                        icon: Icons.event_repeat_outlined,
                        iconColor: AppTheme.syncSuccess,
                        title: 'تلقائي',
                        line1: _frequencyLabel(settings.autoBackupFrequency),
                        line2: _loadingAuto
                            ? null
                            : 'آخر تنفيذ ${_formatDate(_autoLastRun)}',
                        infoText: settings.autoBackupFrequency == AutoBackupFrequency.off
                            ? 'النسخ التلقائي معطّل حاليًا. عند تفعيله، يُنشئ التطبيق نسخة بصمت كل فترة عند فتحه، دون مقاطعتك بشاشة مشاركة.'
                            : 'يفحص التطبيق عند كل فتح إن حان وقت نسخة جديدة (${_frequencyLabel(settings.autoBackupFrequency)}) وينشئها بصمت دون مقاطعتك.',
                        quickActions: [
                          SyncQuickAction(
                            icon: Icons.tune,
                            label: 'تغيير الجدولة',
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const SettingsDataScreen())),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SyncChannelCard(
                        icon: Icons.archive_outlined,
                        iconColor: AppTheme.syncPending,
                        title: 'يدوي',
                        line1: loadingList
                            ? 'جارٍ التحقّق...'
                            : hasBackups
                                ? '${records.length} نسخة محفوظة'
                                : 'لا توجد نسخة بعد',
                        infoText:
                            'نسخة فورية بضغطة، تُحفظ محليًا بقائمة تقدر تستعرضها وتستعيد أو تشارك أي وحدة منها لاحقًا.',
                        quickActions: [
                          SyncQuickAction(
                              icon: Icons.add_circle_outline,
                              label: 'إنشاء نسخة الآن',
                              onPressed: _busy ? () {} : _create),
                          SyncQuickAction(
                              icon: Icons.restore,
                              label: 'استعادة من ملف',
                              onPressed: _busy ? () {} : _restoreFromFile),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (loadingList)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!hasBackups)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: Text('لا توجد نسخ احتياطية محفوظة بعد')),
                  )
                else ...[
                  Text('كل النسخ (${records.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),
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
                ],
              ],
            );
          },
        ),
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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(record.fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(Icons.archive_outlined, size: 20),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${Formatters.d(record.createdAt)}  ${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}',
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
                    Text('الحجم: ${record.formattedSize}', style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.syncError),
                      label: Text('حذف', style: TextStyle(color: AppTheme.syncError)),
                      onPressed: busy ? null : onDelete,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('مشاركة'),
                      onPressed: busy ? null : onShare,
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
