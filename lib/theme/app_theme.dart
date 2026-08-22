import 'package:flutter/material.dart';

/// هوية بصرية لتطبيق كادي للمنظفات — أزرار وبطاقات كبيرة مناسبة للمس،
/// مع دعم كامل للوضع الليلي
class AppTheme {
  static const Color primary = Color(0xFFC62828); // أحمر (هوية كادي الجديدة)
  static const Color primaryDark = Color(0xFF8C1D1D);
  static const Color accent = Color(0xFFFFA000);

  // ألوان دلالية لحالات المزامنة (مركز المزامنة) — تدرّج فيروزي/ذهبي من
  // هوية كادي بدل الأخضر/البرتقالي العام، موحّدة بين شاشتي المندوب والمدير
  // الفيروزي القديم بقي محجوزًا لمعنى "تمام/نجاح" فقط، منفصل الآن عن
  // لون العلامة التجارية (الذي أصبح أحمر) — حتى لا تعني حالة "ناجح" اللون
  // نفسه الذي يعني عادةً خطر/توقف
  static const Color syncSuccess = Color(0xFF00838F);
  static const Color syncSuccessSoft = Color(0xFFE1F1F2);
  static const Color syncPending = accent;
  static const Color syncPendingSoft = Color(0xFFFFF2DC);
  static const Color syncError = Color(0xFFD64545);
  static const Color syncErrorSoft = Color(0xFFFBE8E7);

  static ThemeData light({Color? seedColor}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor ?? primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7F8),
      fontFamily: 'Cairo',
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  static ThemeData dark({Color? seedColor}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor ?? primary,
        brightness: Brightness.dark,
      ),
      fontFamily: 'Cairo',
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
