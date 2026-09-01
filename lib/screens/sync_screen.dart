import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sync/sync_hero_card.dart';
import '../widgets/sync/sync_channel_card.dart';
import '../widgets/sync/sync_pulse.dart';
import '../widgets/sync/sync_section_header.dart';
import '../widgets/sync/sync_attention_banner.dart';
import '../widgets/sync/sync_activity_tile.dart';
import '../widgets/sync/backup_preview_card.dart';
import '../widgets/sync/sync_status_panel.dart';
import 'sync_outbox_inbox_screen.dart';
import 'sync_pending_preview_screen.dart';
import 'backup_management_screen.dart';

/// شاشة "مركز المزامنة" لجانب المندوب: بطاقة حالة رئيسية، إجراءات سريعة،
/// قناتا فايربيس واليدوي، معاينة صندوقَي الاستلام/الإرسال، معاينة النسخ
/// الاحتياطية، وأخيرًا نشاط حقيقي مبني من سجلّي الصادر والوارد الفعليين —
/// لا عدّاد ولا حالة هنا إلا ولها بيانات صادقة تسندها (لا توجد مثلاً حالة
/// "تحديث بانتظار الاعتماد" لأن جهاز المندوب لا يملك أصلًا معرفة كهذه)
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  PendingSummary? _pendingSummary;
  List<OutboxRecord> _outbox = [];
  List<InboxRecord> _inbox = [];
  List<BackupRecord> _backups = [];
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
      final summary = await app.getPendingSyncSummary();
      final outbox = await app.listSyncOutbox();
      final inbox = await app.listSyncInbox();
      final backups = await BackupService.instance.listBackups();
      if (!mounted) return;
      setState(() {
        _pendingSummary = summary;
        _outbox = outbox;
        _inbox = inbox;
        _backups = backups;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _pendingCount => _pendingSummary?.total ?? 0;

  /// الأفعال الرئيسية الثلاثة تعرض لوحة حالة (bottom sheet) بدل الاكتفاء
  /// بـ SnackBar — اللوحة نفسها مغلقة أثناء التنفيذ فتمنع تكرار الضغط،
  /// فلا حاجة لعلم "busy" منفصل هنا كما كان سابقًا
  Future<void> _syncFirebaseNow() async {
    final ok = await showSyncStatusPanel(
      context,
      title: 'مزامنة Firebase',
      runningLabel: 'جاري سحب آخر التحديثات',
      action: () async {
        final msg = await DbService.instance.pullFromFirestore(isManager: false);
        if (mounted) await context.read<AppProvider>().refreshCustomersAndProducts();
        return msg;
      },
    );
    if (ok == true) await _refresh();
  }

  Future<void> _export() async {
    if (_pendingCount == 0) return;
    final ok = await showSyncStatusPanel(
      context,
      title: 'إرسال البيانات للمدير',
      runningLabel: 'جاري تجهيز الملف وفتح المشاركة',
      action: () async {
        final result = await context.read<AppProvider>().exportPendingData();
        return 'تم تجهيز ${result.summary.total} عملية للإرسال';
      },
    );
    if (ok == true) await _refresh();
  }

  Future<void> _importIncoming() async {
    final app = context.read<AppProvider>();
    final content = await app.pickSyncAckFile();
    if (content == null) return;
    if (!mounted) return;
    final ok = await showSyncStatusPanel(
      context,
      title: 'استيراد التحديثات',
      runningLabel: 'جاري معالجة الملف',
      action: () async {
        final result = await app.importIncomingSyncFile(content);
        return result.type == 'sync_ack'
            ? 'تم تأكيد مزامنة ${result.ackedCount} سجل'
            : 'تم استيراد ${result.productsUpdated} منتج و${result.customersUpdated} عميل';
      },
    );
    if (ok == true) await _refresh();
  }

  Future<void> _editDeviceName() async {
    final app = context.read<AppProvider>();
    final controller = TextEditingController(text: app.currentUser?.deviceName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم الجهاز'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'مثال: جوال أحمد'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await app.updateCurrentDeviceName(name);
    if (mounted) setState(() {});
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

  String _pendingBreakdown() {
    final s = _pendingSummary;
    if (s == null) return '';
    final parts = <String>[];
    if (s.invoices.isNotEmpty) parts.add('${s.invoices.length} فاتورة');
    if (s.receipts.isNotEmpty) parts.add('${s.receipts.length} سند');
    if (s.customers.isNotEmpty) parts.add('${s.customers.length} عميل');
    if (s.products.isNotEmpty) parts.add('${s.products.length} منتج');
    return parts.isEmpty ? '' : parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final rep = app.currentUser;

    final state = _pendingCount > 0 ? SyncPulseState.pending : SyncPulseState.synced;

    return Scaffold(
      appBar: AppBar(title: const Text('مركز المزامنة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SyncHeroCard(
                    state: state,
                    title: _pendingCount > 0 ? 'لديك عمليات بانتظار الإرسال' : 'كل شيء متزامن',
                    subtitle: _pendingCount > 0
                        ? '$_pendingCount عملية لم تُرسَل بعد'
                        : (rep?.lastSyncAt != null
                            ? 'آخر مزامنة ${_relativeTime(rep!.lastSyncAt!)}'
                            : 'لم تتم أي مزامنة بعد'),
                    centerLabel: _pendingCount > 0 ? '$_pendingCount' : null,
                    ctaLabel: _pendingCount > 0 ? 'إرسال الآن' : null,
                    onCtaPressed: _pendingCount > 0 ? _export : null,
                    onTap: _pendingCount > 0
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SyncPendingPreviewScreen()),
                            )
                        : null,
                  ),
                  const SizedBox(height: 18),

                  const SyncSectionHeader(title: 'إجراءات سريعة'),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.sync,
                          color: AppTheme.syncSuccess,
                          label: 'مزامنة الآن',
                          onTap: _syncFirebaseNow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.file_download_outlined,
                          color: Theme.of(context).colorScheme.tertiary,
                          label: 'استيراد',
                          onTap: _importIncoming,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.file_upload_outlined,
                          color: Theme.of(context).colorScheme.secondary,
                          label: 'تصدير',
                          onTap: _pendingCount == 0 ? null : _export,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.folder_zip_outlined,
                          color: AppTheme.syncPending,
                          label: 'المزامنة اليدوية',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SyncOutboxInboxScreen()),
                          ),
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
                          line1: 'يُرفع تلقائيًا بالخلفية',
                          dotColor: AppTheme.syncSuccess,
                          infoText:
                              'كل حفظ لفاتورة أو سند أو عميل أو منتج يُرفع تلقائيًا لفايربيس بالخلفية دون أي إجراء منك. اضغط "مزامنة الآن" لسحب آخر ما حدّثه المدير فورًا بدل انتظار الرفع التلقائي.',
                          quickActions: [
                            SyncQuickAction(
                              icon: Icons.sync,
                              label: 'مزامنة الآن',
                              onPressed: _syncFirebaseNow,
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
                              'يبني ملف JSON بكل عملياتك المعلّقة لمشاركته مع المدير عبر واتساب أو بلوتوث أو أي وسيلة أخرى، أو يستورد ملف تأكيد أو تحديث وصلك منه.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SyncOutboxInboxScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  SyncSectionHeader(
                    title: 'صندوق المزامنة اليدوية',
                    actionLabel: 'عرض الكل',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SyncOutboxInboxScreen()),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _MiniBoxCard(
                          icon: Icons.inbox_outlined,
                          color: AppTheme.syncSuccess,
                          title: 'صندوق الاستلام',
                          badge: _inbox.isEmpty ? null : '${_inbox.length}',
                          subtitle: _inbox.isEmpty ? 'لا يوجد شيء بعد' : _inbox.first.summary,
                          caption:
                              _inbox.isEmpty ? '—' : _relativeTime(_inbox.first.receivedAt),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SyncOutboxInboxScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniBoxCard(
                          icon: Icons.outbox_outlined,
                          color:
                              _pendingCount > 0 ? AppTheme.syncPending : AppTheme.syncSuccess,
                          title: 'صندوق الإرسال',
                          badge: _pendingCount > 0 ? '$_pendingCount' : null,
                          subtitle: _pendingCount > 0
                              ? _pendingBreakdown()
                              : (_outbox.isEmpty ? 'لا يوجد شيء بعد' : 'كل شيء أُرسل'),
                          caption: _pendingCount > 0
                              ? 'بانتظار الإرسال'
                              : (_outbox.isEmpty ? '—' : _relativeTime(_outbox.first.createdAt)),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SyncPendingPreviewScreen()),
                          ),
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

                  if (rep != null && rep.deviceName.trim().isEmpty) ...[
                    SyncAttentionBanner(
                      title: 'يحتاج انتباهك',
                      lines: const [
                        'لم تحدّد اسم الجهاز بعد — يساعد المدير على تمييز جهازك عند وصول ملفاتك'
                      ],
                      ctaLabel: 'تحديد الاسم الآن',
                      onCta: _editDeviceName,
                    ),
                    const SizedBox(height: 20),
                  ],

                  const SyncSectionHeader(title: 'النشاط الأخير'),
                  ..._buildActivity(),

                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('بيانات المندوب',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 10),
                          _InfoRow('رقم المندوب',
                              (rep?.repNumber.isNotEmpty == true) ? rep!.repNumber : '—'),
                          _InfoRow('الاسم', rep?.displayName ?? '—'),
                          InkWell(
                            onTap: _editDeviceName,
                            child: _InfoRow(
                              'اسم الجهاز',
                              (rep?.deviceName.isNotEmpty == true)
                                  ? rep!.deviceName
                                  : 'غير محدد (اضغط للتعديل)',
                              trailing: const Icon(Icons.edit_outlined, size: 16),
                            ),
                          ),
                          _InfoRow('إصدار قاعدة البيانات', '${DbService.schemaVersion}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildActivity() {
    final items = <_ActivityEntry>[];
    for (final r in _outbox) {
      final parts = <String>[];
      if (r.invoicesCount > 0) parts.add('${r.invoicesCount} فاتورة');
      if (r.receiptsCount > 0) parts.add('${r.receiptsCount} سند');
      if (r.customersCount > 0) parts.add('${r.customersCount} عميل');
      if (r.productsCount > 0) parts.add('${r.productsCount} منتج');
      items.add(_ActivityEntry(
        time: r.createdAt,
        icon: Icons.upload_outlined,
        iconColor: AppTheme.syncSuccess,
        title: 'تصدير وإرسال البيانات',
        subtitle: parts.isEmpty ? r.fileName : parts.join(' - '),
        badgeText: 'ناجح',
        badgeColor: AppTheme.syncSuccess,
      ));
    }
    for (final r in _inbox) {
      final isAck = r.type == 'sync_ack';
      items.add(_ActivityEntry(
        time: r.receivedAt,
        icon: isAck ? Icons.verified_outlined : Icons.inventory_2_outlined,
        iconColor: AppTheme.syncSuccess,
        title: isAck ? 'تأكيد مزامنة من المدير' : 'تحديث من المدير',
        subtitle: r.summary,
        badgeText: 'ناجح',
        badgeColor: AppTheme.syncSuccess,
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

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  const _QuickAction(
      {required this.icon, required this.color, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
                child: Icon(icon, color: disabled ? Colors.grey : color, size: 19),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: disabled ? Colors.grey : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBoxCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? badge;
  final String subtitle;
  final String caption;
  final VoidCallback onTap;
  const _MiniBoxCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.badge,
    required this.subtitle,
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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 19),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(99)),
                      child: Text(badge!,
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(caption, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  const _InfoRow(this.label, this.value, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}
