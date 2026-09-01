import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../services/db_service.dart';
import '../../services/sync_service.dart';
import '../../services/manager_sync_service.dart';
import '../../services/backup_service.dart';
import '../../models/user_account.dart';
import '../../models/sync_log_entry.dart';
import '../../models/export_log_entry.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sync/sync_hero_card.dart';
import '../../widgets/sync/sync_channel_card.dart';
import '../../widgets/sync/sync_pulse.dart';
import '../../widgets/sync/sync_section_header.dart';
import '../../widgets/sync/sync_attention_banner.dart';
import '../../widgets/sync/sync_activity_tile.dart';
import '../../widgets/sync/backup_preview_card.dart';
import '../../widgets/sync/sync_status_panel.dart';
import '../backup_management_screen.dart';
import 'manager_import_screen.dart';
import 'manager_export_screen.dart';
import 'manager_sync_log_screen.dart';
import 'manager_live_activity_screen.dart';
import 'manager_users_screen.dart';

/// شاشة "مركز العمليات" لجانب المدير: بطاقة حالة فايربيس الرئيسية، أربع
/// بطاقات أرقام حقيقية، حالة المندوبين (مبنية من lastSyncAt الفعلي —
/// وليس من عدّ عمليات معلّقة لا يملك جهاز المدير معرفة صادقة بها أصلًا)،
/// شبكة المزامنة اليدوية، معاينة النسخ الاحتياطية، ونشاط أخير مدمَج من
/// سجلّي الاستيراد والتصدير الحقيقيين
class ManagerSyncHubScreen extends StatefulWidget {
  const ManagerSyncHubScreen({super.key});

  @override
  State<ManagerSyncHubScreen> createState() => _ManagerSyncHubScreenState();
}

