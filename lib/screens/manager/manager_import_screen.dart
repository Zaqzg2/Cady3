import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../services/manager_sync_service.dart';

/// استيراد ملف مزامنة من مندوب: اختيار الملف، معاينة الأرقام (فواتير/
/// سندات/عملاء جدد/تكرارات/أخطاء)، ثم اعتماد أو إلغاء. الاعتماد فقط هو
/// ما يكتب البيانات فعليًا ويحوّلها إلى "متزامنة"
class ManagerImportScreen extends StatefulWidget {
  const ManagerImportScreen({super.key});

  @override
  State<ManagerImportScreen> createState() => _ManagerImportScreenState();
}

class _ManagerImportScreenState extends State<ManagerImportScreen> {
  ImportPreview? _preview;
  String? _ackJson;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await ManagerSyncService.instance.pickAndPreview();
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e) {
      setState(() => _error = 'تعذّرت قراءة الملف: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    if (_preview == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ack = await ManagerSyncService.instance.commitImport(_preview!);
      if (!mounted) return;
      await context.read<AppProvider>().refreshCustomersAndProducts();
      if (!mounted) return;
      setState(() => _ackJson = ack);
    } catch (e) {
      setState(() => _error = 'تعذّر الاعتماد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _preview = null;
      _ackJson = null;
      _error = null;
    });
  }

  Future<void> _shareAck() async {
    if (_ackJson == null || _preview == null) return;
    await ManagerSyncService.instance.shareAck(_ackJson!, _preview!.repDisplayName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد ملف مندوب')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _preview == null
                ? _buildPickState()
                : _ackJson == null
                    ? _buildPreviewState(_preview!)
                    : _buildDoneState(_preview!),
      ),
    );
  }

  Widget _buildPickState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.file_download_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('اختر ملف المزامنة المُرسَل من المندوب', textAlign: TextAlign.center),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('اختيار ملف مندوب'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewState(ImportPreview p) {
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('من: ${p.repDisplayName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(p.fileName, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const Divider(height: 24),
                _StatLine(label: 'عدد الفواتير', value: p.invoicesCount, color: Colors.indigo),
                _StatLine(label: 'عدد السندات', value: p.receiptsCount, color: Colors.teal),
                _StatLine(label: 'العملاء الجدد', value: p.newCustomersCount, color: Colors.green),
                _StatLine(label: 'التكرارات', value: p.duplicatesCount, color: Colors.orange),
                _StatLine(label: 'الأخطاء', value: p.errorsCount, color: Colors.red),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _reset, child: const Text('إلغاء')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(onPressed: _approve, child: const Text('اعتماد')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDoneState(ImportPreview p) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          const SizedBox(height: 16),
          Text('تم اعتماد بيانات ${p.repDisplayName} بنجاح', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'شارك تأكيد الاستلام مع المندوب حتى تتحول عملياته من "معلّقة" إلى "متزامنة" على جهازه',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _shareAck,
            icon: const Icon(Icons.share_outlined),
            label: const Text('مشاركة تأكيد الاستلام'),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: _reset, child: const Text('استيراد ملف آخر')),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatLine({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
