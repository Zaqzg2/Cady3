import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../models/user_account.dart';
import '../../services/manager_sync_service.dart';

/// إنشاء تحديث: يختار المدير ما يُصدَّر (منتجات/عملاء/إعدادات) ولمن
/// (الكل أو مندوب محدد)، فيُنشأ ملف واحد يمكن مشاركته مباشرة
class ManagerExportScreen extends StatefulWidget {
  const ManagerExportScreen({super.key});

  @override
  State<ManagerExportScreen> createState() => _ManagerExportScreenState();
}

class _ManagerExportScreenState extends State<ManagerExportScreen> {
  bool _includeProducts = true;
  bool _includeCustomers = true;
  bool _includeSettings = false;
  String? _targetRepId; // null = كل المندوبين
  List<UserAccount> _reps = [];
  bool _loadingReps = true;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _loadReps();
  }

  Future<void> _loadReps() async {
    final users = await context.read<AppProvider>().getAllUsers();
    if (!mounted) return;
    setState(() {
      _reps = users.where((u) => u.role == UserRole.rep).toList();
      _loadingReps = false;
    });
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final targetLabel = _targetRepId == null
          ? 'كل المندوبين'
          : _reps.firstWhere((r) => r.id == _targetRepId).displayName;
      final json = await ManagerSyncService.instance.buildUpdatePackage(
        includeProducts: _includeProducts,
        includeCustomers: _includeCustomers,
        includeSettings: _includeSettings,
        targetRepId: _targetRepId ?? '',
        targetLabel: targetLabel,
      );
      await ManagerSyncService.instance.shareUpdatePackage(json, targetLabel);
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر الإنشاء: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canCreate =>
      !_busy && (_includeProducts || _includeCustomers || _includeSettings);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء تحديث')),
      body: _done ? _buildDoneState() : _buildFormState(),
    );
  }

  Widget _buildDoneState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          const SizedBox(height: 16),
          const Text('تم إنشاء ملف التحديث ومشاركته'),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() => _done = false),
            child: const Text('إنشاء تحديث آخر'),
          ),
        ],
      ),
    );
  }

  Widget _buildFormState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('البيانات المُضمَّنة', style: TextStyle(fontWeight: FontWeight.bold)),
        Card(
          child: Column(
            children: [
              CheckboxListTile(
                title: const Text('المنتجات (والأسعار)'),
                value: _includeProducts,
                onChanged: (v) => setState(() => _includeProducts = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('العملاء'),
                value: _includeCustomers,
                onChanged: (v) => setState(() => _includeCustomers = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('الإعدادات'),
                subtitle: const Text('اسم الشركة، الهاتف، العنوان، نص أسفل الفاتورة فقط'),
                value: _includeSettings,
                onChanged: (v) => setState(() => _includeSettings = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('العروض'),
                subtitle: const Text('ميزة العروض غير متوفرة في التطبيق حاليًا'),
                value: false,
                onChanged: null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('الوجهة', style: TextStyle(fontWeight: FontWeight.bold)),
        Card(
          child: _loadingReps
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  children: [
                    RadioListTile<String?>(
                      title: const Text('كل المندوبين'),
                      value: null,
                      groupValue: _targetRepId,
                      onChanged: (v) => setState(() => _targetRepId = v),
                    ),
                    for (final rep in _reps)
                      RadioListTile<String?>(
                        title: Text(rep.displayName),
                        subtitle: rep.repNumber.isNotEmpty ? Text('#${rep.repNumber}') : null,
                        value: rep.id,
                        groupValue: _targetRepId,
                        onChanged: (v) => setState(() => _targetRepId = v),
                      ),
                    if (_reps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا يوجد مندوبون مضافون بعد',
                            style: TextStyle(color: Colors.black54)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _canCreate ? _create : null,
          icon: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.file_upload_outlined),
          label: const Text('إنشاء الملف ومشاركته'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
        ),
      ],
    );
  }
}
