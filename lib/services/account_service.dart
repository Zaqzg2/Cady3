import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/user_account.dart';
import 'db_service.dart';

/// إدارة حسابات المستخدمين (مدير/مندوب) وجلسة الدخول الحالية. كلمة المرور
/// تُشفَّر بنفس أسلوب AuthService (SHA-256 محلي فقط، بلا أي اتصال بخادم)،
/// والجلسة (من هو المسجّل دخوله حاليًا) تُخزَّن في shared_preferences
/// كمعرف مستخدم واحد فقط.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _sessionKey = 'current_user_id';
  final _uuid = const Uuid();

  String _hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

  Future<bool> hasAnyUsers() async {
    final users = await DbService.instance.getUsers();
    return users.isNotEmpty;
  }

  Future<bool> isUsernameTaken(String username, {String? excludingId}) async {
    final users = await DbService.instance.getUsers();
    final normalized = username.trim().toLowerCase();
    return users.any(
        (u) => u.username.toLowerCase() == normalized && u.id != excludingId);
  }

  /// ينشئ حسابًا جديدًا (مدير أو مندوب) — لا يبدأ الجلسة تلقائيًا
  Future<UserAccount> createUser({
    required String username,
    required String rawPassword,
    required String displayName,
    required UserRole role,
    String repNumber = '',
  }) async {
    final user = UserAccount(
      id: _uuid.v4(),
      username: username.trim(),
      passwordHash: _hash(rawPassword),
      displayName: displayName.trim(),
      role: role,
      repNumber: repNumber.trim(),
    );
    await DbService.instance.upsertUser(user);
    return user;
  }

  Future<void> updateUser(UserAccount user) async {
    user.updatedAt = DateTime.now();
    await DbService.instance.upsertUser(user);
  }

  Future<void> setPassword(UserAccount user, String rawPassword) async {
    user.passwordHash = _hash(rawPassword);
    await updateUser(user);
  }

  Future<List<UserAccount>> getUsers() => DbService.instance.getUsers();

  /// يتحقق من اسم المستخدم وكلمة المرور، ويبدأ الجلسة عند النجاح
  Future<UserAccount?> login(String username, String rawPassword) async {
    final users = await DbService.instance.getUsers();
    final normalized = username.trim().toLowerCase();
    UserAccount? match;
    for (final u in users) {
      if (u.username.toLowerCase() == normalized) {
        match = u;
        break;
      }
    }
    if (match == null || !match.isActive) return null;
    if (match.passwordHash != _hash(rawPassword)) return null;
    await setSession(match.id);
    return match;
  }

  Future<void> setSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, userId);
  }

  Future<UserAccount?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_sessionKey);
    if (id == null) return null;
    final users = await DbService.instance.getUsers();
    for (final u in users) {
      if (u.id == id) return u.isActive ? u : null;
    }
    return null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