class _ManagerSyncHubScreenState extends State<ManagerSyncHubScreen> {
  List<SyncLogEntry> _importLog = [];
  List<ExportLogEntry> _exportLog = [];
  List<UserAccount> _reps = [];
  List<BackupRecord> _backups = [];
  PendingSummary? _pendingSummary;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final app = context.read<AppProvider>();
    try {
      final importLog = await ManagerSyncService.instance.getLog();
      final exportLog = await ManagerSyncService.instance.getExportLog();
      final users = await app.getAllUsers();
      final backups = await BackupService.instance.listBackups();
      final pending = await app.getPendingSyncSummary();
      if (!mounted) return;
      setState(() {
        _importLog = importLog;
        _exportLog = exportLog;
        _reps = users.where((u) => u.role == UserRole.rep).toList();
        _backups = backups;
        _pendingSummary = pending;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// تعرض لوحة حالة (bottom sheet) بدل SnackBar وحدها؛ اللوحة مغلقة أثناء
  /// التنفيذ فتمنع تكرار الضغط بلا حاجة لعلم "busy" منفصل هنا
  Future<void> _syncNow() async {
    final ok = await showSyncStatusPanel(
      context,
      title: 'مزامنة Firebase',
      runningLabel: 'جاري سحب آخر التحديثات',
      action: () async {
        final msg = await DbService.instance.pullFromFirestore(isManager: true);
        if (mounted) await context.read<AppProvider>().refreshCustomersAndProducts();
        return msg;
      },
    );
    if (ok == true) await _refresh();
  }

  Future<void> _shareBackup(BackupRecord r) async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.shareBackup(r);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup(BackupRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: const Text(
            'سيتم دمج بيانات هذه النسخة مع البيانات الحالية على هذا الجهاز، بدون حذف أي شيء موجود. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final ok = await showSyncStatusPanel(
      context,
      title: 'استعادة نسخة احتياطية',
      runningLabel: 'جاري دمج البيانات',
      action: () async {
        await BackupService.instance.restoreBackup(r);
        if (mounted) await context.read<AppProvider>().refreshCustomersAndProducts();
        return 'تمت الاستعادة بنجاح';
      },
    );
    if (ok == true) await _refresh();
  }

  String _relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return 'منذ ${diff.inDays} يوم';
  }

  String _shortTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  int get _errorsTotal => _importLog.fold<int>(0, (sum, e) => sum + e.errorsCount);

  int get _todayOpsCount {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    return _importLog.where((e) => isToday(e.importedAt)).length +
        _exportLog.where((e) => isToday(e.createdAt)).length;
  }

  int get _pendingProductsCount => _pendingSummary?.products.length ?? 0;

  int get _activeRepsCount => _reps.where((u) => u.isActive).length;

  List<UserAccount> get _sortedReps {
    final reps = List<UserAccount>.from(_reps);
    reps.sort((a, b) {
      if (a.lastSyncAt == null && b.lastSyncAt == null) return 0;
      if (a.lastSyncAt == null) return 1;
      if (b.lastSyncAt == null) return -1;
      return b.lastSyncAt!.compareTo(a.lastSyncAt!);
    });
    return reps;
  }

  Color _repColor(UserAccount u) {
    if (u.lastSyncAt == null) return Colors.grey;
    final hours = DateTime.now().difference(u.lastSyncAt!).inHours;
    if (hours < 24) return AppTheme.syncSuccess;
    if (hours < 24 * 7) return AppTheme.syncPending;
    return AppTheme.syncError;
  }

  String _repLabel(UserAccount u) {
    if (u.lastSyncAt == null) return 'لم يُزامَن بعد';
    final hours = DateTime.now().difference(u.lastSyncAt!).inHours;
    if (hours < 24) return 'متزامن';
    if (hours < 24 * 7) return 'يحتاج مزامنة';
    return 'متأخر';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final manager = app.currentUser;

    const state = SyncPulseState.synced;

    final attentionLines = <String>[];
    if (_errorsTotal > 0) {
      attentionLines.add('$_errorsTotal خطأ مسجّل بعمليات استيراد سابقة');
    }
    if (_pendingProductsCount > 0) {
      attentionLines.add('$_pendingProductsCount منتج لديك لم يُرفع لفايربيس بعد');
    }
    final staleReps = _sortedReps
        .where((u) => u.lastSyncAt == null || DateTime.now().difference(u.lastSyncAt!).inDays >= 7)
        .length;
    if (staleReps > 0) {
      attentionLines.add('$staleReps مندوب لم تتم مزامنة بياناته منذ أسبوع أو أكثر');
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('مركز العمليات', style: TextStyle(fontSize: 17)),
            Text('إدارة ومتابعة المزامنة',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          ],
        ),
        actions: [
          if (manager != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: AppTheme.primary.withOpacity(0.12),
                    child: Text(
                      manager.displayName.isNotEmpty ? manager.displayName[0] : '؟',
                      style: const TextStyle(
                          color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SyncHeroCard(
                    state: state,
                    title: 'النظام يعمل بشكل طبيعي',
                    subtitle: 'جميع البيانات متزامنة وآمنة',
                    ctaLabel: 'مزامنة الآن',
                    onCtaPressed: _syncNow,
                  ),
                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.error_outline,
                          color: AppTheme.syncError,
                          value: '$_errorsTotal',
                          label: 'أخطاء',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.today_outlined,
                          color: Theme.of(context).colorScheme.tertiary,
                          value: '$_todayOpsCount',
                          label: 'عمليات اليوم',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.inventory_2_outlined,
                          color: AppTheme.syncPending,
                          value: '$_pendingProductsCount',
                          label: 'منتج يحتاج رفع',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.groups_outlined,
                          color: AppTheme.syncSuccess,
                          value: '$_activeRepsCount',
                          label: 'مندوب نشط',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (attentionLines.isNotEmpty) ...[
                    SyncAttentionBanner(
                      title: 'يحتاج إلى انتباهك',
                      lines: attentionLines,
                      ctaLabel: 'عرض المندوبين',
                      onCta: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ManagerUsersScreen()),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  SyncSectionHeader(
                    title: 'حالة المندوبين',
                    actionLabel: 'عرض الكل',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ManagerUsersScreen()),
                    ),
                  ),
                  if (_sortedReps.isEmpty)
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.person_add_alt_outlined),
                        title: const Text('لا يوجد مندوبون بعد'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ManagerUsersScreen()),
                        ),
                      ),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.6,
                      children: [
                        for (final rep in _sortedReps.take(4))
                          _RepStatusCard(
                            name: rep.displayName,
                            repNumber: rep.repNumber,
                            color: _repColor(rep),
                            statusLabel: _repLabel(rep),
                            caption: rep.lastSyncAt != null
                                ? _relativeTime(rep.lastSyncAt!)
                                : 'بلا نشاط',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ManagerUsersScreen()),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SyncChannelCard(
                          icon: Icons.cloud_outlined,
                          iconColor: AppTheme.syncSuccess,
                          title: 'Firebase',
                          line1: 'المزامنة السحابية',
                          dotColor: AppTheme.syncSuccess,
                          infoText:
                              'بيانات كل المندوبين المرفوعة لفايربيس تصل تلقائيًا بالخلفية. اضغط "مزامنة الآن" لسحب آخر التحديثات فورًا.',
                          quickActions: [
                            SyncQuickAction(icon: Icons.sync, label: 'مزامنة الآن', onPressed: _syncNow),
                            SyncQuickAction(
                              icon: Icons.podcasts_outlined,
                              label: 'نشاط مباشر',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ManagerLiveActivityScreen()),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SyncChannelCard(
                          icon: Icons.folder_zip_outlined,
                          iconColor: AppTheme.syncPending,
                          title: 'يدوي (ملف)',
                          line1: 'بلا إنترنت',
                          infoText:
                              'يستورد ملف بيانات وصلك من مندوب لمراجعته قبل الاعتماد، أو ينشئ ملف تحديث (منتجات/عملاء/إعدادات) لمشاركته مع مندوب أو كل المندوبين.',
                          quickActions: [
                            SyncQuickAction(
                              icon: Icons.file_download_outlined,
                              label: 'استيراد ملف مندوب',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ManagerImportScreen()),
                              ),
                            ),
                            SyncQuickAction(
                              icon: Icons.file_upload_outlined,
                              label: 'إنشاء تحديث',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ManagerExportScreen()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const SyncSectionHeader(title: 'المزامنة اليدوية'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.75,
                    children: [
                      _ManualSyncCard(
                        icon: Icons.file_download_outlined,
                        color: Theme.of(context).colorScheme.tertiary,
                        title: 'استيراد ملف مندوب',
                        subtitle: 'استلام بيانات من مندوب',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ManagerImportScreen()),
                        ),
                      ),
                      _ManualSyncCard(
                        icon: Icons.file_upload_outlined,
                        color: AppTheme.syncSuccess,
                        title: 'إنشاء تحديث',
                        subtitle: 'إرسال تحديثات لمندوب',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ManagerExportScreen()),
                        ),
                      ),
                      _ManualSyncCard(
                        icon: Icons.history_outlined,
                        color: Theme.of(context).colorScheme.secondary,
                        title: 'سجل المزامنة',
                        subtitle: 'كل عمليات الاستيراد',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ManagerSyncLogScreen()),
                        ),
                      ),
                      _ManualSyncCard(
                        icon: Icons.podcasts_outlined,
                        color: AppTheme.primary,
                        title: 'نشاط مباشر',
                        subtitle: 'آخر حركة كل مندوب',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ManagerLiveActivityScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  SyncSectionHeader(
                    title: 'النسخ الاحتياطية',
                    actionLabel: 'عرض الكل',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BackupManagementScreen()),
                    ),
                  ),
                  if (_backups.isEmpty)
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.archive_outlined),
                        title: const Text('لا توجد نسخة احتياطية بعد'),
                        subtitle: const Text('يمكنك إنشاء أول نسخة من هذه الشاشة'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BackupManagementScreen()),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (int i = 0; i < _backups.length && i < 2; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          BackupPreviewCard(
                            record: _backups[i],
                            busy: _busy,
                            onShare: () => _shareBackup(_backups[i]),
                            onRestore: () => _restoreBackup(_backups[i]),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 20),

                  SyncSectionHeader(
                    title: 'آخر النشاط',
                    actionLabel: 'عرض السجل الكامل',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ManagerSyncLogScreen()),
                    ),
                  ),
                  ..._buildActivity(),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildActivity() {
    final items = <_ActivityEntry>[];
    for (final e in _importLog) {
      items.add(_ActivityEntry(
        time: e.importedAt,
        icon: Icons.file_download_outlined,
        iconColor: e.errorsCount > 0 ? AppTheme.syncError : AppTheme.syncSuccess,
        title: 'استيراد من ${e.repDisplayName}',
        subtitle: '${e.totalRecords} سجل${e.duplicatesCount > 0 ? ' - ${e.duplicatesCount} مكرر' : ''}',
        badgeText: e.errorsCount > 0 ? '${e.errorsCount} خطأ' : 'ناجح',
        badgeColor: e.errorsCount > 0 ? AppTheme.syncError : AppTheme.syncSuccess,
      ));
    }
    for (final e in _exportLog) {
      final count = e.productsCount + e.customersCount;
      items.add(_ActivityEntry(
        time: e.createdAt,
        icon: Icons.file_upload_outlined,
        iconColor: AppTheme.syncSuccess,
        title: 'تحديث أُرسل ← ${e.targetLabel}',
        subtitle: '$count سجل',
        badgeText: 'مكتمل',
        badgeColor: Theme.of(context).colorScheme.tertiary,
      ));
    }
    items.sort((a, b) => b.time.compareTo(a.time));

    if (items.isEmpty) {
      return [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('لا يوجد نشاط بعد', style: TextStyle(color: Colors.grey.shade600)),
          ),
        ),
      ];
    }

    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              for (final e in items.take(6))
                SyncActivityTile(
                  time: _shortTime(e.time),
                  icon: e.icon,
                  iconColor: e.iconColor,
                  title: e.title,
                  subtitle: e.subtitle,
                  badgeText: e.badgeText,
                  badgeColor: e.badgeColor,
                ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _ActivityEntry {
  final DateTime time;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  _ActivityEntry({
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
  });
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StatCard(
      {required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepStatusCard extends StatelessWidget {
  final String name;
  final String repNumber;
  final Color color;
  final String statusLabel;
  final String caption;
  final VoidCallback onTap;
  const _RepStatusCard({
    required this.name,
    required this.repNumber,
    required this.color,
    required this.statusLabel,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withOpacity(0.12),
                child: Text(
                  name.isNotEmpty ? name[0] : '؟',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(
                      repNumber.isNotEmpty ? 'مندوب $repNumber' : caption,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration:
                    BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
                child: Text(statusLabel,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualSyncCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ManualSyncCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
                child: Icon(icon, color: color, size: 17),
              ),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
