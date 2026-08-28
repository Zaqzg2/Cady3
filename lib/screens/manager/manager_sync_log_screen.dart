import 'package:flutter/material.dart';

import '../../services/manager_sync_service.dart';
import '../../theme/app_theme.dart';
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
/// بعرض Timeline — خط متصل بين كل عملية والتالية، بدل بطاقات منفصلة
/// بلا رابط بصري بينها
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

  Color _colorFor(_LogItem e) {
    if (e.hasError) return AppTheme.syncError;
    return e.isImport ? AppTheme.syncSuccess : AppTheme.primary;
  }

  IconData _iconFor(_LogItem e) {
    if (e.hasError) return Icons.error_outline;
    return e.isImport ? Icons.arrow_downward : Icons.arrow_upward;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المزامنة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ManagerImportScreen()));
          _load();
        },
        icon: const Icon(Icons.file_download_outlined),
        label: const Text('استيراد جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('لا توجد عمليات مزامنة بعد'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final e = _items[i];
                    final isLast = i == _items.length - 1;
                    final color = _colorFor(e);
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withOpacity(0.12),
                                  border: Border.all(color: color, width: 1.4),
                                ),
                                alignment: Alignment.center,
                                child: Icon(_iconFor(e), color: color, size: 16),
                              ),
                              if (!isLast)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_fmt(e.time)}${e.subtitle.isNotEmpty ? ' • ${e.subtitle}' : ''}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
