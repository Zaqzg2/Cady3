/// ملخّص محسوب لعميل معيّن: الرصيد الحالي، عدد الفواتير، إجمالي المقبوض،
/// إجمالي المرتجع، وتاريخ/رقم آخر نشاط — يُستخدم في بطاقة العميل وصفحته
class CustomerStats {
  final double balance;
  final int invoicesCount;
  final double receivedTotal;
  final double returnsTotal;
  final DateTime? lastActivityDate;
  final String? lastInvoiceNumber;
  final DateTime? lastInvoiceDate;

  const CustomerStats({
    required this.balance,
    required this.invoicesCount,
    required this.receivedTotal,
    required this.returnsTotal,
    this.lastActivityDate,
    this.lastInvoiceNumber,
    this.lastInvoiceDate,
  });

  /// عدد الأيام منذ آخر نشاط (فاتورة أو سند قبض)، أو null إن لم يوجد نشاط
  int? get daysSinceLastActivity {
    if (lastActivityDate == null) return null;
    return DateTime.now().difference(lastActivityDate!).inDays;
  }

  /// نسبة استخدام الحد الائتماني (0..1+)، أو null إن لم يكن للعميل حد محدد
  double? creditUsageRatio(double creditLimit) {
    if (creditLimit <= 0) return null;
    return balance / creditLimit;
  }
}
