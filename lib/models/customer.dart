import 'sync_status.dart';

class Customer {
  final String id;
  String name;
  String phone;
  String address;
  double openingBalance; // رصيد افتتاحي (مديونية سابقة)
  bool isPinned; // تثبيت العميل أعلى القائمة
  bool isActive; // حالة العميل: نشط/متوقف
  double creditLimit; // الحد الائتماني المسموح به (0 = بلا حد)
  String notes; // ملاحظات داخلية عن العميل
  SyncStatus syncStatus;
  DateTime updatedAt;

  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.openingBalance = 0,
    this.isPinned = false,
    this.isActive = true,
    this.creditLimit = 0,
    this.notes = '',
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'openingBalance': openingBalance,
        'isPinned': isPinned ? 1 : 0,
        'isActive': isActive ? 1 : 0,
        'creditLimit': creditLimit,
        'notes': notes,
        'syncStatus': syncStatus.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String? ?? '',
        address: m['address'] as String? ?? '',
        openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
        isPinned: ((m['isPinned'] as num?) ?? 0) != 0,
        isActive: ((m['isActive'] as num?) ?? 1) != 0,
        creditLimit: (m['creditLimit'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String? ?? '',
        // migration آمن: سجل قديم بلا هذا الحقل يُعتبر "متزامن" افتراضيًا
        // حتى لا يظهر فجأة كمعلّق بعد تحديث التطبيق
        syncStatus: m['syncStatus'] != null
            ? SyncStatus.values.firstWhere((s) => s.name == m['syncStatus'],
                orElse: () => SyncStatus.synced)
            : SyncStatus.synced,
        updatedAt: m['updatedAt'] != null
            ? DateTime.parse(m['updatedAt'] as String)
            : DateTime.now(),
      );
}

