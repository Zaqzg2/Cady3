import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'setup_manager_screen.dart';

/// شاشة تسجيل الدخول: اسم المستخدم وكلمة المرور يحدّدان هوية المستخدم
/// (مدير أو مندوب) وبالتالي الواجهة التي تظهر بعد الدخول
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _checking = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok =
        await context.read<AppProvider>().login(_userCtrl.text, _passCtrl.text);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!ok) {
      setState(() {
        _error = 'اسم المستخدم أو كلمة المرور غير صحيحة، أو الحساب موقوف';
        _passCtrl.clear();
      });
    }
    // عند النجاح يُحدّث AppProvider currentUser وتتبدّل الشاشة تلقائيًا
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppTheme.primary.withOpacity(0.045),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppTheme.primary, width: 1.6),
      ),
      prefixIcon: Icon(icon, color: AppTheme.primary),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    // نفس منطق تسجيل الدخول القديم بالكامل (login/AppProvider/التنقّل)،
    // فقط بنمط بصري جديد: رأس بلون العلامة الأحمر ثم لوحة بيضاء بزوايا
    // علوية دائرية تحمل النموذج — بدل الشكل المتوسّط المسطّح القديم
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 44, 24, 30),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'كادي',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'سجّل الدخول لمتابعة العمل',
                      style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                constraints:
                    BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.52),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _userCtrl,
                      decoration:
                          _fieldDecoration(label: 'اسم المستخدم', icon: Icons.person_outline),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: _fieldDecoration(
                        label: 'كلمة المرور',
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: Colors.grey.shade500,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: AppTheme.syncErrorSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 18, color: AppTheme.syncError),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: AppTheme.syncError, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _checking ? null : _submit,
                        child: _checking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('دخول',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _checking
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SetupManagerScreen())),
                      child: const Text('أول مرة تستخدم التطبيق؟ إنشاء حساب مدير جديد'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
