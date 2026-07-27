import 'package:intl/intl.dart';

/// تنسيق المبالغ بالريال اليمني، وتنسيق التاريخ المستخدم في كل التطبيق
class Formatters {
  static final currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'ر.ي',
    decimalDigits: 0,
  );

  static final date = DateFormat('yyyy/MM/dd');

  static String money(num value) => currency.format(value);
  static String d(DateTime dt) => date.format(dt);
}
