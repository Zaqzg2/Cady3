package com.cady.cadysalesapp

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * طبقة بلوتوث كلاسيكي (SPP) أصلية مكتوبة خصيصًا لكادي — بديل مباشر لمكتبة
 * print_bluetooth_thermal الخارجية بعد إثبات أنها تفشل بالكتابة على هذا
 * الجهاز تحديدًا رغم نجاح الاتصال الظاهري في كل محاولة (راجع سجلات
 * lastAttemptLog بالتطبيق: connect() ينجح دائمًا، لكن writeBytes() يفشل
 * فورًا خلال أقل من 10ms، حتى بعد إعادة اتصال كاملة). لا اعتماد هنا على أي
 * مكتبة خارجية ولا أي كود مأخوذ من تطبيق آخر — فقط android.bluetooth
 * القياسية الموثّقة رسميًا من جوجل.
 *
 * الفرق الجوهري عن المكتبة السابقة: عند فشل إنشاء/فتح المقبس بالطريقة
 * القياسية (createRfcommSocketToServiceRecord، تعتمد على اكتشاف خدمة SDP)،
 * نُجرّب فورًا مقبسًا احتياطيًا على القناة الخام رقم 1
 * (createRfcommSocket عبر reflection) — حل معروف وشائع تحديدًا لطابعات
 * حرارية رخيصة عندها تطبيق SDP غير موثوق، وهو بالضبط النمط اللي يُنتج
 * عرض "الاتصال نجح لكن الكتابة تفشل" اللي شخّصناه بسجلات هذا الجهاز.
 *
 * كذلك: أي فشل كتابة يُبطل مرجع المقبس فورًا (socket = null) بدل تركه
 * "يبدو متصلاً" وهو ميت فعليًا — هذا هو جذر مشكلة "متصلة بالإعدادات لكن
 * الطباعة تفشل" التي كانت السبب الأصلي لكل هذا التشخيص.
 */
class BluetoothPrinterBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.cady.cadysalesapp/bt_printer"
        private const val TAG = "KadyBtPrinter"
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val adapter: BluetoothAdapter? by lazy {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        manager?.adapter
    }

    private var socket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null

    // كل عمليات البلوتوث (اتصال/كتابة) عمليات حاجبة (blocking) ويُمنع تنفيذها
    // على الخيط الرئيسي — خيط خلفي واحد مخصص يكفي (الاتصال بطابعة واحدة في
    // كل مرة أصلاً)، والنتيجة تُعاد لفلاتر عبر mainHandler كما يتطلب MethodChannel.
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pairedDevices" -> runOnIo(result) { pairedDevicesSync() }
            "connect" -> {
                val mac = call.argument<String>("mac")
                if (mac == null) {
                    result.error("bad_args", "mac مطلوب", null); return
                }
                runOnIo(result) { connectSync(mac) }
            }
            "disconnect" -> runOnIo(result) { disconnectSync() }
            "isConnected" -> runOnIo(result) { isConnectedSync() }
            "writeBytes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("bad_args", "bytes مطلوبة", null); return
                }
                runOnIo(result) { writeBytesSync(bytes) }
            }
            else -> result.notImplemented()
        }
    }

    private fun runOnIo(result: MethodChannel.Result, block: () -> Any?) {
        ioExecutor.execute {
            val value: Any? = try {
                block()
            } catch (e: Exception) {
                Log.w(TAG, "bt_printer error: ${e.message}", e)
                mainHandler.post { result.error("bt_error", e.message, null) }
                return@execute
            }
            mainHandler.post { result.success(value) }
        }
    }

    private fun pairedDevicesSync(): List<Map<String, String>> {
        val bonded = adapter?.bondedDevices ?: emptySet()
        return bonded.map { d -> mapOf("name" to (safeName(d) ?: d.address), "mac" to d.address) }
    }

    private fun safeName(d: BluetoothDevice): String? = try {
        d.name
    } catch (e: SecurityException) {
        null
    }

    private fun connectSync(mac: String): Boolean {
        disconnectSync()
        val device = adapter?.getRemoteDevice(mac) ?: return false
        try { adapter?.cancelDiscovery() } catch (_: Exception) {}

        var newSocket = openSocket(device, useFallbackChannel = false)
        try {
            newSocket?.connect()
        } catch (e: IOException) {
            Log.w(TAG, "المقبس القياسي فشل (${e.message})، تجربة القناة الخام 1...")
            try { newSocket?.close() } catch (_: Exception) {}
            newSocket = openSocket(device, useFallbackChannel = true)
            try {
                newSocket?.connect()
            } catch (e2: IOException) {
                Log.w(TAG, "فشل الاتصال الاحتياطي أيضًا: ${e2.message}")
                try { newSocket?.close() } catch (_: Exception) {}
                return false
            }
        }

        if (newSocket == null || newSocket.isConnected.not()) return false
        socket = newSocket
        outputStream = newSocket.outputStream
        return true
    }

    private fun openSocket(device: BluetoothDevice, useFallbackChannel: Boolean): BluetoothSocket? {
        return try {
            if (!useFallbackChannel) {
                device.createRfcommSocketToServiceRecord(SPP_UUID)
            } else {
                device.javaClass
                    .getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    .invoke(device, 1) as BluetoothSocket
            }
        } catch (e: Exception) {
            Log.w(TAG, "تعذّر إنشاء المقبس (fallback=$useFallbackChannel): ${e.message}")
            null
        }
    }

    private fun isConnectedSync(): Boolean = socket?.isConnected == true

    private fun writeBytesSync(bytes: ByteArray): Boolean {
        val out = outputStream ?: return false
        return try {
            out.write(bytes)
            out.flush()
            true
        } catch (e: IOException) {
            Log.w(TAG, "فشلت الكتابة: ${e.message}")
            // المقبس مات فعليًا — أبطل المرجع فورًا حتى لا تُبنى محاولة تالية
            // على افتراض "متصل" خاطئ (جذر المشكلة الأصلية).
            try { socket?.close() } catch (_: Exception) {}
            socket = null
            outputStream = null
            false
        }
    }

    private fun disconnectSync(): Boolean {
        return try {
            outputStream?.close()
            socket?.close()
            true
        } catch (e: Exception) {
            false
        } finally {
            outputStream = null
            socket = null
        }
    }
}
