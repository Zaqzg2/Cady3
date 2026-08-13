import 'dart:typed_data';
import 'package:printing/printing.dart';

import 'printer_device.dart';

/// خدمة الطباعة على الويب — لا يوجد وصول لطابعات البلوتوث الحرارية من
/// المتصفح إطلاقًا (لا يوجد Web API لهذا)، لذلك "الطباعة" هنا تفتح مربع
/// حوار الطباعة الأصلي بالمتصفح (يسمح للمستخدم بالطباعة على أي طابعة
/// متصلة بجهازه، أو الحفظ كـ PDF).
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  // موجودة فقط لمطابقة شكل الواجهة مع print_service_io.dart (راجع
  // print_service.dart الذي يستخدمها بغض النظر عن المنصة) — لا معنى لها
  // فعليًا على الويب لأن الطباعة هنا تمر بحوار المتصفح الأصلي دائمًا.
  final List<String> lastAttemptLog = [];
  String? lastError;

  Future<List<PrinterDevice>> getPairedDevices() async => const [];

  Future<bool> connect(String macAddress) async => false;

  Future<bool> get isConnected async => false;

  Future<void> disconnect() async {}

  Future<bool> verifyConnection(String? printerMac) async => false;

  Future<bool> printPdfBytes(Uint8List pdfBytes,
      {String? printerMac, int blackThreshold = 175}) async {
    return Printing.layoutPdf(onLayout: (format) async => pdfBytes);
  }

  Future<bool> printViaSystemDialog(Uint8List pdfBytes) async {
    return Printing.layoutPdf(onLayout: (format) async => pdfBytes);
  }
}
