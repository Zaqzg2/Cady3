#!/usr/bin/env python3
"""
يربط طبقة استقبال المشاركة الأصلية (native/ShareIntentBridge.kt) بمشروع
android/ المُولَّد — نفس فكرة patch_add_bluetooth_bridge.py تمامًا ولنفس
السبب: android/ غير مُتتبَّع بـ git ويُعاد توليده من الصفر في كل بناء،
فلا يمكن الاعتماد على وضع الملف مباشرة داخله؛ المصدر الحقيقي في native/
(متتبَّع بـ git) ويُنسخ لمكانه الصحيح هنا في كل تشغيلة.

الفرق الوحيد عن سكربت البلوتوث: هذا السكربت قد يعمل بعد أن سبق وأضاف
سكربت البلوتوث تابع configureFlutterEngine بنفسه — لذا يتحقق أولًا إن كان
هذا التابع موجودًا مسبقًا: إن وُجد يُضيف تسجيل قناتنا بداخله (بدل إنشاء
تابع override مكرر بنفس الاسم، وهو خطأ ترجمة في Kotlin)، وإلا يُنشئ
التابع من الصفر تمامًا كما يفعل سكربت البلوتوث. يعمل بشكل صحيح بغضّ
النظر عن ترتيب تشغيل السكربطين.

آمن للتكرار (idempotent): لا يُدرج شيئًا مرتين إن أُعيد تشغيله.
"""
import re
import shutil
from pathlib import Path

PACKAGE_DIR = Path("android/app/src/main/kotlin/com/cady/cadysalesapp")
BRIDGE_SOURCE = Path("native/ShareIntentBridge.kt")
BRIDGE_DEST = PACKAGE_DIR / "ShareIntentBridge.kt"

CHANNEL_MARKER = "ShareIntentBridge.CHANNEL"

NEEDED_IMPORTS = [
    "import android.content.Intent",
    "import android.os.Bundle",
    "import io.flutter.embedding.engine.FlutterEngine",
    "import io.flutter.plugin.common.MethodChannel",
]

FIELD_AND_LIFECYCLE_BLOCK = """
    // "by lazy" مقصود هنا وليس lateinit + تهيئة داخل onCreate: أندرويد
    // فلاتر يستدعي configureFlutterEngine من *داخل* super.onCreate نفسها
    // (قبل تنفيذ أي سطر بعدها بجسم onCreate) — فلو هيّأنا shareIntentBridge
    // بعد super.onCreate لكان configureFlutterEngine يصل قبل التهيئة
    // ويرمي UninitializedPropertyAccessException (تعطّل فوري عند فتح
    // التطبيق). "by lazy" يهيّئها عند أول استخدام فعلي (من داخل
    // configureFlutterEngine ذاتها)، فتكون جاهزة دومًا وقت الحاجة إليها
    // بغضّ النظر عن ترتيب الاستدعاء الداخلي لفلاتر.
    private val shareIntentBridge: ShareIntentBridge by lazy { ShareIntentBridge(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        shareIntentBridge.offerIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shareIntentBridge.offerIntent(intent)
    }
"""

REGISTRATION_LINE = """        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ShareIntentBridge.CHANNEL
        ).setMethodCallHandler(shareIntentBridge)
"""

NEW_CONFIGURE_ENGINE_BLOCK = """
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
""" + REGISTRATION_LINE + """    }
"""

EXISTING_CONFIGURE_RE = re.compile(
    r"(override fun configureFlutterEngine\(flutterEngine: FlutterEngine\)\s*\{\s*\n"
    r"\s*super\.configureFlutterEngine\(flutterEngine\)\n)"
)


def find_main_activity():
    kotlin_base = Path("android/app/src/main/kotlin")
    if kotlin_base.exists():
        matches = list(kotlin_base.rglob("MainActivity.kt"))
        if matches:
            return matches[0]
    java_base = Path("android/app/src/main/java")
    if java_base.exists():
        matches = list(java_base.rglob("MainActivity.java"))
        if matches:
            return matches[0]
    return None


def add_missing_imports(text: str) -> str:
    for imp in NEEDED_IMPORTS:
        if imp in text:
            continue
        import_lines = list(re.finditer(r"^import .*$", text, flags=re.MULTILINE))
        if import_lines:
            insert_at = import_lines[-1].end()
            text = text[:insert_at] + "\n" + imp + text[insert_at:]
        else:
            text = re.sub(r"(^package .*$)", r"\1\n\n" + imp, text, count=1, flags=re.MULTILINE)
    return text


def patch_main_activity(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if CHANNEL_MARKER in text:
        print(f"{path}: قناة المشاركة مربوطة مسبقًا — تخطي.")
        return

    if path.suffix == ".java":
        print(f"تحذير: {path} بلغة Java — هذا السكربت يدعم Kotlin فقط حاليًا؛ "
              "أضف الربط يدويًا (راجع تعليق ShareIntentBridge.kt).")
        return

    text = add_missing_imports(text)

    if EXISTING_CONFIGURE_RE.search(text):
        # تابع configureFlutterEngine موجود مسبقًا (غالبًا من سكربت
        # البلوتوث) — أضف تسجيل قناتنا بداخله بدل تابع مكرر
        text = EXISTING_CONFIGURE_RE.sub(r"\1" + REGISTRATION_LINE, text, count=1)
        lifecycle_block = FIELD_AND_LIFECYCLE_BLOCK
    else:
        lifecycle_block = FIELD_AND_LIFECYCLE_BLOCK + NEW_CONFIGURE_ENGINE_BLOCK

    # الحالة الشائعة من flutter create: تصريح الصنف بلا جسم إطلاقًا
    no_body = re.compile(r"(class\s+MainActivity\s*:\s*FlutterActivity\s*\(\s*\))(?!\s*\{)")
    if no_body.search(text):
        text = no_body.sub(r"\1 {" + lifecycle_block + "}", text, count=1)
    else:
        # الصنف له جسم بالفعل { ... } (من سكربت آخر سبق وشغّل) — أدرج
        # مباشرة بعد قوس الفتح، قبل أي محتوى موجود
        has_body = re.compile(r"(class\s+MainActivity\s*:\s*FlutterActivity\s*\(\s*\)\s*\{)")
        if has_body.search(text):
            text = has_body.sub(r"\1" + lifecycle_block, text, count=1)
        else:
            print(f"تحذير: تعذّر التعرف على تصريح الصنف داخل {path} — لم يُعدَّل، أضفه يدويًا.")
            return

    path.write_text(text, encoding="utf-8")
    print(f"تم ربط قناة ShareIntentBridge داخل {path}")


def main():
    android_main = Path("android/app/src/main")
    if not android_main.exists():
        print("تحذير: android/app/src/main غير موجود بعد — تخطي.")
        return

    if not BRIDGE_SOURCE.exists():
        print(f"تحذير: {BRIDGE_SOURCE} غير موجود بالمستودع — تخطي نسخ طبقة استقبال المشاركة.")
        return

    PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy(BRIDGE_SOURCE, BRIDGE_DEST)
    print(f"تم نسخ ShareIntentBridge.kt إلى {BRIDGE_DEST}")

    main_activity = find_main_activity()
    if main_activity is None:
        print("تحذير: لم يُعثر على MainActivity.kt أو .java — تخطي ربط القناة.")
        return
    patch_main_activity(main_activity)


if __name__ == "__main__":
    main()
