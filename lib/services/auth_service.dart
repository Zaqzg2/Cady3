import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حماية التطبيق بكلمة مرور/رمز دخول (PIN). كلمة المرور تُخزَّن مُشفّرة
/// (SHA-256) محليًا فقط على الجهاز — لا يتم إرسالها لأي خادم.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _hashKey = 'app_password_hash';

  String _hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

  Future<bool> isPasswordSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hashKey) != null;
  }

  Future<void> setPassword(String rawPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey, _hash(rawPassword));
  }

  Future<bool> checkPassword(String rawPassword) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_hashKey);
    if (stored == null) return true; // لا توجد حماية مفعّلة
    return stored == _hash(rawPassword);
  }

  Future<void> removePassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
  }
}
