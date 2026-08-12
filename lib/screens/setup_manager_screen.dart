import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';

/// تظهر مرة واحدة فقط عند أول تشغيل للتطبيق (لا يوجد أي حساب بعد) —
/// تنشئ أول حساب، وهو حساب المدير دائمًا، وتبدأ جلسته تلقائيًا
class SetupManagerScreen extends StatefulWidget {
  const SetupManagerScreen({super.key});

  @override
  State<SetupManagerScreen> createState() => _SetupManagerScreenState();
}

class _SetupManagerScreenState extends State<SetupManagerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passCtrl.text != _passConfirmCtrl.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AppProvider>().createFirstManager(
            username: _userCtrl.text,
            rawPassword: _passCtrl.text,
            displayName: _nameCtrl.text,
          );
      // بعد النجاح يُحدّث AppProvider usersExist/currentUser وتتبدّل
      // الشاشة تلقائيًا عبر Consumer<AppProvider> بلا أي تنقّل يدوي هنا
    } catch (e) {
      setState(() => _error = 'تعذّر إنشاء الحساب: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.admin_panel_settings, size: 56),
                  const SizedBox(height: 12),
                  const Text('إعداد حساب المدير',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'هذا أول تشغيل للتطبيق — أنشئ حساب المدير الرئيسي أولاً، ثم يمكنك إضافة حسابات المندوبين لاحقًا',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'اسمك', border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'كلمة المرور',
                        border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.length < 4) ? '٤ أحرف على الأقل' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passConfirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'تأكيد كلمة المرور',
                        border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'مطلوب' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('إنشاء الحساب والمتابعة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
