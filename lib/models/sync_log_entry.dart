/// سجل عملية استيراد واحدة نفّذها المدير من ملف مندوب
class SyncLogEntry {
  final String id;
  final String fileName;
  final String repId;
  final String repDisplayName;
  final DateTime importedAt;
  final int customersCount;
  final int productsCount;
  final int invoicesCount;
  final int receiptsCount;
  final int duplicatesCount;
  final int errorsCount;

  const SyncLogEntry({
    required this.id,
    required this.fileName,
    required this.repId,
    required this.repDisplayName,
    required this.importedAt,
    required this.customersCount,
    required this.productsCount,
    required this.invoicesCount,
    required this.receiptsCount,
    required this.duplicatesCount,
    required this.errorsCount,
  });

  int get totalRecords =>
      customersCount + productsCount + invoicesCount + receiptsCount;

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'repId': repId,
        'repDisplayName': repDisplayName,
        'importedAt': importedAt.toIso8601String(),
        'customersCount': customersCount,
        'productsCount': productsCount,
        'invoicesCount': invoicesCount,
        'receiptsCount': receiptsCount,
        'duplicatesCount': duplicatesCount,
        'errorsCount': errorsCount,
      };

  factory SyncLogEntry.fromMap(Map<String, dynamic> m) => SyncLogEntry(
        id: m['id'] as String,
        fileName: m['fileName'] as String? ?? '',
        repId: m['repId'] as String? ?? '',
        repDisplayName: m['repDisplayName'] as String? ?? '',
        importedAt: DateTime.parse(m['importedAt'] as String),
        customersCount: (m['customersCount'] as num?)?.toInt() ?? 0,
        productsCount: (m['productsCount'] as num?)?.toInt() ?? 0,
        invoicesCount: (m['invoicesCount'] as num?)?.toInt() ?? 0,
        receiptsCount: (m['receiptsCount'] as num?)?.toInt() ?? 0,
        duplicatesCount: (m['duplicatesCount'] as num?)?.toInt() ?? 0,
        errorsCount: (m['errorsCount'] as num?)?.toInt() ?? 0,
      );
}
