import 'package:flutter/material.dart';

import '../services/data_stats_service.dart';
import '../services/cleanup_service.dart';

/// حجم البيانات الحالي (فواتير، سندات، عملاء، منتجات، مساحة التخزين)
/// وتنظيف الصور غير المستخدمة. النسخ الاحتياطي (يدوي/تلقائي/CSV) انتقل
/// بالكامل لشاشته المستقلة BackupManagementScreen — هذه الشاشة كانت
/// تكرّر نفس عناصر التحكم فيها (زر النسخ الآن، جدولة تلقائي، تصدير CSV)
/// فصار للمستخدم صفحتان لنفس الإجراء؛ أُزيل التكرار وبقيت هذه الشاشة
/// لما هو خاص بها فقط: حجم البيانات والتنظيف
class SettingsDataScreen extends StatefulWidget {
  const SettingsDataScreen({super.key});

  @override
  State<SettingsDataScreen> createState() => _SettingsDataScreenState();
}

class _SettingsDataScreenState extends State<SettingsDataScreen> {
  bool _busy = false;
  late Future<DataStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = DataStatsService.collect();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حجم البيانات')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
