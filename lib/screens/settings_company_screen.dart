import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/image_store.dart';
import '../widgets/signature_pad_widget.dart';
import '../widgets/stored_image.dart';

/// بيانات الشركة والمندوب: الشعار، اسم/هاتف/عنوان الشركة، اسم/هاتف
/// المندوب، توقيعه الافتراضي المحفوظ، ونص التذييل الثابت أسفل كل فاتورة
class SettingsCompanyScreen extends StatefulWidget {
  const SettingsCompanyScreen({super.key});

  @override
  State<SettingsCompanyScreen> createState() => _SettingsCompanyScreenState();
}

class _SettingsCompanyScreenState extends State<SettingsCompanyScreen> {
  late TextEditingController _companyName;
  late TextEditingController _companyPhone;
  late TextEditingController _companyAddress;
  late TextEditingController _repName;
  late TextEditingController _repPhone;
  late TextEditingController _footerText;
  String? _defaultSignaturePath;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppProvider>().settings;
    _companyName = TextEditingController(text: s.companyName);
    _companyPhone = TextEditingController(text: s.companyPhone);
    _companyAddress = TextEditingController(text: s.companyAddress);
    _repName = TextEditingController(text: s.repName);
    _repPhone = TextEditingController(text: s.repPhone);
    _footerText = TextEditingController(text: s.invoiceFooterText);
    _defaultSignaturePath = s.defaultRepSignaturePath;
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final app = context.read<AppProvider>();
    final s = app.settings;
    final key = await ImageStore.instance.save(bytes, key: s.logoPath);
    s.logoPath = key;
    await app.saveSettings(s);
    setState(() {});
  }

  Future<void> _removeLogo() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    await ImageStore.instance.delete(s.logoPath);
    s.logoPath = null;
    await app.saveSettings(s);
    setState(() {});
  }

  Future<void> _save() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.companyName = _companyName.text.trim();
    s.companyPhone = _companyPhone.text.trim();
    s.companyAddress = _companyAddress.text.trim();
    s.repName = _repName.text.trim();
    s.repPhone = _repPhone.text.trim();
    s.invoiceFooterText =
        _footerText.text.trim().isEmpty ? 'شكرًا لتعاملكم معنا' : _footerText.text.trim();
    s.defaultRepSignaturePath = _defaultSignaturePath;
    await app.saveSettings(s);
    if (mounted) _snack('تم حفظ البيانات');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppProvider>().settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('بيانات الشركة والمندوب'),
        actions: [
          TextButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('شعار الشركة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              StoredAvatar(imageKey: s.logoPath, radius: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload),
                      label: Text(s.logoPath == null ? 'رفع الشعار' : 'تغيير الشعار'),
                      onPressed: _pickLogo,
                    ),
                    if (s.logoPath != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('حذف', style: TextStyle(color: Colors.red)),
                        onPressed: _removeLogo,
                      ),
                  ],
                ),
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
              keyboardType: TextInputType.phone,
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
          const SizedBox(height: 8),
          TextField(
              controller: _repPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'هاتف المندوب')),
          const SizedBox(height: 12),
          const Text('التوقيع الافتراضي للمندوب',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Text('يُستخدم تلقائيًا في كل سند جديد بدل التوقيع يدويًا في كل مرة',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          SignaturePadWidget(
            key: ValueKey(_defaultSignaturePath),
            label: 'توقيع المندوب الافتراضي',
            existingPath: _defaultSignaturePath,
            onSaved: (path) => setState(() => _defaultSignaturePath = path),
          ),
          const Divider(height: 32),

          const Text('نص أسفل الفاتورة والسند',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('يظهر في نهاية كل فاتورة وسند مطبوع', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          TextField(
            controller: _footerText,
            decoration: const InputDecoration(hintText: 'شكرًا لتعاملكم معنا'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
