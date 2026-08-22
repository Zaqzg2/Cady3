import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sync/sync_channel_card.dart';
import '../widgets/sync/sync_hero_card.dart';
import '../widgets/sync/sync_pulse.dart';
import 'sync_pending_preview_screen.dart';

/// شاشة المزامنة عند المندوب — مركز مزامنة موحّد: بطاقة حالة رئيسية تجيب
/// بلمحة "هل بياناتي آمنة، وماذا أفعل الآن"، ثم بطاقتا القناتين
/// (فايربيس التلقائي، والملف اليدوي)، فبيانات المندوب والوصول التفصيلي.
/// دفع منتجات/أسعار جديدة من المدير سيُضاف مع شاشة "إنشاء تحديث" عنده
/// (مرحلة قادمة)
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  PendingSummary? _pendingSummary;
  bool _loadingCount = true;
  ({String json, String fileName, DateTime at})? _lastExport;
  bool _busy = false;
  String? _lastError;
  Future<void> Function()? _lastAction;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  int get _pendingCount => _pendingSummary?.total ?? 0;

  Future<void> _refresh() async {
    setState(() => _loadingCount = true);
    final app = context.read<AppProvider>();
    final summary = await app.getPendingSyncSummary();
    final last = await app.getLastExport();
    if (!mounted) return;
    setState(() {
      _pendingSummary = summary;
      _lastExport = last;
      _loadingCount = false;
    });
  }

  Future<void> _export() async {
    _lastAction = _export;
    if (_pendingCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات جديدة لتصديرها الآن')));
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await context.read<AppProvider>().exportPendingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم إنشاء ملف المزامنة ومشاركته')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = 'تعذّر التصدير: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _reExport() async {
    _lastAction = _reExport;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final ok = await context.read<AppProvider>().reExportLastSync();
      if (!mounted) return;
      if (!ok) {
        setState(() => _lastError = 'لا يوجد ملف سابق لإعادة إرساله');
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تمت إعادة مشاركة آخر ملف')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = 'تعذّر إعادة الإرسال: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importIncoming() async {
    _lastAction = _importIncoming;
    final app = context.read<AppProvider>();
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final content = await app.pickSyncAckFile();
      if (content == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final result = await app.importIncomingSyncFile(content);
      if (!mounted) return;
      final msg = result.type == 'sync_ack'
          ? 'تم تأكيد ${result.ackedCount} عملية كمتزامنة'
          : 'تم التحديث: ${result.productsUpdated} منتج، ${result.customersUpdated} عميل'
              '${result.settingsUpdated ? '، وبيانات الشركة' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = 'تعذّر الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _syncFirebaseNow() async {
    _lastAction = _syncFirebaseNow;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final message = await DbService.instance.pullFromFirestore(isManager: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = 'تعذّر الوصول لفايربيس: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _editDeviceName(String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم الجهاز'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty && mounted) {
      await context.read<AppProvider>().updateCurrentDeviceName(result.trim());
      if (mounted) setState(() {});
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'لم تتم أي مزامنة بعد';
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'اليوم $time';
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday =
        d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
    if (wasYesterday) return 'أمس $time';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} $time';
  }

  String _pendingBreakdownText(PendingSummary s) {
    final parts = <String>[];
    if (s.invoices.isNotEmpty) parts.add('${s.invoices.length} فاتورة');
    if (s.receipts.isNotEmpty) parts.add('${s.receipts.length} سند');
    if (s.customers.isNotEmpty) parts.add('${s.customers.length} عميل');
    if (s.products.isNotEmpty) parts.add('${s.products.length} منتج');
    if (parts.isEmpty) return 'لا توجد بيانات جديدة';
    return '${parts.join('، ')} بانتظار التصدير';
  }

  SyncPulseState get _pulseState {
    if (_busy) return SyncPulseState.syncing;
    if (_lastError != null) return SyncPulseState.failed;
    if (_pendingCount > 0) return SyncPulseState.pending;
    return SyncPulseState.synced;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final rep = app.currentUser;
    final state = _pulseState;

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
        title = 'لديك $_pendingCount عملية لم تُرسل بعد';
        subtitle = _loadingCount
            ? 'جارٍ الحساب...'
            : '${_pendingBreakdownText(_pendingSummary!)} · آخر مزامنة ${_formatDate(rep?.lastSyncAt)}';
        ctaLabel = 'تصدير وإرسال الآن';
        onCta = _busy ? null : _export;
        break;
      case SyncPulseState.synced:
        title = 'بياناتك بأمان';
        subtitle = 'كل الفواتير والسندات مُرسلة · آخر مزامنة ${_formatDate(rep?.lastSyncAt)}';
        ctaLabel = 'تحقّق من التحديثات';
        ctaKind = SyncHeroCta.ghost;
        onCta = _busy ? null : _importIncoming;
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('مركز المزامنة')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SyncHeroCard(
              state: state,
              progress: null,
              centerLabel: '$_pendingCount',
              title: title,
              subtitle: subtitle,
              ctaLabel: ctaLabel,
              ctaKind: ctaKind,
              onCtaPressed: onCta,
              onTap: _pendingCount > 0
                  ? () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SyncPendingPreviewScreen()))
                  : null,
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
                    line1: 'يُرفع تلقائيًا بالخلفية',
                    infoText:
                        'بياناتك تُرفع لفايربيس تلقائيًا في الخلفية فور حفظ أي فاتورة أو سند، دون أي إجراء منك.',
                    quickActions: [
                      SyncQuickAction(
                        icon: Icons.sync,
                        label: 'مزامنة فايربيس الآن',
                        onPressed: _busy ? () {} : _syncFirebaseNow,
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
                    line1: _lastExport == null
                        ? 'لم يُصدَّر بعد'
                        : 'آخر إرسال ${_formatDate(_lastExport!.at)}',
                    infoText:
                        'قناة احتياطية تعمل حتى بدون إنترنت — تُصدّر ملفًا وترسله للمدير، ويرد عليك بملف اعتماد.',
                    quickActions: [
                      SyncQuickAction(
                        icon: Icons.file_upload_outlined,
                        label: 'تصدير وإرسال الآن',
                        onPressed: _busy ? () {} : _export,
                      ),
                      if (_lastExport != null)
                        SyncQuickAction(
                          icon: Icons.refresh,
                          label: 'إعادة إرسال آخر ملف',
                          onPressed: _busy ? () {} : _reExport,
                        ),
                      SyncQuickAction(
                        icon: Icons.file_download_outlined,
                        label: 'استيراد تحديثات',
                        onPressed: _busy ? () {} : _importIncoming,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('بيانات المندوب',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    _InfoRow(
                        label: 'رقم المندوب',
                        value: (rep != null && rep.repNumber.isNotEmpty) ? rep.repNumber : '—'),
                    _InfoRow(label: 'اسم المندوب', value: rep?.displayName ?? '—'),
                    _InfoRow(
                      label: 'اسم الجهاز',
                      value: (rep != null && rep.deviceName.isNotEmpty)
                          ? rep.deviceName
                          : 'غير محدد',
                      onEdit: rep == null ? null : () => _editDeviceName(rep.deviceName),
                    ),
                    _InfoRow(label: 'إصدار قاعدة البيانات', value: '${DbService.schemaVersion}'),
                    _InfoRow(label: 'رقم آخر تحديث مستورد', value: '— (قريبًا)'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('معاينة العمليات المعلّقة'),
                subtitle: _loadingCount
                    ? const Text('جارٍ الحساب...')
                    : Text('$_pendingCount عملية بانتظار المزامنة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SyncPendingPreviewScreen())),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('استيراد تحديثات'),
                subtitle: const Text('تأكيد مزامنة أو تحديث منتجات/عملاء من المدير'),
                trailing: const Icon(Icons.chevron_left),
                onTap: _busy ? null : _importIncoming,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onEdit;
  const _InfoRow({required this.label, required this.value, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (onEdit != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onEdit,
              child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}
