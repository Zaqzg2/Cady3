package com.cady.cadysalesapp

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Build
import android.util.Log
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * خدمة طباعة بلوتوث حرارية أصلية لأندرويد.
 * تتصل بالطابعات عبر بروتوكول SPP (Serial Port Profile)
 * وتكتب بايتات ESC/POS مباشرة.
 *
 * تُربط بـ Flutter عبر MethodChannel من MainActivity.
 */
class BluetoothPrinterService(private val context: Context) {

    companion object {
        private const val TAG = "BluetoothPrinter"
        // UUID القياسي لـ Serial Port Profile (SPP) — تستخدمه أغلب طابعات الإيصالات الحرارية
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            manager?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private var socket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private var connectedMac: String? = null

    // ننفّذ عمليات البلوتوث على خيط خلفي لتجنب حظر الـ UI
    private val executor = Executors.newSingleThreadExecutor()

    /**
     * قائمة الأجهزة المقترنة مسبقًا (bonded).
     * يجب أن يكون البلوتوث مفعّلاً وأن تكون الصلاحيات ممنوحة.
     */
    @SuppressLint("MissingPermission")
    fun getPairedDevices(): List<Map<String, String>> {
        val adapter = bluetoothAdapter ?: return emptyList()
        if (!adapter.isEnabled) return emptyList()

        return try {
            val bonded: Set<BluetoothDevice> = adapter.bondedDevices ?: emptySet()
            bonded.map { device ->
                mapOf(
                    "name" to (device.name ?: "Unknown"),
                    "macAddress" to device.address
                )
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing Bluetooth permission for bondedDevices", e)
            emptyList()
        }
    }

    /**
     * الاتصال بجهاز عبر عنوان MAC.
     * يعيد true عند نجاح فتح المقبس وكتابة الـ stream.
     */
    @SuppressLint("MissingPermission")
    fun connect(macAddress: String): Boolean {
        // أغلق أي اتصال سابق
        disconnectInternal()

        val adapter = bluetoothAdapter ?: run {
            Log.e(TAG, "BluetoothAdapter is null")
            return false
        }
        if (!adapter.isEnabled) {
            Log.e(TAG, "Bluetooth is disabled")
            return false
        }

        return try {
            val device = adapter.getRemoteDevice(macAddress)
            // إلغاء الاكتشاف قبل الاتصال (يُحسّن استقرار الاتصال)
            try {
                if (adapter.isDiscovering) adapter.cancelDiscovery()
            } catch (_: Exception) { /* ignore */ }

            // نحاول الاتصال عبر createRfcommSocketToServiceRecord أولاً
            var sock: BluetoothSocket? = null
            try {
                sock = device.createRfcommSocketToServiceRecord(SPP_UUID)
                sock.connect()
            } catch (e: IOException) {
                Log.w(TAG, "Standard SPP connect failed, trying fallback reflection", e)
                // بعض الطابعات القديمة تحتاج الطريقة الانعكاسية
                try {
                    sock?.close()
                } catch (_: Exception) {}
                sock = createFallbackSocket(device)
                sock?.connect()
            }

            if (sock == null || !sock.isConnected) {
                Log.e(TAG, "Socket not connected after attempts")
                return false
            }

            socket = sock
            outputStream = sock.outputStream
            connectedMac = macAddress
            Log.i(TAG, "Connected to $macAddress")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing Bluetooth permission for connect", e)
            false
        } catch (e: IOException) {
            Log.e(TAG, "IOException during connect to $macAddress", e)
            disconnectInternal()
            false
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error during connect", e)
            disconnectInternal()
            false
        }
    }

    /**
     * طريقة احتياطية لبعض أجهزة أندرويد/الطابعات التي تفشل مع createRfcommSocketToServiceRecord
     */
    @SuppressLint("MissingPermission")
    private fun createFallbackSocket(device: BluetoothDevice): BluetoothSocket? {
        return try {
            val method = device.javaClass.getMethod(
                "createRfcommSocket",
                Int::class.javaPrimitiveType
            )
            method.invoke(device, 1) as BluetoothSocket
        } catch (e: Exception) {
            Log.e(TAG, "Fallback socket creation failed", e)
            null
        }
    }

    fun isConnected(): Boolean {
        val sock = socket
        return sock != null && sock.isConnected && outputStream != null
    }

    fun getConnectedMac(): String? = if (isConnected()) connectedMac else null

    /**
     * كتابة بايتات خام (أوامر ESC/POS أو صورة raster).
     * يجب أن يكون الاتصال قائمًا.
     */
    fun writeBytes(data: ByteArray): Boolean {
        if (!isConnected()) {
            Log.e(TAG, "writeBytes called while not connected")
            return false
        }
        return try {
            val stream = outputStream!!
            // نكتب على دفعات لتجنب تجاوز buffer الطابعة
            val chunkSize = 512
            var offset = 0
            while (offset < data.size) {
                val end = minOf(offset + chunkSize, data.size)
                stream.write(data, offset, end - offset)
                stream.flush()
                offset = end
                // استراحة قصيرة بين الدفعات لبعض الطابعات البطيئة
                if (offset < data.size) {
                    Thread.sleep(20)
                }
            }
            true
        } catch (e: IOException) {
            Log.e(TAG, "IOException while writing bytes", e)
            // الاتصال انقطع — ننظّف الحالة
            disconnectInternal()
            false
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error while writing", e)
            false
        }
    }

    fun disconnect() {
        disconnectInternal()
    }

    private fun disconnectInternal() {
        try {
            outputStream?.close()
        } catch (_: Exception) {}
        try {
            socket?.close()
        } catch (_: Exception) {}
        outputStream = null
        socket = null
        connectedMac = null
        Log.i(TAG, "Disconnected")
    }

    /** استدعاء عند تدمير الخدمة / إغلاق التطبيق */
    fun dispose() {
        disconnectInternal()
        executor.shutdownNow()
    }
}
