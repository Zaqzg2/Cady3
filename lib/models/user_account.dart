/// دور المستخدم: مدير أو مندوب — يحدد أي واجهة يرى المستخدم بعد الدخول
enum UserRole { manager, rep }

/// حساب مستخدم (مدير أو مندوب). كلمة المرور تُخزَّن مُشفّرة فقط (SHA-256)
/// بنفس أسلوب AuthService الحالي — كل شيء محلي على الجهاز بلا أي خادم.
class UserAccount {
  final String id;
  String username;
  String passwordHash;
  String displayName;
  UserRole role;
  String repNumber; // فارغ للمدير، رقم تعريف المندوب لدى المدير
  String deviceName; // اسم الجهاز (يُملأ لاحقًا مع شاشة إعدادات المزامنة)
  bool isActive;
  DateTime? lastSyncAt;
  DateTime createdAt;
  DateTime updatedAt;

  UserAccount({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.displayName,
    required this.role,
    this.repNumber = '',
    this.deviceName = '',
    this.isActive = true,
    this.lastSyncAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'passwordHash': passwordHash,
        'displayName': displayName,
        'role': role.name,
        'repNumber': repNumber,
        'deviceName': deviceName,
        'isActive': isActive,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserAccount.fromMap(Map<String, dynamic> m) => UserAccount(
        id: m['id'] as String,
        username: m['username'] as String,
        passwordHash: m['passwordHash'] as String,
        displayName: m['displayName'] as String,
        role: UserRole.values.firstWhere((r) => r.name == m['role']),
        repNumber: m['repNumber'] as String? ?? '',
        deviceName: m['deviceName'] as String? ?? '',
        isActive: (m['isActive'] as bool?) ?? true,
        lastSyncAt: m['lastSyncAt'] != null
            ? DateTime.parse(m['lastSyncAt'] as String)
            : null,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
}
