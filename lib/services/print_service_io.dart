import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';

// نحتفظ بالحزمة كـ fallback لمنصات غير أندرويد (iOS / سطح المكتب)
// حتى لا نكسر الطباعة هناك. على أندرويد نستخدم الطبقة الأصلية عبر MethodChannel.
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'printer_device.dart';

/// خدمة الطباعة الحرارية 80مم.
///
/// على **أندرويد**: تستخدم طبقة Native (BluetoothPrinterService.kt)
/// عبر MethodChannel — بدون الاعتماد على print_bluetooth_thermal.
///
/// على **iOS / سطح المكتب**: تبقى تستخدم print_bluetooth_thermal كـ fallback.
///
/// السبب في طباعة "صورة" بدل نص ESC/POS مباشر: الطابعات الحرارية
/// تعتمد على صفحات ترميز (codepages) لا تدعم تشكيل الحروف العربية بشكل
/// صحيح. لذلك نحوّل نفس PDF المُنتَج فعليًا (نفس تصميم 80مم) إلى صورة
/// نقطية (raster) ثم نرسلها بأوامر ESC/POS كصورة — فتخرج مطابقة تمامًا
/// لما يظهر في PDF، بما في ذلك النصوص العربية والشعار والتوقيع.
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  static const _channel = MethodChannel('com.cady.cadysalesapp/bluetooth_printer');

  /// هل المنصة الحالية أندرويد؟ (نستخدم الـ Native فقط عليها)
  bool get _useNative => !kIsWeb && Platform.isAndroid;

  /// طلب صلاحيات البلوتوث اللازمة (Android 12+ يحتاج CONNECT + SCAN).
  /// يُستدعى تلقائيًا قبل getPairedDevices / connect.
  Future<bool> ensureBluetoothPermissions() async {
    if (!_useNative) return true;

    // على أندرويد 12+ (API 31+) الصلاحيات الجديدة إلزامية
    final perms = <Permission>[
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      // بعض الأجهزة/الإصدارات ما زالت تطلب الموقع لقائمة الأجهزة
      Permission.locationWhenInUse,
    ];

    final statuses = await perms.request();
    final allGranted = statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );
    if (!allGranted) {
      print('Bluetooth permissions not fully granted: $statuses');
    }
    return allGranted;
  }

  /// الأجهزة المقترنة مسبقًا مع الهاتف (يجب إقران الطابعة أولًا من إعدادات
  /// بلوتوث النظام قبل ظهورها هنا)
  Future<List<PrinterDevice>> getPairedDevices() async {
    if (_useNative) {
      await ensureBluetoothPermissions();
      try {
        final list = await _channel.invokeMethod<List<dynamic>>('getPairedDevices');
        if (list == null) return [];
        return list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return PrinterDevice(
            name: m['name'] as String? ?? 'Unknown',
            macAddress: m['macAddress'] as String? ?? '',
          );
        }).toList();
      } on PlatformException catch (e) {
        // صلاحيات أو بلوتوث مطفأ
        print('Native getPairedDevices error: ${e.message}');
        return [];
      }
    }

    // Fallback: الحزمة القديمة
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return list
        .map((d) => PrinterDevice(name: d.name, macAddress: d.macAdress))
        .toList();
  }

  Future<bool> connect(String macAddress) async {
    if (_useNative) {
      await ensureBluetoothPermissions();
      try {
        final ok = await _channel.invokeMethod<bool>(
          'connect',
          {'macAddress': macAddress},
        );
        return ok ?? false;
      } on PlatformException catch (e) {
        print('Native connect error: ${e.message}');
        return false;
      }
    }
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<bool> get isConnected async {
    if (_useNative) {
      try {
        final ok = await _channel.invokeMethod<bool>('isConnected');
        return ok ?? false;
      } on PlatformException {
        return false;
      }
    }
    return PrintBluetoothThermal.connectionStatus;
  }

  Future<void> disconnect() async {
    if (_useNative) {
      try {
        await _channel.invokeMethod('disconnect');
      } on PlatformException catch (e) {
        print('Native disconnect error: ${e.message}');
      }
      return;
    }
    await PrintBluetoothThermal.disconnect;
  }

  /// يحوّل أول صفحة من ملف PDF (المُصمَّم أصلاً بعرض 80مم) إلى صورة، ثم
  /// يطبعها عبر البلوتوث على طابعة 80مم حرارية متصلة مسبقًا.
  ///
  /// [printerMac] عنوان آخر طابعة محفوظة بالإعدادات (اختياري). مقبس
  /// البلوتوث الفعلي ينقطع بصمت أحيانًا كثيرة (بعد قفل الشاشة، خمول لبضع
  /// دقائق، تذبذب الراديو...) حتى لو بقيت الإعدادات تُظهر "متصلة" لأنها
  /// تعرض آخر طابعة نجح الاتصال بها فقط، وليس حالة المقبس الحيّة. لذلك إن
  /// لم يكن هناك اتصال فعلي الآن، نحاول إعادة الاتصال تلقائيًا بهذا العنوان
  /// قبل اعتبار الطباعة فاشلة.
  Future<bool> printPdfBytes(Uint8List pdfBytes, {String? printerMac}) async {
    var connected = await isConnected;
    if (!connected && printerMac != null && printerMac.isNotEmpty) {
      connected = await connect(printerMac);
    }
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

    return _writeBytes(Uint8List.fromList(bytes));
  }

  Future<bool> _writeBytes(Uint8List data) async {
    if (_useNative) {
      try {
        // نمرّر البايتات كـ List<int> لأن MethodChannel يدعمها مباشرة
        final ok = await _channel.invokeMethod<bool>(
          'writeBytes',
          {'bytes': data.toList()},
        );
        return ok ?? false;
      } on PlatformException catch (e) {
        print('Native writeBytes error: ${e.message}');
        return false;
      }
    }
    return PrintBluetoothThermal.writeBytes(data);
  }
}
