import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'manager_import_screen.dart';
import 'manager_export_screen.dart';
import 'manager_sync_log_screen.dart';
import 'manager_live_activity_screen.dart';
import '../../providers/app_provider.dart';
import '../../services/db_service.dart';
import '../../services/manager_sync_service.dart';
import '../../models/user_account.dart';
import '../../models/sync_log_entry.dart';
import '../../models/export_log_entry.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sync/sync_channel_card.dart';
import '../../widgets/sync/sync_hero_card.dart';
import '../../widgets/sync/sync_pulse.dart';

class _SyncActivity {
  final DateTime time;
  final String text;
  final bool hasError;
  const _SyncActivity({required this.time, required this.text, required this.hasError});
}

/// مركز المزامنة عند المدير: عرض مباشر من Firestore (تلقائي، يحتاج نت)
/// + مزامنة بالنت يدوية (تسحب فورًا بدون تسجيل خروج/دخول)
/// + استيراد/تصدير يدوي عبر JSON (يشتغل حتى بدون نت لأي طرف). بطاقة
/// الحالة الرئيسية والقناتان إضافة فوق نفس الوجهات الخمس القديمة —
/// موجودة كلها بالأسفل صراحةً، ما انحذف شيء
class ManagerSyncHubScreen extends StatefulWidget {
  const ManagerSyncHubScreen({super.key});

  @override
  State<ManagerSyncHubScreen> createState() => _ManagerSyncHubScreenState();
}

class _ManagerSyncHubScreenState extends State<ManagerSyncHubScreen> {
  bool _syncing = false;
  String? _lastError;
  _SyncActivity? _activity;
  bool _loadingActivity = true;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    setState(() => _loadingActivity = true);
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

    _SyncActivity? result;
    if (latestImport != null || latestExport != null) {
      final importIsNewer = latestExport == null ||
          (latestImport != null && latestImport.importedAt.isAfter(latestExport.createdAt));
      if (importIsNewer && latestImport != null) {
        result = _SyncActivity(
          time: latestImport.importedAt,
          text:
              'استيراد من ${latestImport.repDisplayName.isNotEmpty ? latestImport.repDisplayName : 'مندوب'}',
          hasError: latestImport.errorsCount > 0,
        );
      } else if (latestExport != null) {
        result = _SyncActivity(
          time: latestExport.createdAt,
          text: 'تحديث أُرسل ← ${latestExport.targetLabel}',
          hasError: false,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _activity = result;
      _loadingActivity = false;
    });
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _lastError = null;
    });
    try {
      final isManager = context.read<AppProvider>().currentUser?.role == UserRole.manager;
      final message = await DbService.instance.pullFromFirestore(isManager: isManager);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = 'تعذّر الوصول لفايربيس: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
      _loadActivity();
    }
  }

  String _relativeTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) {
      final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      return 'اليوم $time';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday =
        d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
    if (wasYesterday) return 'أمس';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  SyncPulseState get _pulseState {
    if (_syncing) return SyncPulseState.syncing;
    if (_lastError != null) return SyncPulseState.failed;
    return SyncPulseState.synced;
  }

  void _goImport() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const ManagerImportScreen()));
  void _goExport() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const ManagerExportScreen()));
  void _goLog() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const ManagerSyncLogScreen()));
  void _goLive() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const ManagerLiveActivityScreen()));

  @override
  Widget build(BuildContext context) {
    final state = _pulseState;

    String title = '';
    String subtitle = '';
    String? ctaLabel;
    SyncHeroCta ctaKind = SyncHeroCta.solid;
    VoidCallback? onCta;

    switch (state) {
      case SyncPulseState.syncing:
        title = 'جارٍ السحب من فايربيس';
        subtitle = 'يحدّث بيانات الفريق الآن';
        break;
      case SyncPulseState.failed:
        title = 'تعذّرت آخر مزامنة';
        subtitle = _lastError ?? 'حاول مرة أخرى';
        ctaLabel = 'إعادة المحاولة';
        ctaKind = SyncHeroCta.danger;
        onCta = _syncing ? null : _syncNow;
        break;
      case SyncPulseState.pending:
        break; // غير مُستخدَمة عند المدير — لا بيانات صادقة لعدّها
      case SyncPulseState.synced:
        title = 'فريقك متصل';
        subtitle = _loadingActivity
            ? 'جارٍ التحقّق من آخر نشاط...'
            : (_activity == null
                ? 'لم يصل أي ملف بعد — استورد أول ملف من مندوب'
                : 'آخر نشاط: ${_activity!.text} · ${_relativeTime(_activity!.time)}');
        ctaLabel = 'استيراد ملف مندوب';
        ctaKind = SyncHeroCta.solid;
        onCta = _goImport;
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('مركز المزامنة')),
      body: RefreshIndicator(
        onRefresh: _syncNow,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SyncHeroCard(
              state: state,
              progress: null,
              title: title,
              subtitle: subtitle,
              ctaLabel: ctaLabel,
              ctaKind: ctaKind,
              onCtaPressed: onCta,
              onTap: _activity != null ? _goLog : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SyncChannelCard(
                    icon: Icons.cloud_outlined,
                    iconColor: AppTheme.syncSuccess,
                    title: 'فايربيس',
                    line1: 'يراقب الفريق مباشرة',
                    infoText:
                        'تراقب هذه القناة اتصال فايربيس بالفريق كامل، وتعكس آخر نشاط مباشر من كل مندوب.',
                    quickActions: [
                      SyncQuickAction(
                          icon: Icons.sync, label: 'مزامنة الآن', onPressed: _syncing ? () {} : _syncNow),
                      SyncQuickAction(
                          icon: Icons.cloud_sync_outlined, label: 'نشاط مباشر', onPressed: _goLive),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SyncChannelCard(
                    icon: Icons.folder_zip_outlined,
                    iconColor: AppTheme.syncPending,
                    title: 'يدوي (JSON)',
                    line1: 'ملفات من ولإلى المندوبين',
                    infoText:
                        'الملفات الواردة من المندوبين تحتاج مراجعتك واعتمادك قبل أن تُحتسب متزامنة نهائيًا.',
                    onTap: _goLog,
                    quickActions: [
                      SyncQuickAction(
                          icon: Icons.file_download_outlined,
                          label: 'استيراد ملف مندوب',
                          onPressed: _goImport),
                      SyncQuickAction(
                          icon: Icons.file_upload_outlined, label: 'إنشاء تحديث', onPressed: _goExport),
                      SyncQuickAction(
                          icon: Icons.history_outlined, label: 'سجل المزامنة', onPressed: _goLog),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                onTap: _goLive,
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
                onTap: _goImport,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('إنشاء تحديث'),
                subtitle: const Text('تصدير المنتجات/الأسعار/العملاء لمندوب أو للجميع'),
                trailing: const Icon(Icons.chevron_left),
                onTap: _goExport,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('سجل المزامنة'),
                subtitle: const Text('كل عمليات الاستيراد السابقة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: _goLog,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
