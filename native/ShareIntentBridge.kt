package com.cady.cadysalesapp

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.Executors

/**
 * يقرأ أي ملف وصل التطبيق عبر مشاركة أندرويد (مثلاً: مستخدم يضغط "مشاركة"
 * على ملف مزامنة/نسخة احتياطية بواتساب ويختار كادي من القائمة، أو يضغط
 * على الملف مباشرة بمدير الملفات) بدل اضطراره لفتح منتقي الملفات يدويًا
 * والبحث عن الملف بنفسه داخل التطبيق — نفس فكرة "Sync Inbox حقيقي داخل
 * التطبيق" بدل الخروج الذهني منه لملفات الجهاز.
 *
 * يدعم الحالتين: التطبيق كان مغلقًا تمامًا (النية تصل عبر onCreate)،
 * والتطبيق كان مفتوحًا بالفعل (النية تصل عبر onNewIntent، وlaunchMode
 * الافتراضي "singleTop" من flutter create كافٍ لهذا). MainActivity تُمرّر
 * كلتا الحالتين هنا عبر offerIntent، وDart يسحبها بطلب واحد (getPendingShare)
 * عند الإقلاع وعند عودة التطبيق للواجهة — فتُستهلك فور القراءة ولا تُعاد
 * مرة ثانية بالخطأ لو أُعيد فتح نفس الشاشة.
 *
 * قراءة محتوى الملف تمر دومًا عبر ContentResolver (لا نفترض مسار ملف على
 * القرص مباشرة) لأن أندرويد الحديث يُسلّم روابط content:// من التطبيق
 * المُرسِل (واتساب مثلًا)، لا مسارات file:// خام.
 */
class ShareIntentBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.cady.cadysalesapp/share_intent"
        private const val TAG = "KadyShareIntent"
    }

    // النية المعلّقة التي لم تُستهلك بعد من طرف Dart، إن وُجدت
    private var pendingIntent: Intent? = null

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** يُستدعى من MainActivity عند onCreate وonNewIntent لتسجيل نية واردة محتملة */
    fun offerIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val hasStream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) != null
        if (action == Intent.ACTION_SEND && hasStream) {
            pendingIntent = intent
        } else if (action == Intent.ACTION_VIEW && intent.data != null) {
            pendingIntent = intent
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPendingShare" -> consumePendingShare(result)
            else -> result.notImplemented()
        }
    }

    private fun consumePendingShare(result: MethodChannel.Result) {
        val intent = pendingIntent
        pendingIntent = null // تُستهلك فورًا — لا تُعاد بطلب لاحق حتى لو فشلت القراءة
        if (intent == null) {
            result.success(null)
            return
        }
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        if (uri == null) {
            result.success(null)
            return
        }
        ioExecutor.execute {
            val value = try {
                readUri(uri)
            } catch (e: Exception) {
                Log.w(TAG, "تعذّرت قراءة الملف المشارك: ${e.message}", e)
                null
            }
            mainHandler.post { result.success(value) }
        }
    }

    private fun readUri(uri: Uri): Map<String, String>? {
        val resolver = activity.contentResolver
        val name = queryDisplayName(uri) ?: "ملف_مستلم.json"
        val content = resolver.openInputStream(uri)?.use { stream ->
            BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).readText()
        } ?: return null
        return mapOf("fileName" to name, "content" to content)
    }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }
        } catch (e: Exception) {
            null
        }
    }
}
