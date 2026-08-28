// صف موحّد يُستخدم في كشف حساب العميل
// التاريخ | البيان | رقم المستند | مدين | دائن | الرصيد
enum LedgerDocType { invoiceSale, invoiceReturn, receipt, opening }

class LedgerEntry {
  final DateTime date;
  final String description;
  final String docNumber;
  final String docId;
  final LedgerDocType docType;
  final double debit; // مدين (فاتورة بيع تزيد المديونية)
  final double credit; // دائن (سند قبض / مرتجع يقلل المديونية)
  double runningBalance;

  LedgerEntry({
    required this.date,
    required this.description,
    required this.docNumber,
    required this.docId,
    required this.docType,
    this.debit = 0,
    this.credit = 0,
    this.runningBalance = 0,
  });
}
