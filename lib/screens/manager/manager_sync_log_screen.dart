import 'package:flutter/material.dart';

import '../../services/manager_sync_service.dart';
import 'manager_import_screen.dart';

class _LogItem {
  final DateTime time;
  final bool isImport;
  final String title;
  final String subtitle;
  final bool hasError;

  const _LogItem({
    required this.time,
    required this.isImport,
    required this.title,
    required this.subtitle,
    this.hasError = false,
  });
}

/// سجل موحّد لكل عمليات المزامنة عند المدير: الاستيراد من المندوبين
/// (سجل الاستيراد) والتصدير إليهم (سجل التصدير)، مرتّبة زمنيًا معًا
class ManagerSyncLogScreen extends StatefulWidget {
  const ManagerSyncLogScreen({super.key});

  @override
  State<ManagerSyncLogScreen> createState() => _ManagerSyncLogScreenState();
}

class _ManagerSyncLogScreenState extends State<ManagerSyncLogScreen> {
  List<_LogItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final imports = await ManagerSyncService.instance.getLog();
    final exports = await ManagerSyncService.instance.getExportLog();

    final items = <_LogItem>[
      for (final e in imports)
        _LogItem(
          time: e.importedAt,
          isImport: true,
          title: e.repDisplayName.isNotEmpty ? e.repDisplayName : e.fileName,
          subtitle: '${e.totalRecords} سجل'
              '${e.duplicatesCount > 0 ? ' • ${e.duplicatesCount} تكرار' : ''}'
              '${e.errorsCount > 0 ? ' • ${e.errorsCount} خطأ' : ''}',
          hasError: e.errorsCount > 0,
        ),
      for (final e in exports)
        _LogItem(
          time: e.createdAt,
          isImport: false,
          title: 'تحديث ← ${e.targetLabel}',
          subtitle: [
            if (e.includedProducts) '${e.productsCount} منتج',
            if (e.includedCustomers) '${e.customersCount} عميل',
            if (e.includedSettings) 'بيانات الشركة',
          ].join(' • '),
        ),
    ];
    items.sort((a, b) => b.time.compareTo(a.time));

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _fmt(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المزامنة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ManagerImportScreen()));
          _load();
        },
        icon: const Icon(Icons.file_download_outlined),
        label: const Text('استيراد جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('لا توجد عمليات مزامنة بعد'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = _items[i];
                    final color = e.hasError
                        ? Colors.red
                        : (e.isImport ? Colors.green : Colors.indigo);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.12),
                          child: Icon(
                            e.hasError
                                ? Icons.error_outline
                                : (e.isImport
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward),
                            color: color,
                            size: 18,
                          ),
                        ),
                        title: Text(e.title),
                        subtitle: Text('${_fmt(e.time)} • ${e.subtitle}'),
                      ),
                    );
                  },
                ),
    );
  }
}
