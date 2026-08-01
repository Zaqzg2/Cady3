import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/company_settings.dart';
import '../providers/app_provider.dart';
import '../services/print_service.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';

/// شاشة الإعدادات: الشعار، بيانات الشركة، اسم المندوب، جدول الأصناف
/// (الأعمدة/حجم الخط)، طابعة البلوتوث 80مم، والوضع الليلي
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _companyName;
  late TextEditingController _companyPhone;
  late TextEditingController _companyAddress;
  late TextEditingController _repName;
  double _fontSize = 9;
  double _rowSpacing = 4;
  List<BluetoothInfo> _pairedDevices = [];
  String? _selectedPrinterMac;
  bool _passwordEnabled = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppProvider>().settings;
    _companyName = TextEditingController(text: s.companyName);
    _companyPhone = TextEditingController(text: s.companyPhone);
    _companyAddress = TextEditingController(text: s.companyAddress);
    _repName = TextEditingController(text: s.repName);
    _fontSize = s.tableFontSize;
    _rowSpacing = s.rowSpacing;
    _selectedPrinterMac = s.printerAddress;
    _loadPairedDevices();
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    final set = await AuthService.instance.isPasswordSet();
    if (mounted) setState(() => _passwordEnabled = set);
  }

  Future<void> _loadPairedDevices() async {
    try {
      final list = await PrintService.instance.getPairedDevices();
      if (mounted) setState(() => _pairedDevices = list);
    } catch (_) {
      // البلوتوث قد لا يكون مفعّلاً أو الصلاحيات غير ممنوحة بعد
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.logoPath = file.path;
    await app.saveSettings(s);
    setState(() {});
  }

  Future<void> _connectPrinter(BluetoothInfo device) async {
    final ok = await PrintService.instance.connect(device.macAdress);
    if (ok) {
      final app = context.read<AppProvider>();
      final s = app.settings;
      s.printerAddress = device.macAdress;
      s.printerName = device.name;
      await app.saveSettings(s);
      setState(() => _selectedPrinterMac = device.macAdress);
      _snack('تم الاتصال بالطابعة ${device.name}');
    } else {
      _snack('تعذّر الاتصال بالطابعة');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _saveGeneral() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.companyName = _companyName.text.trim();
    s.companyPhone = _companyPhone.text.trim();
    s.companyAddress = _companyAddress.text.trim();
    s.repName = _repName.text.trim();
    s.tableFontSize = _fontSize;
    s.rowSpacing = _rowSpacing;
    await app.saveSettings(s);
    _snack('تم حفظ الإعدادات');
  }

  Future<void> _toggleDarkMode(bool value) async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.darkMode = value;
    await app.saveSettings(s);
  }

  // ---------------- حماية بكلمة مرور ----------------
  Future<void> _setOrChangePassword() async {
    final ctrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_passwordEnabled ? 'تغيير كلمة المرور' : 'تعيين كلمة مرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
            ),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    if (ctrl.text.isEmpty || ctrl.text != confirmCtrl.text) {
      _snack('كلمتا المرور غير متطابقتين أو فارغتين');
      return;
    }
    await AuthService.instance.setPassword(ctrl.text);
    setState(() => _passwordEnabled = true);
    _snack('تم تفعيل حماية التطبيق بكلمة المرور');
  }

  Future<void> _disablePassword() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الحماية'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'أدخل كلمة المرور الحالية للتأكيد'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء الحماية')),
        ],
      ),
    );
    if (ok != true) return;
    final correct = await AuthService.instance.checkPassword(ctrl.text);
    if (!correct) {
      _snack('كلمة المرور غير صحيحة');
      return;
    }
    await AuthService.instance.removePassword();
    setState(() => _passwordEnabled = false);
    _snack('تم إلغاء حماية التطبيق');
  }

  // ---------------- نسخ احتياطي ----------------
  Future<void> _exportBackup() async {
    try {
      await BackupService.instance.exportAndShare();
      _snack('تم إنشاء النسخة الاحتياطية بنجاح');
    } catch (e) {
      _snack('تعذّر إنشاء النسخة الاحتياطية: $e');
    }
  }

  Future<void> _importBackup() async {
    final path = await BackupService.instance.pickBackupFilePath();
    if (path == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: const Text(
            'سيتم دمج بيانات الملف المختار مع البيانات الحالية (لن يتم حذف أي شيء). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استيراد')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await BackupService.instance.importFromFile(path);
      if (mounted) {
        await context.read<AppProvider>().init();
        _snack('تم استيراد النسخة الاحتياطية بنجاح');
      }
    } catch (e) {
      _snack('تعذّر استيراد الملف: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('شعار الشركة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.grey.shade200,
                backgroundImage:
                    s.logoPath != null ? FileImage(File(s.logoPath!)) : null,
                child: s.logoPath == null ? const Icon(Icons.image, size: 30) : null,
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text('تحميل الشعار'),
                onPressed: _pickLogo,
              ),
            ],
          ),
          const Divider(height: 32),

          const Text('بيانات الشركة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
              controller: _companyName,
              decoration: const InputDecoration(labelText: 'اسم الشركة')),
          const SizedBox(height: 8),
          TextField(
              controller: _companyPhone,
              decoration: const InputDecoration(labelText: 'هاتف الشركة')),
          const SizedBox(height: 8),
          TextField(
              controller: _companyAddress,
              decoration: const InputDecoration(labelText: 'عنوان الشركة')),
          const Divider(height: 32),

          const Text('بيانات المندوب', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
              controller: _repName,
              decoration: const InputDecoration(labelText: 'اسم المندوب')),
          const Divider(height: 32),

          const Text('إعدادات جدول الفاتورة',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('حجم خط الجدول: ${_fontSize.toStringAsFixed(0)}'),
          Slider(
            value: _fontSize,
            min: 6,
            max: 14,
            divisions: 8,
            label: _fontSize.toStringAsFixed(0),
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          Text('تباعد صفوف الجدول: ${_rowSpacing.toStringAsFixed(0)}'),
          Slider(
            value: _rowSpacing,
            min: 0,
            max: 16,
            divisions: 8,
            label: _rowSpacing.toStringAsFixed(0),
            onChanged: (v) => setState(() => _rowSpacing = v),
          ),
          const Divider(height: 32),

          const Text('طابعة البلوتوث الحرارية 80مم',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث قائمة الأجهزة المقترنة'),
            onPressed: _loadPairedDevices,
          ),
          const SizedBox(height: 8),
          if (_pairedDevices.isEmpty)
            const Text('لا توجد أجهزة مقترنة — اقرن الطابعة أولًا من إعدادات بلوتوث الهاتف')
          else
            ..._pairedDevices.map((d) => RadioListTile<String>(
                  title: Text(d.name),
                  subtitle: Text(d.macAdress),
                  value: d.macAdress,
                  groupValue: _selectedPrinterMac,
                  onChanged: (_) => _connectPrinter(d),
                )),
          const Divider(height: 32),

          SwitchListTile(
            title: const Text('الوضع الليلي'),
            value: s.darkMode,
            onChanged: _toggleDarkMode,
          ),
          const Divider(height: 32),

          const Text('حماية التطبيق بكلمة مرور',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (!_passwordEnabled)
            OutlinedButton.icon(
              icon: const Icon(Icons.lock),
              label: const Text('تفعيل الحماية بكلمة مرور'),
              onPressed: _setOrChangePassword,
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.password),
                    label: const Text('تغيير كلمة المرور'),
                    onPressed: _setOrChangePassword,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: const Text('إلغاء الحماية'),
                    onPressed: _disablePassword,
                  ),
                ),
              ],
            ),
          const Divider(height: 32),

          const Text('النسخ الاحتياطي', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('يشمل: العملاء، المنتجات، الفواتير، السندات، والإعدادات',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('تصدير نسخة احتياطية'),
                  onPressed: _exportBackup,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('استيراد نسخة'),
                  onPressed: _importBackup,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات'),
            onPressed: _saveGeneral,
          ),
        ],
      ),
    );
  }
}
