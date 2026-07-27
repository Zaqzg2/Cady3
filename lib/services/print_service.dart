import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

/// خدمة الطباعة الحرارية 80مم عبر البلوتوث مباشرة (بدون تطبيقات وسيطة)
///
/// السبب في طباعة "صورة" بدل نص ESC/POS مباشر: الطابعات الحرارية
/// تعتمد على صفحات ترميز (codepages) لا تدعم تشكيل الحروف العربية بشكل
/// صحيح. لذلك نحوّل نفس PDF المُنتَج فعليًا (نفس تصميم 80مم) إلى صورة
/// نقطية (raster) ثم نرسلها بأوامر ESC/POS كصورة — فتخرج مطابقة تمامًا
/// لما يظهر في PDF، بما في ذلك النصوص العربية والشعار والتوقيع.
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  /// الأجهزة المقترنة مسبقًا مع الهاتف (يجب إقران الطابعة أولًا من إعدادات
  /// بلوتوث النظام قبل ظهورها هنا)
  Future<List<BluetoothInfo>> getPairedDevices() async {
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> connect(String macAddress) async {
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<void> disconnect() => PrintBluetoothThermal.disconnect;

  /// يحوّل أول صفحة من ملف PDF (المُصمَّم أصلاً بعرض 80مم) إلى صورة، ثم
  /// يطبعها عبر البلوتوث على طابعة 80مم حرارية متصلة مسبقًا.
  Future<bool> printPdfBytes(Uint8List pdfBytes) async {
    final connected = await isConnected;
    if (!connected) return false;

    // عرض 80مم عند 203 نقطة/إنش (الدقة القياسية لأغلب طابعات الإيصالات)
    // 80mm ≈ 3.15in => العرض بالبكسل ≈ 576
    const targetWidthPx = 576;

    img.Image? finalImage;

    await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
      final pngBytes = await page.toPng();
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) continue;
      final resized = img.copyResize(decoded, width: targetWidthPx);
      finalImage = resized; // فاتورة/سند عادة صفحة واحدة (roll80)
      break;
    }

    if (finalImage == null) return false;

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.imageRaster(finalImage, align: PosAlign.center);
    bytes += generator.feed(2);
    bytes += generator.cut();

    return PrintBluetoothThermal.writeBytes(Uint8List.fromList(bytes));
  }
}
