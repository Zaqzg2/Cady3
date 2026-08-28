import 'db_service.dart';
import 'image_store.dart';
import 'settings_service.dart';

/// تنظيف صور محفوظة (توقيعات/شعار) غير المرتبطة بأي فاتورة أو سند حالي
/// ولا بالتوقيع الافتراضي المحفوظ للمندوب أو شعار الشركة الحالي —
/// لتحرير المساحة المستخدمة داخل Hive.
class CleanupService {
  static Future<int> cleanUnusedSignatures() async {
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();
    final settings = await SettingsService.instance.load();

    final used = <String>{
      ...invoices.map((i) => i.signaturePath).whereType<String>(),
      ...receipts.map((r) => r.repSignaturePath).whereType<String>(),
      if (settings.defaultRepSignaturePath != null)
        settings.defaultRepSignaturePath!,
      if (settings.logoPath != null) settings.logoPath!,
    };

    final allKeys = await ImageStore.instance.allKeys();
    int deleted = 0;
    for (final key in allKeys) {
      if (!used.contains(key)) {
        await ImageStore.instance.delete(key);
        deleted++;
      }
    }
    return deleted;
  }
}
