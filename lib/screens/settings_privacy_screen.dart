import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company_settings.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';

/// الخصوصية والأمان: كلمة المرور، القفل التلقائي بعد الخمول، إخفاء
/// الأرقام المالية بالتطبيقات الأخيرة، وتسجيل الخروج التلقائي
class SettingsPrivacyScreen extends StatefulWidget {
  const SettingsPrivacyScreen({super.key});

  @override
  State<SettingsPrivacyScreen> createState() => _SettingsPrivacyScreenState();
}

class _SettingsPrivacyScreenState extends State<SettingsPrivacyScreen> {
  bool _passwordEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    final set = await AuthService.instance.isPasswordSet();
    if (mounted) setState(() {
      _passwordEnabled = set;
      _loading = false;
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _update(void Function(CompanySettings s) mutate) async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    mutate(s);
    await app.saveSettings(s);
    setState(() {});
  }

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

  void _showBiometricNote() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('البصمة / الوجه'),
        content: const Text(
            'يتطلب تفعيل هذا الخيار تحديثًا برمجيًا إضافيًا على مستوى نظام أندرويد '
            '(لم يُفعَّل بعد في هذه النسخة). حاليًا يمكنك حماية التطبيق بكلمة المرور '
            'مع القفل التلقائي بعد الخمول.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppProvider>().settings;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('الخصوصية والأمان')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('حماية التطبيق بكلمة مرور',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (!_passwordEnabled)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.lock),
                label: const Text('تفعيل الحماية بكلمة مرور'),
                onPressed: _setOrChangePassword,
              ),
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

          const Text('قفل تلقائي بعد الخمول', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('يعمل فقط إن كانت كلمة المرور مفعّلة',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          ...AutoLockOption.values.map((opt) => RadioListTile<AutoLockOption>(
                contentPadding: EdgeInsets.zero,
                title: Text(_autoLockLabel(opt)),
                value: opt,
                groupValue: s.autoLockOption,
                onChanged: _passwordEnabled
                    ? (v) => _update((s) => s.autoLockOption = v!)
                    : null,
              )),
          const Divider(height: 32),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.fingerprint),
            title: const Text('بصمة / وجه بدل كلمة المرور'),
            subtitle: const Text('غير مفعّل بعد بهذه النسخة'),
            trailing: const Icon(Icons.info_outline, size: 18),
            onTap: _showBiometricNote,
          ),
          const Divider(height: 32),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إخفاء الأرقام المالية عند التبديل بين التطبيقات'),
            subtitle: const Text('تُغطّى الشاشة بشعار الشركة عند مغادرة التطبيق مؤقتًا'),
            value: s.hideAmountsInRecents,
            onChanged: (v) => _update((s) => s.hideAmountsInRecents = v),
          ),
          const Divider(height: 32),

          const Text('تسجيل خروج تلقائي بعد عدم الاستخدام',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: s.autoLogoutHours,
            items: const [
              DropdownMenuItem(value: 0, child: Text('معطّل')),
              DropdownMenuItem(value: 1, child: Text('بعد ساعة')),
              DropdownMenuItem(value: 6, child: Text('بعد 6 ساعات')),
              DropdownMenuItem(value: 24, child: Text('بعد 24 ساعة')),
              DropdownMenuItem(value: 72, child: Text('بعد 3 أيام')),
            ],
            onChanged: _passwordEnabled
                ? (v) => _update((s) => s.autoLogoutHours = v ?? 0)
                : null,
          ),
        ],
      ),
    );
  }

  String _autoLockLabel(AutoLockOption opt) {
    switch (opt) {
      case AutoLockOption.immediate:
        return 'فورًا';
      case AutoLockOption.oneMinute:
        return 'بعد دقيقة';
      case AutoLockOption.fiveMinutes:
        return 'بعد 5 دقائق';
      case AutoLockOption.never:
        return 'أبدًا';
    }
  }
}
