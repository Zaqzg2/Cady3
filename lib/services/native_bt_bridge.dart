import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'printer_device.dart';

/// جسر Platform Channel لطبقة البلوتوث الأصلية (Kotlin) — راجع
/// android/app/src/main/kotlin/com/cady/cadysalesapp/BluetoothPrinterBridge.kt
/// لشرح كامل السبب والتفاصيل. هذا بديل مباشر لمكتبة print_bluetooth_thermal
/// الخارجية بعد إثبات أنها تفشل بالكتابة على أجهزة معيّنة رغم نجاح الاتصال
/// الظاهري. تُستخدم من print_service_io.dart فقط.
class NativeBtBridge {
  NativeBtBridge._();
  static final NativeBtBridge instance = NativeBtBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.cady.cadysalesapp/bt_printer');

  Future<List<PrinterDevice>> pairedDevices() async {
    final result = await _channel.invokeMethod<List<dynamic>>('pairedDevices');
    if (result == null) return [];
    return result
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((m) => PrinterDevice(
              name: (m['name'] as String?) ?? '',
              macAddress: (m['mac'] as String?) ?? '',
            ))
        .toList();
  }

  Future<bool> connect(String mac) async {
    final ok = await _channel.invokeMethod<bool>('connect', {'mac': mac});
    return ok ?? false;
  }

  Future<bool> disconnect() async {
    final ok = await _channel.invokeMethod<bool>('disconnect');
    return ok ?? false;
  }

  Future<bool> isConnected() async {
    final ok = await _channel.invokeMethod<bool>('isConnected');
    return ok ?? false;
  }

  Future<bool> writeBytes(Uint8List bytes) async {
    final ok = await _channel.invokeMethod<bool>('writeBytes', {'bytes': bytes});
    return ok ?? false;
  }
}
