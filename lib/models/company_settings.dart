class ColumnConfig {
  String key; // productName / quantity / price / total
  String label;
  double widthFlex;
  bool visible;

  ColumnConfig({
    required this.key,
    required this.label,
    this.widthFlex = 1,
    this.visible = true,
  });

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'widthFlex': widthFlex,
        'visible': visible,
      };

  factory ColumnConfig.fromMap(Map<String, dynamic> m) => ColumnConfig(
        key: m['key'] as String,
        label: m['label'] as String,
        widthFlex: (m['widthFlex'] as num?)?.toDouble() ?? 1,
        visible: m['visible'] as bool? ?? true,
      );
}

class CompanySettings {
  String companyName;
  String companyPhone;
  String companyAddress;
  String? logoPath;
  String repName;
  double tableFontSize;
  double rowSpacing;
  List<ColumnConfig> tableColumns;
  String? printerAddress; // عنوان MAC لطابعة البلوتوث المحفوظة
  String? printerName;
  bool darkMode;

  CompanySettings({
    this.companyName = 'كادي للمنظفات',
    this.companyPhone = '',
    this.companyAddress = '',
    this.logoPath,
    this.repName = '',
    this.tableFontSize = 9,
    this.rowSpacing = 4,
    List<ColumnConfig>? tableColumns,
    this.printerAddress,
    this.printerName,
    this.darkMode = false,
  }) : tableColumns = tableColumns ??
            [
              ColumnConfig(key: 'productName', label: 'الصنف', widthFlex: 3),
              ColumnConfig(key: 'quantity', label: 'الكمية', widthFlex: 1),
              ColumnConfig(key: 'price', label: 'السعر', widthFlex: 1.2),
              ColumnConfig(key: 'total', label: 'الإجمالي', widthFlex: 1.4),
            ];

  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'companyPhone': companyPhone,
        'companyAddress': companyAddress,
        'logoPath': logoPath,
        'repName': repName,
        'tableFontSize': tableFontSize,
        'rowSpacing': rowSpacing,
        'tableColumns': tableColumns.map((c) => c.toMap()).toList(),
        'printerAddress': printerAddress,
        'printerName': printerName,
        'darkMode': darkMode,
      };

  factory CompanySettings.fromJson(Map<String, dynamic> m) => CompanySettings(
        companyName: m['companyName'] as String? ?? 'كادي للمنظفات',
        companyPhone: m['companyPhone'] as String? ?? '',
        companyAddress: m['companyAddress'] as String? ?? '',
        logoPath: m['logoPath'] as String?,
        repName: m['repName'] as String? ?? '',
        tableFontSize: (m['tableFontSize'] as num?)?.toDouble() ?? 9,
        rowSpacing: (m['rowSpacing'] as num?)?.toDouble() ?? 4,
        tableColumns: (m['tableColumns'] as List?)
                ?.map((e) => ColumnConfig.fromMap(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        printerAddress: m['printerAddress'] as String?,
        printerName: m['printerName'] as String?,
        darkMode: m['darkMode'] as bool? ?? false,
      );
}
