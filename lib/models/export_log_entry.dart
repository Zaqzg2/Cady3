/// سجل عملية "إنشاء تحديث" واحدة نفّذها المدير (تصدير منتجات/عملاء/
/// إعدادات لمندوب محدد أو لكل المندوبين)
class ExportLogEntry {
  final String id;
  final DateTime createdAt;
  final String targetLabel; // اسم المندوب أو "كل المندوبين"
  final bool includedProducts;
  final bool includedCustomers;
  final bool includedSettings;
  final int productsCount;
  final int customersCount;

  const ExportLogEntry({
    required this.id,
    required this.createdAt,
    required this.targetLabel,
    required this.includedProducts,
    required this.includedCustomers,
    required this.includedSettings,
    required this.productsCount,
    required this.customersCount,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'targetLabel': targetLabel,
        'includedProducts': includedProducts,
        'includedCustomers': includedCustomers,
        'includedSettings': includedSettings,
        'productsCount': productsCount,
        'customersCount': customersCount,
      };

  factory ExportLogEntry.fromMap(Map<String, dynamic> m) => ExportLogEntry(
        id: m['id'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        targetLabel: m['targetLabel'] as String? ?? '',
        includedProducts: (m['includedProducts'] as bool?) ?? false,
        includedCustomers: (m['includedCustomers'] as bool?) ?? false,
        includedSettings: (m['includedSettings'] as bool?) ?? false,
        productsCount: (m['productsCount'] as num?)?.toInt() ?? 0,
        customersCount: (m['customersCount'] as num?)?.toInt() ?? 0,
      );
}
