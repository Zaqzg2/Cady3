import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'sync_pending_preview_screen.dart';

/// شاشة المزامنة عند المندوب: تصدير العمليات المعلّقة، معاينتها، إعادة
/// إرسال آخر ملف، بيانات الجهاز/المندوب، واستيراد تأكيد المزامنة من
/// المدير. دفع منتجات/أسعار جديدة من المدير سيُضاف مع شاشة "إنشاء
/// تحديث" عنده (مرحلة قادمة)
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  int _pendingCount = 0;
  bool _loadingCount = true;
  ({String json, String fileName, DateTime at})? _lastExport;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loadingCount = true);
    final app = context.read<AppProvider>();
    final summary = await app.getPendingSyncSummary();
    final last = await app.getLastExport();
    if (!mounted) return;
    setState(() {
      _pendingCount = summary.total;
      _lastExport = last;
      _loadingCount = false;
    });
  }

  Future<void> _export() async {
    final app = context.read<AppProvider>();
    if (_pendingCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات جديدة لتصديرها الآن')));
      return;
    }
    setState(() => _busy = true);
    try {
      await app.exportPendingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء ملف المزامنة ومشاركته')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر التصدير: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _reExport() async {
    setState(() => _busy = true);
    final ok = await context.read<AppProvider>().reExportLastSync();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'تمت إعادة مشاركة آخر ملف' : 'لا يوجد ملف سابق لإعادة إرساله')));
  }

  Future<void> _importIncoming() async {
    final app = context.read<AppProvider>();
    setState(() => _busy = true);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر الاستيراد: $e')));
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null && mounted) {
      await context.read<AppProvider>().updateCurrentDeviceName(result);
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'لم تتم أي مزامنة بعد';
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'اليوم $time';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} $time';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final rep = app.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('بيانات المندوب',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    _InfoRow(label: 'رقم المندوب', value: (rep != null && rep.repNumber.isNotEmpty) ? rep.repNumber : '—'),
                    _InfoRow(label: 'اسم المندوب', value: rep?.displayName ?? '—'),
                    _InfoRow(
                      label: 'اسم الجهاز',
                      value: (rep != null && rep.deviceName.isNotEmpty) ? rep.deviceName : 'غير محدد',
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
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('آخر مزامنة'),
                subtitle: Text(_formatDate(rep?.lastSyncAt)),
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('تصدير بيانات اليوم'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
            ),
            const SizedBox(height: 6),
            Text(
              'تبقى العمليات "معلّقة" حتى يعتمد المدير استيرادها، حتى بعد التصدير',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (_busy || _lastExport == null) ? null : _reExport,
              icon: const Icon(Icons.refresh),
              label: Text(_lastExport == null
                  ? 'لا يوجد ملف سابق بعد'
                  : 'إعادة تصدير آخر ملف (${_formatDate(_lastExport!.at)})'),
            ),
            const SizedBox(height: 24),
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
              child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
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
