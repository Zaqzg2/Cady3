import 'invoice_item.dart';
import 'sync_status.dart';

enum InvoiceKind { sale, saleReturn } // فاتورة بيع / فاتورة مرتجع
enum PaymentMode { cash, credit } // نقد / آجل

class Invoice {
  String id;
  String docNumber; // رقم الفاتورة (قابل للتعديل مع استمرار الترقيم)
  DateTime date;
  InvoiceKind kind;
  PaymentMode paymentMode;
  String customerId;
  String customerName;
  List<InvoiceItem> items;
  double discountPercent;
  double discountAmount;
  String notes;
  String? signaturePath; // مسار صورة توقيع العميل (PNG)
  String repName; // اسم المندوب الذي أنشأ الفاتورة (يُلتقط وقت الإنشاء فقط)
  double balanceAfter; // رصيد مديونية العميل بعد هذه الفاتورة
  bool isPrinted; // هل طُبعت هذه الفاتورة من قبل
  bool isShared; // هل شُوركت (واتساب/مشاركة) من قبل
  bool isPinned; // تثبيت الفاتورة أعلى سجل المستندات
  DateTime createdAt;
  SyncStatus syncStatus;
  DateTime updatedAt;

  Invoice({
    required this.id,
    required this.docNumber,
    required this.date,
    required this.kind,
    required this.paymentMode,
    required this.customerId,
    required this.customerName,
    required this.items,
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.notes = '',
    this.signaturePath,
    this.repName = '',
    this.balanceAfter = 0,
    this.isPrinted = false,
    this.isShared = false,
    this.isPinned = false,
    DateTime? createdAt,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get subTotal => items.fold(0.0, (sum, it) => sum + it.total);

  double get discountValue {
    final byPercent = subTotal * (discountPercent / 100);
    return byPercent + discountAmount;
  }

  double get grandTotal {
    final t = subTotal - discountValue;
    return t < 0 ? 0 : t;
  }

  // فاتورة المرتجع تُخصم من مديونية العميل بدلاً من إضافتها
  double get effect => kind == InvoiceKind.saleReturn ? -grandTotal : grandTotal;

  Map<String, dynamic> toMap() => {
        'id': id,
        'docNumber': docNumber,
        'date': date.toIso8601String(),
        'kind': kind.name,
        'paymentMode': paymentMode.name,
        'customerId': customerId,
        'customerName': customerName,
        'items': items.map((e) => e.toMap()).toList(),
        'discountPercent': discountPercent,
        'discountAmount': discountAmount,
        'notes': notes,
        'signaturePath': signaturePath,
        'repName': repName,
        'balanceAfter': balanceAfter,
        'isPrinted': isPrinted,
        'isShared': isShared,
        'isPinned': isPinned,
        'createdAt': createdAt.toIso8601String(),
        'syncStatus': syncStatus.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Invoice.fromMap(Map<String, dynamic> m) => Invoice(
        id: m['id'] as String,
        docNumber: m['docNumber'] as String,
        date: DateTime.parse(m['date'] as String),
        kind: InvoiceKind.values.firstWhere((k) => k.name == m['kind']),
        paymentMode:
            PaymentMode.values.firstWhere((k) => k.name == m['paymentMode']),
        customerId: m['customerId'] as String,
        customerName: m['customerName'] as String,
        items: (m['items'] as List)
            .map((e) => InvoiceItem.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        discountPercent: (m['discountPercent'] as num?)?.toDouble() ?? 0,
        discountAmount: (m['discountAmount'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String? ?? '',
        signaturePath: m['signaturePath'] as String?,
        repName: m['repName'] as String? ?? '',
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

