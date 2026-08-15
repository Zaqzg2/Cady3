import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import 'printer_device.dart';

/// خدمة الطباعة على الويب — لا يوجد وصول لطابعات البلوتوث الحرارية من
/// المتصفح إطلاقًا (لا يوجد Web API لهذا).
///
/// المحاولة الأولى (فتح حوار طباعة المتصفح تلقائيًا عبر حزمة printing عن
/// طريق Printing.layoutPdf) قيد معروف وموثّق بالحزمة نفسها: لا تعمل
/// بشكل موثوق على متصفحات الجوال تحديدًا (Chrome أندرويد وSafari آيفون
/// كلاهما)، حتى لو كانت الطابعة الافتراضية بالمتصفح تُستدعى يدويًا —
/// تنتهي بتنزيل الملف بدل حوار طباعة حقيقي. تأكّد هذا عمليًا (راجع
/// المحادثة: نفس النتيجة سواء من زر التطبيق أو من أيقونة الطباعة داخل
/// عارض PDF بمتصفح Chrome نفسه).
///
/// البديل هنا: "مشاركة" الفاتورة عبر قائمة مشاركة النظام الأصلية بأندرويد
/// (Web Share API، تدعمها حزمة share_plus مباشرة على الويب) — نفس قائمة
/// المشاركة المعتادة، وفيها غالبًا خيار "طباعة" مباشر لو الجهاز يدعمه،
/// بالإضافة لأي تطبيق طباعة مثبّت فعليًا (بما فيها RawBT نفسه المستخدم
/// بنسخة أندرويد للطباعة الحرارية المباشرة) — أوسع وأوثق بكثير من محاولة
/// استدعاء حوار طباعة المتصفح مباشرة.
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  // موجودة فقط لمطابقة شكل الواجهة مع print_service_io.dart (راجع
  // print_service.dart الذي يستخدمها بغض النظر عن المنصة) — لا معنى لها
  // فعليًا على الويب لأن الطباعة هنا تمر بقائمة مشاركة النظام دائمًا.
  final List<String> lastAttemptLog = [];
  String? lastError;

  Future<List<PrinterDevice>> getPairedDevices() async => const [];

  Future<bool> connect(String macAddress) async => false;

  Future<bool> get isConnected async => false;

  Future<void> disconnect() async {}

  Future<bool> verifyConnection(String? printerMac) async => false;

  Future<bool> printPdfBytes(Uint8List pdfBytes,
      {String? printerMac, int blackThreshold = 175}) async {
    return _shareForPrinting(pdfBytes);
  }

  Future<bool> printViaSystemDialog(Uint8List pdfBytes) async {
    return _shareForPrinting(pdfBytes);
  }

  Future<bool> _shareForPrinting(Uint8List pdfBytes) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(pdfBytes, mimeType: 'application/pdf')],
          fileNameOverrides: const ['invoice.pdf'],
        ),
      );
      return result.status == ShareResultStatus.success;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}
