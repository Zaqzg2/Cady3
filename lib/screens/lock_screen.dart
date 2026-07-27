import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// شاشة قفل التطبيق: تظهر عند بدء التشغيل إذا كانت كلمة المرور مفعّلة.
/// لوحة أرقام كبيرة مناسبة للمس.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entered = '';
  String? _error;
  bool _checking = false;

  Future<void> _submit() async {
    setState(() => _checking = true);
    final ok = await AuthService.instance.checkPassword(_entered);
    setState(() => _checking = false);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'كلمة المرور غير صحيحة';
        _entered = '';
      });
    }
  }

  void _tap(String digit) {
    if (_entered.length >= 8) return;
    setState(() {
      _entered += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.lock, size: 56),
              const SizedBox(height: 12),
              const Text('كادي للمنظفات',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('أدخل كلمة المرور لفتح التطبيق'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(8, (i) {
                  final filled = i < _entered.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                    ),
                  );
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const Spacer(),
              if (_checking)
                const CircularProgressIndicator()
              else
                _buildPad(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: keys.map((k) {
            if (k.isEmpty) return const SizedBox();
            if (k == '⌫') {
              return _padButton(icon: Icons.backspace_outlined, onTap: _backspace);
            }
            return _padButton(label: k, onTap: () => _tap(k));
          }).toList(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _entered.isEmpty ? null : _submit,
            icon: const Icon(Icons.lock_open),
            label: const Text('دخول'),
          ),
        ),
      ],
    );
  }

  Widget _padButton({String? label, IconData? icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: label != null
              ? Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
              : Icon(icon, size: 22),
        ),
      ),
    );
  }
}
