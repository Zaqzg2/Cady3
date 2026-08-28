#!/usr/bin/env python3
"""
يربط طبقة البلوتوث الأصلية (native/BluetoothPrinterBridge.kt) بمشروع
android/ المُولَّد. android/ هنا غير مُتتبَّع بـ git ويُعاد توليده من الصفر
(عبر flutter create) في كل تشغيلة بناء لا يجد فيها المجلد موجودًا مسبقًا
(راجع خطوة "توليد مجلد android إن لم يكن موجودًا" في build-apk.yml) —
لذلك لا يمكن الاعتماد على وضع الملف مباشرة داخل android/؛ نحتفظ بالمصدر
الحقيقي في native/ (متتبَّع بـ git بشكل عادي) وننسخه لمكانه الصحيح هنا في
كل تشغيلة، تمامًا كما تُرقَّع باقي ملفات android/ المولَّدة.

آمن للتكرار (idempotent): لا يُدرج ربط القناة مرتين إن أُعيد تشغيل السكربت
على نفس MainActivity.kt.
"""
import re
import shutil
from pathlib import Path

PACKAGE_DIR = Path("android/app/src/main/kotlin/com/cady/cadysalesapp")
BRIDGE_SOURCE = Path("native/BluetoothPrinterBridge.kt")
BRIDGE_DEST = PACKAGE_DIR / "BluetoothPrinterBridge.kt"

CHANNEL_MARKER = "BluetoothPrinterBridge.CHANNEL"

REGISTRATION_BLOCK = """
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BluetoothPrinterBridge.CHANNEL
        ).setMethodCallHandler(BluetoothPrinterBridge(applicationContext))
    }
"""

NEEDED_IMPORTS = [
    "import io.flutter.embedding.engine.FlutterEngine",
    "import io.flutter.plugin.common.MethodChannel",
]


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
        print(f"{path}: القناة مربوطة مسبقًا — تخطي.")
        return

    if path.suffix == ".java":
        print(f"تحذير: {path} بلغة Java — هذا السكربت يدعم Kotlin فقط حاليًا؛ "
              "أضف الربط يدويًا (راجع تعليق BluetoothPrinterBridge.kt).")
        return

    text = add_missing_imports(text)

    # الحالة الشائعة من flutter create: تصريح الصنف بلا جسم إطلاقًا
    #   class MainActivity : FlutterActivity()
    no_body = re.compile(r"(class\s+MainActivity\s*:\s*FlutterActivity\s*\(\s*\))(?!\s*\{)")
    if no_body.search(text):
        text = no_body.sub(r"\1 {" + REGISTRATION_BLOCK + "}", text, count=1)
    else:
        # الصنف له جسم بالفعل { ... } — أدرج التابع مباشرة بعد قوس الفتح
        has_body = re.compile(r"(class\s+MainActivity\s*:\s*FlutterActivity\s*\(\s*\)\s*\{)")
        if has_body.search(text):
            text = has_body.sub(r"\1" + REGISTRATION_BLOCK, text, count=1)
        else:
            print(f"تحذير: تعذّر التعرف على تصريح الصنف داخل {path} — لم يُعدَّل، أضفه يدويًا.")
            return

    path.write_text(text, encoding="utf-8")
    print(f"تم ربط قناة BluetoothPrinterBridge داخل {path}")


def main():
    android_main = Path("android/app/src/main")
    if not android_main.exists():
        print("تحذير: android/app/src/main غير موجود بعد — تخطي.")
        return

    if not BRIDGE_SOURCE.exists():
        print(f"تحذير: {BRIDGE_SOURCE} غير موجود بالمستودع — تخطي نسخ طبقة البلوتوث الأصلية.")
        return

    PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy(BRIDGE_SOURCE, BRIDGE_DEST)
    print(f"تم نسخ BluetoothPrinterBridge.kt إلى {BRIDGE_DEST}")

    main_activity = find_main_activity()
    if main_activity is None:
        print("تحذير: لم يُعثر على MainActivity.kt أو .java — تخطي ربط القناة.")
        return
    patch_main_activity(main_activity)


if __name__ == "__main__":
    main()
