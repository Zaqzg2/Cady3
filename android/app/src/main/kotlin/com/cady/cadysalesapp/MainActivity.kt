package com.cady.cadysalesapp

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * نقطة الدخول الأصلية لأندرويد.
 * تسجّل MethodChannel باسم "com.cady.cadysalesapp/bluetooth_printer"
 * وتربطه بـ BluetoothPrinterService.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.cady.cadysalesapp/bluetooth_printer"
    }

    private lateinit var printerService: BluetoothPrinterService
    // خيط خلفي لعمليات البلوتوث الثقيلة (connect / write)
    private val bgExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printerService = BluetoothPrinterService(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPairedDevices" -> {
                        try {
                            val devices = printerService.getPairedDevices()
                            result.success(devices)
                        } catch (e: Exception) {
                            result.error("PAIRED_ERROR", e.message, null)
                        }
                    }

                    "connect" -> {
                        val mac = call.argument<String>("macAddress")
                        if (mac.isNullOrBlank()) {
                            result.error("INVALID_ARG", "macAddress is required", null)
                            return@setMethodCallHandler
                        }
                        // الاتصال قد يستغرق ثوانٍ — ننفّذه في الخلفية
                        bgExecutor.execute {
                            val ok = try {
                                printerService.connect(mac)
                            } catch (e: Exception) {
                                false
                            }
                            // النتيجة يجب أن تُعاد على الـ main thread عبر result
                            runOnUiThread {
                                result.success(ok)
                            }
                        }
                    }

                    "isConnected" -> {
                        result.success(printerService.isConnected())
                    }

                    "getConnectedMac" -> {
                        result.success(printerService.getConnectedMac())
                    }

                    "disconnect" -> {
                        try {
                            printerService.disconnect()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("DISCONNECT_ERROR", e.message, null)
                        }
                    }

                    "writeBytes" -> {
                        val bytesList = call.argument<List<Int>>("bytes")
                        if (bytesList == null) {
                            result.error("INVALID_ARG", "bytes is required", null)
                            return@setMethodCallHandler
                        }
                        val data = ByteArray(bytesList.size) { i -> bytesList[i].toByte() }
                        bgExecutor.execute {
                            val ok = try {
                                printerService.writeBytes(data)
                            } catch (e: Exception) {
                                false
                            }
                            runOnUiThread {
                                result.success(ok)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (::printerService.isInitialized) {
            printerService.dispose()
        }
        bgExecutor.shutdownNow()
        super.onDestroy()
    }
}
