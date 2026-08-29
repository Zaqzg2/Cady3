import 'package:flutter/material.dart';

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

/// وضع المظهر: تلقائي حسب النظام / فاتح دائمًا / داكن دائمًا
enum AppThemeMode { system, light, dark }

/// صيغة طباعة كشف الحساب الافتراضية
enum StatementFormat { thermal80, a4 }

/// مدة الخمول قبل قفل التطبيق تلقائيًا
enum AutoLockOption { immediate, oneMinute, fiveMinutes, never }

/// دورية النسخ الاحتياطي التلقائي
enum AutoBackupFrequency { off, daily, weekly }

/// وجهة حفظ النسخة الاحتياطية التلقائية
enum AutoBackupLocation { local, driveShare }

/// ألوان الهوية المتاحة للاختيار من بينها في المظهر
const List<Color> kBrandColorPalette = [
  Color(0xFF00838F), // فيروزي (الافتراضي)
  Color(0xFF2E7D32), // أخضر
  Color(0xFF1565C0), // أزرق
  Color(0xFF6A1B9A), // بنفسجي
  Color(0xFFEF6C00), // برتقالي
  Color(0xFFC62828), // أحمر
  Color(0xFF37474F), // رمادي غامق
];

class CompanySettings {
  // بيانات الشركة والمندوب
  String companyName;
  String companyPhone;
  String companyAddress;
  String? logoPath;
  String repName;
  String repPhone;
  String? defaultRepSignaturePath; // توقيع افتراضي محفوظ للمندوب
  String invoiceFooterText; // نص ثابت أسفل كل فاتورة/سند

  // الطباعة والفاتورة
  double tableFontSize; // حجم خط جدول الأصناف
  double rowSpacing; // تباعد صفوف الجدول
  double invoiceBodyFontSize; // حجم خط بقية نص الفاتورة/السند (غير الجدول)
  double invoiceLineSpacing; // تباعد أسطر الفاتورة/السند كاملة
  List<ColumnConfig> tableColumns;
  String? printerAddress; // عنوان MAC لطابعة البلوتوث المحفوظة
  String? printerName;
  StatementFormat defaultStatementFormat;
  // اطبع عبر مربع حوار نظام التشغيل (يعرض أي خدمة طباعة مُثبَّتة كـ RawBT)
  // بدل الاتصال المباشر بمكتبة البلوتوث. مفيد للأجهزة التي تفشل فيها
  // المكتبة المباشرة رغم أن الطابعة تعمل فعليًا (راجع ملاحظة
  // print_service.dart لتفاصيل السبب). افتراضيًا false للحفاظ على السرعة
  // الحالية على الأجهزة التي تعمل فيها الطباعة المباشرة بلا مشاكل.
  bool preferSystemPrintDialog;
  // درجة تحويل الرمادي إلى أسود عند طباعة الصور النقطية (0-255): كل بكسل
  // درجته أغمق من هذه القيمة يُطبع أسود صرفًا، وإلا فأبيض — بلا تدرّج
  // رمادي بينهما. القيمة الافتراضية أعلى من المنتصف الرياضي (128) عمدًا:
  // نصوص الفاتورة تمر بتنعيم حواف (anti-aliasing) يجعل كثيرًا من بكسلاتها
  // رماديًا فاتحًا لا أسود صرفًا، فعتبة أعلى تجعل الحروف تطبع أغمق وأوضح.
  int printBlackThreshold;

  // المظهر
  AppThemeMode themeMode;
  double appFontScale; // حجم خط واجهة التطبيق (غير خط الفاتورة)
  bool hapticOnSave;
  bool soundOnSave;
  int themeColorValue; // Color.value للون الهوية المختار

  // الخصوصية والأمان
  AutoLockOption autoLockOption;
  bool hideAmountsInRecents;
  int autoLogoutHours; // 0 = تعطيل تسجيل الخروج التلقائي

  // البيانات والنسخ الاحتياطي
  AutoBackupFrequency autoBackupFrequency;
  AutoBackupLocation autoBackupLocation;

  CompanySettings({
    this.companyName = 'كادي للمنظفات',
    this.companyPhone = '',
    this.companyAddress = '',
    this.logoPath,
    this.repName = '',
    this.repPhone = '',
    this.defaultRepSignaturePath,
    this.invoiceFooterText = 'شكرًا لتعاملكم معنا',
    this.tableFontSize = 9,
    this.rowSpacing = 4,
    this.invoiceBodyFontSize = 9,
    this.invoiceLineSpacing = 1.2,
    List<ColumnConfig>? tableColumns,
    this.printerAddress,
    this.printerName,
    this.defaultStatementFormat = StatementFormat.thermal80,
    this.preferSystemPrintDialog = false,
    this.printBlackThreshold = 175,
    this.themeMode = AppThemeMode.system,
    this.appFontScale = 1.0,
    this.hapticOnSave = true,
    this.soundOnSave = false,
    int? themeColorValue,
    this.autoLockOption = AutoLockOption.never,
    this.hideAmountsInRecents = false,
    this.autoLogoutHours = 0,
    this.autoBackupFrequency = AutoBackupFrequency.off,
    this.autoBackupLocation = AutoBackupLocation.local,
  })  : themeColorValue = themeColorValue ?? kBrandColorPalette.first.value,
        tableColumns = tableColumns ??
            [
              ColumnConfig(key: 'productName', label: 'الصنف', widthFlex: 3),
              ColumnConfig(key: 'quantity', label: 'الكمية', widthFlex: 1),
              ColumnConfig(key: 'price', label: 'السعر', widthFlex: 1.2),
              ColumnConfig(key: 'total', label: 'الإجمالي', widthFlex: 1.4),
            ];

