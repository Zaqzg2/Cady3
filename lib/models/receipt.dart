import 'sync_status.dart';

enum ReceiptMethod { cash, transfer } // نقدًا / تحويل

class Receipt {
  String id;
  String docNumber;
  DateTime date;
  double amount;
  ReceiptMethod method;
  String customerId;
  String customerName;
  String? repSignaturePath; // توقيع المندوب
  String repName; // اسم المندوب الذي أنشأ السند (يُلتقط وقت الإنشاء فقط)
  String notes;
  double balanceAfter;
  bool isPrinted;
  bool isShared;
  bool isPinned;
  DateTime createdAt;
  SyncStatus syncStatus;
  DateTime updatedAt;

  Receipt({
    required this.id,
    required this.docNumber,
    required this.date,
    required this.amount,
    required this.method,
    required this.customerId,
    required this.customerName,
    this.repSignaturePath,
    this.repName = '',
    this.notes = '',
    this.balanceAfter = 0,
    this.isPrinted = false,
    this.isShared = false,
    this.isPinned = false,
    DateTime? createdAt,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'docNumber': docNumber,
        'date': date.toIso8601String(),
        'amount': amount,
        'method': method.name,
        'customerId': customerId,
        'customerName': customerName,
        'repSignaturePath': repSignaturePath,
        'repName': repName,
        'notes': notes,
        'balanceAfter': balanceAfter,
        'isPrinted': isPrinted,
        'isShared': isShared,
        'isPinned': isPinned,
        'createdAt': createdAt.toIso8601String(),
        'syncStatus': syncStatus.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Receipt.fromMap(Map<String, dynamic> m) => Receipt(
        id: m['id'] as String,
        docNumber: m['docNumber'] as String,
        date: DateTime.parse(m['date'] as String),
        amount: (m['amount'] as num).toDouble(),
        method: ReceiptMethod.values.firstWhere((k) => k.name == m['method']),
        customerId: m['customerId'] as String,
        customerName: m['customerName'] as String,
        repSignaturePath: m['repSignaturePath'] as String?,
        repName: m['repName'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        balanceAfter: (m['balanceAfter'] as num?)?.toDouble() ?? 0,
        isPrinted: (m['isPrinted'] as bool?) ?? false,
        isShared: (m['isShared'] as bool?) ?? false,
        isPinned: (m['isPinned'] as bool?) ?? false,
        createdAt: DateTime.parse(m['createdAt'] as String),
        syncStatus: m['syncStatus'] != null
            ? SyncStatus.values.firstWhere((s) => s.name == m['syncStatus'],
                orElse: () => SyncStatus.synced)
            : SyncStatus.synced,
        updatedAt: m['updatedAt'] != null
            ? DateTime.parse(m['updatedAt'] as String)
            : DateTime.now(),
      );
}

