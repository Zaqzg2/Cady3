/// جهاز طابعة بلوتوث مقترن — نوع بسيط مستقل عن أي حزمة، حتى لا تحتاج
/// شاشات الواجهة (مثل إعدادات الطباعة) استيراد print_bluetooth_thermal
/// مباشرة (تلك الحزمة لا تدعم الويب، فعزلها هنا يبقي كل كود الواجهة آمنًا
/// للعمل على الويب دون أي تغيير).
class PrinterDevice {
  final String name;
  final String macAddress;
  const PrinterDevice({required this.name, required this.macAddress});
}
