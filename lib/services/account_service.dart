import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';
import 'db_service.dart';

/// إدارة حسابات المستخدمين (مدير/مندوب) وجلسة الدخول الحالية.
///
/// الهوية الفعلية الآن مبنية على Firebase Authentication (بريد وهمي
/// مُصاغ من اسم المستخدم + نطاق المشروع، لأن Firebase Auth يتطلب بريدًا
/// لا اسم مستخدم مجرّد). هذا يحل ثغرة كانت موجودة بالنظام المحلي
/// القديم: حساب المندوب كان يُنشأ محليًا على جهاز المدير فقط، وما
/// توجد أي طريقة تلقائية ليصل لجهاز المندوب نفسه. الآن: المدير يُنشئ
/// الحساب من جهازه (يبقى هو نفسه مسجّل دخول، عبر نسخة FirebaseApp
/// ثانوية مؤقتة تُنشئ الحساب بدون ما تلمس جلسته)، والمندوب يدخل نفس
/// اليوزر/الباسورد بجهازه هو — أول دخول يحتاج إنترنت (يتحقق من
/// Firebase ويسحب بيانات حسابه من Firestore)، وبعدها الجلسة تُحفظ
/// محليًا وتشتغل حتى بدون إنترنت.
///
/// نسخة محلية من الحساب (Hive، بلا كلمة مرور فعلية مستخدَمة للتحقق)
/// تبقى موجودة كـ"كاش" — تخدم كل الشاشات الحالية اللي تقرأ
/// AppProvider.currentUser بدون أي تعديل عليها، وتوفّر آخر حالة معروفة
/// عند انعدام الاتصال (راجع _localFallbackLogin).
///
/// قيود معروفة بهذي المرحلة (تحتاج Cloud Function/صلاحية إدارية لاحقًا
/// إذا احتجناها):
/// - المدير ما يقدر يغيّر كلمة مرور مندوب موجود مسبقًا (setPassword)؛
///   المستخدم يقدر يغيّر كلمة مروره بنفسه فقط وهو مسجّل دخول.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _sessionKey = 'current_user_id';
  static const _emailDomain = 'cady-34220.firebaseapp.com';

  FirebaseAuth get _auth => FirebaseAuth.instance;
  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');

  String _hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

  /// يحوّل اسم المستخدم لبريد وهمي صالح لـ Firebase Auth. يقبل فقط
  /// حروف/أرقام إنجليزية ونقطة وشرطة وشرطة سفلية (متطلبات صيغة
  /// البريد) — لو اسم المستخدم فيه حروف عربية أو رموز غير مدعومة
  /// يرمي خطأ عربي واضح بدل فشل غامض من Firebase نفسه.
  String _emailFor(String username) {
    final normalized = username.trim().toLowerCase();
    final safe = RegExp(r'^[a-z0-9_.-]+$');
    if (!safe.hasMatch(normalized)) {
      throw Exception(
          'اسم المستخدم يجب يكون بحروف/أرقام إنجليزية فقط (بدون مسافات أو حروف عربية)');
    }
    return '$normalized@$_emailDomain';
  }

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

  /// ينشئ حساب Firebase Auth جديد دون التأثير على جلسة الدخول الحالية
  /// (لو المدير مسجّل دخول، يضل مسجّل دخول) — عبر نسخة FirebaseApp
  /// ثانوية مؤقتة تُحذف فور الانتهاء منها.
  Future<UserCredential> _createAuthAccountPreservingSession({
    required String email,
    required String password,
  }) async {
    final tempName = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final tempApp = await Firebase.initializeApp(
      name: tempName,
      options: Firebase.app().options,
    );
    try {
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final cred = await tempAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred;
    } finally {
      await tempApp.delete();
    }
  }

  /// ينشئ حسابًا جديدًا (مدير أو مندوب) على Firebase Auth + Firestore،
  /// ويحفظ نسخة محلية (كاش) — لا يبدأ جلسة جديدة إلا لو ما فيه أحد
  /// مسجّل دخول أصلاً (حالة أول مدير عند أول تشغيل للتطبيق).
  Future<UserAccount> createUser({
    required String username,
    required String rawPassword,
    required String displayName,
    required UserRole role,
    String repNumber = '',
  }) async {
    final email = _emailFor(username);
    final noOneSignedInYet = _auth.currentUser == null;

    late final String uid;
    try {
      final cred = await _createAuthAccountPreservingSession(
        email: email,
        password: rawPassword,
      );
      uid = cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('اسم المستخدم مستخدم بالفعل');
      }
      if (e.code == 'weak-password') {
        throw Exception('كلمة المرور ضعيفة جدًا (٦ أحرف على الأقل)');
      }
      throw Exception('تعذّر إنشاء الحساب على Firebase: ${e.message}');
    } catch (e) {
      throw Exception('تعذّر الاتصال بـ Firebase: $e');
    }

    // لو ما فيه أحد مسجّل دخول أصلاً (أول حساب على الإطلاق) سجّل
    // دخوله فورًا على الجلسة الأساسية *قبل* الكتابة على Firestore،
    // عشان قواعد الحماية تسمح بالكتابة (تتطلب مستخدم مسجّل دخول).
    if (noOneSignedInYet) {
      await _auth.signInWithEmailAndPassword(email: email, password: rawPassword);
    }

    final user = UserAccount(
      id: uid,
      username: username.trim(),
      passwordHash: _hash(rawPassword),
      displayName: displayName.trim(),
      role: role,
      repNumber: repNumber.trim(),
    );

    try {
      await _usersCol.doc(uid).set({
        'username': user.username,
        'displayName': user.displayName,
        'role': user.role.name,
        'repNumber': user.repNumber,
        'isActive': user.isActive,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // فشل الكتابة السحابية ما يوقف إنشاء الحساب محليًا، لكن يعني
      // الحساب ما راح يظهر على أي جهاز ثاني حتى تُصلَح المزامنة
      // ignore: avoid_print
      print('تحذير: تعذّرت كتابة ملف Firestore للمستخدم الجديد: $e');
    }

    await DbService.instance.upsertUser(user);
    return user;
  }

  Future<void> updateUser(UserAccount user) async {
    user.updatedAt = DateTime.now();
    await DbService.instance.upsertUser(user);
    try {
      await _usersCol.doc(user.id).set({
        'username': user.username,
        'displayName': user.displayName,
        'role': user.role.name,
        'repNumber': user.repNumber,
        'isActive': user.isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('تنبيه: تعذّرت مزامنة تعديل المستخدم مع Firestore: $e');
    }
  }

  /// تغيير كلمة مرور مستخدم آخر (مثلاً المدير يعيد ضبط كلمة مرور
  /// مندوب) غير مدعوم عبر صلاحيات Firebase Auth العادية للعميل —
  /// يحتاج صلاحية إدارية (Cloud Function). المستخدم يقدر يغيّر كلمة
  /// مروره بنفسه فقط وهو مسجّل دخول بحسابه.
  Future<void> setPassword(UserAccount user, String rawPassword) async {
    final current = _auth.currentUser;
    if (current != null && current.uid == user.id) {
      await current.updatePassword(rawPassword);
      user.passwordHash = _hash(rawPassword);
      await updateUser(user);
      return;
    }
    throw Exception(
        'تغيير كلمة مرور مستخدم آخر غير مدعوم حاليًا (يحتاج صلاحية إدارية على Firebase). المستخدم يقدر يغيّرها بنفسه وهو مسجّل دخول.');
  }

  Future<List<UserAccount>> getUsers() => DbService.instance.getUsers();

  /// يتحقق من اسم المستخدم وكلمة المرور عبر Firebase Auth (يتطلب
  /// إنترنت أول مرة على أي جهاز)، ويحدّث النسخة المحلية من Firestore.
  /// لو فشل الاتصال تحديدًا (لا خطأ باسم مستخدم/كلمة مرور، بل انعدام
  /// شبكة) يرجع للتحقق من النسخة المحلية المخزّنة مسبقًا على نفس
  /// الجهاز — يسمح للمندوب بالدخول بدون إنترنت طالما دخل من قبل عليه.
  Future<UserAccount?> login(String username, String rawPassword) async {
    final normalized = username.trim().toLowerCase();
    String email;
    try {
      email = _emailFor(username);
    } catch (_) {
      return null;
    }

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: rawPassword,
      );
      final uid = cred.user!.uid;
      final doc = await _usersCol.doc(uid).get();
      UserAccount user;
      if (doc.exists) {
        final d = doc.data()!;
        user = UserAccount(
          id: uid,
          username: (d['username'] as String?) ?? normalized,
          passwordHash: _hash(rawPassword),
          displayName: (d['displayName'] as String?) ?? normalized,
          role: UserRole.values.firstWhere((r) => r.name == d['role'],
              orElse: () => UserRole.rep),
          repNumber: (d['repNumber'] as String?) ?? '',
          isActive: (d['isActive'] as bool?) ?? true,
        );
      } else {
        // حساب موجود على Auth بس بلا ملف Firestore (حالة نادرة) —
        // نبني نسخة محلية أساسية حتى لا يتعطّل الدخول بالكامل
        user = UserAccount(
          id: uid,
          username: normalized,
          passwordHash: _hash(rawPassword),
          displayName: normalized,
          role: UserRole.rep,
        );
      }
      if (!user.isActive) return null;
      await DbService.instance.upsertUser(user);
      await setSession(user.id);
      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        return _localFallbackLogin(normalized, rawPassword);
      }
      return null; // باسورد غلط أو مستخدم غير موجود على Firebase
    } catch (_) {
      // أي خطأ اتصال آخر (لا يوجد إعداد Firebase صالح، انقطاع مفاجئ...)
      return _localFallbackLogin(normalized, rawPassword);
    }
  }

  Future<UserAccount?> _localFallbackLogin(
      String normalizedUsername, String rawPassword) async {
    final users = await DbService.instance.getUsers();
    UserAccount? match;
    for (final u in users) {
      if (u.username.toLowerCase() == normalizedUsername) {
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
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}
