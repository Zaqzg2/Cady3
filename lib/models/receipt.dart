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
  String notes;
  double balanceAfter;
  DateTime createdAt;

  Receipt({
    required this.id,
    required this.docNumber,
    required this.date,
    required this.amount,
    required this.method,
    required this.customerId,
    required this.customerName,
    this.repSignaturePath,
    this.notes = '',
    this.balanceAfter = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'docNumber': docNumber,
        'date': date.toIso8601String(),
        'amount': amount,
        'method': method.name,
        'customerId': customerId,
        'customerName': customerName,
        'repSignaturePath': repSignaturePath,
        'notes': notes,
        'balanceAfter': balanceAfter,
        'createdAt': createdAt.toIso8601String(),
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
        notes: m['notes'] as String? ?? '',
        balanceAfter: (m['balanceAfter'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(m['createdAt'] as String),
      );
}