  Color get themeColor => Color(themeColorValue);

  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'companyPhone': companyPhone,
        'companyAddress': companyAddress,
        'logoPath': logoPath,
        'repName': repName,
        'repPhone': repPhone,
        'defaultRepSignaturePath': defaultRepSignaturePath,
        'invoiceFooterText': invoiceFooterText,
        'tableFontSize': tableFontSize,
        'rowSpacing': rowSpacing,
        'invoiceBodyFontSize': invoiceBodyFontSize,
        'invoiceLineSpacing': invoiceLineSpacing,
        'tableColumns': tableColumns.map((c) => c.toMap()).toList(),
        'printerAddress': printerAddress,
        'printerName': printerName,
        'defaultStatementFormat': defaultStatementFormat.name,
        'preferSystemPrintDialog': preferSystemPrintDialog,
        'printBlackThreshold': printBlackThreshold,
        'themeMode': themeMode.name,
        'appFontScale': appFontScale,
        'hapticOnSave': hapticOnSave,
        'soundOnSave': soundOnSave,
        'themeColorValue': themeColorValue,
        'autoLockOption': autoLockOption.name,
        'hideAmountsInRecents': hideAmountsInRecents,
        'autoLogoutHours': autoLogoutHours,
        'autoBackupFrequency': autoBackupFrequency.name,
        'autoBackupLocation': autoBackupLocation.name,
      };

  factory CompanySettings.fromJson(Map<String, dynamic> m) => CompanySettings(
        companyName: m['companyName'] as String? ?? 'كادي للمنظفات',
        companyPhone: m['companyPhone'] as String? ?? '',
        companyAddress: m['companyAddress'] as String? ?? '',
        logoPath: m['logoPath'] as String?,
        repName: m['repName'] as String? ?? '',
        repPhone: m['repPhone'] as String? ?? '',
        defaultRepSignaturePath: m['defaultRepSignaturePath'] as String?,
        invoiceFooterText: m['invoiceFooterText'] as String? ?? 'شكرًا لتعاملكم معنا',
        tableFontSize: (m['tableFontSize'] as num?)?.toDouble() ?? 9,
        rowSpacing: (m['rowSpacing'] as num?)?.toDouble() ?? 4,
        invoiceBodyFontSize: (m['invoiceBodyFontSize'] as num?)?.toDouble() ?? 9,
        invoiceLineSpacing: (m['invoiceLineSpacing'] as num?)?.toDouble() ?? 1.2,
        tableColumns: (m['tableColumns'] as List?)
                ?.map((e) => ColumnConfig.fromMap(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        printerAddress: m['printerAddress'] as String?,
        printerName: m['printerName'] as String?,
        defaultStatementFormat: StatementFormat.values.firstWhere(
            (v) => v.name == m['defaultStatementFormat'],
            orElse: () => StatementFormat.thermal80),
        preferSystemPrintDialog: (m['preferSystemPrintDialog'] as bool?) ?? false,
        printBlackThreshold: (m['printBlackThreshold'] as num?)?.toInt() ?? 175,
        // توافق مع النسخ القديمة التي كانت تخزّن darkMode كـ bool فقط
        themeMode: m['themeMode'] != null
            ? AppThemeMode.values.firstWhere((v) => v.name == m['themeMode'],
                orElse: () => AppThemeMode.system)
            : ((m['darkMode'] as bool?) == true
                ? AppThemeMode.dark
                : AppThemeMode.system),
        appFontScale: (m['appFontScale'] as num?)?.toDouble() ?? 1.0,
        hapticOnSave: (m['hapticOnSave'] as bool?) ?? true,
        soundOnSave: (m['soundOnSave'] as bool?) ?? false,
        themeColorValue:
            (m['themeColorValue'] as num?)?.toInt() ?? kBrandColorPalette.first.value,
        autoLockOption: AutoLockOption.values.firstWhere(
            (v) => v.name == m['autoLockOption'],
            orElse: () => AutoLockOption.never),
        hideAmountsInRecents: (m['hideAmountsInRecents'] as bool?) ?? false,
        autoLogoutHours: (m['autoLogoutHours'] as num?)?.toInt() ?? 0,
        autoBackupFrequency: AutoBackupFrequency.values.firstWhere(
            (v) => v.name == m['autoBackupFrequency'],
            orElse: () => AutoBackupFrequency.off),
        autoBackupLocation: AutoBackupLocation.values.firstWhere(
            (v) => v.name == m['autoBackupLocation'],
            orElse: () => AutoBackupLocation.local),
      );
}
