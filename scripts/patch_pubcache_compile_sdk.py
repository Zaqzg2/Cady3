#!/usr/bin/env python3
"""
الحل الجذري (النسخة الموثوقة 100%) لخطأ:
    :file_picker is currently compiled against android-34.
    (Dependency ':flutter_plugin_android_lifecycle' requires ... compileSdk 36)

لماذا فشلت المحاولة السابقة رغم أن النمط النصي كان صحيحاً؟
لأنها اعتمدت على **تخمين** مسار مجلد pub-cache
(افتراض: PUB_CACHE أو ~/.pub-cache/hosted/pub.dev). هذا تخمين، وليس حقيقة
مضمونة — قد يختلف حسب بيئة GitHub Actions (متغير PUB_CACHE، سلوك تخزين
subosito/flutter-action المؤقت، إلخ)، وإن أخطأ التخمين فالسكربت لا يجد
شيئاً ليعدّله دون أي رسالة خطأ واضحة توقف البناء.

الحل هنا مختلف جذرياً: بدل التخمين، نقرأ الموقع **الحقيقي المؤكد** لكل
حزمة مباشرة من الملف الذي يولّده Dart/Flutter نفسه بعد `flutter pub get`:
    .dart_tool/package_config.json
هذا الملف يحتوي (لكل حزمة مستخدمة في المشروع) حقل rootUri يشير إلى
المسار الفعلي الدقيق لتلك الحزمة على القرص — بغض النظر عن أي إعدادات
كاش أو متغيرات بيئة. هذا هو نفس الملف الذي تعتمد عليه أدوات Dart
الرسمية (ومحلل Dart نفسه) لتحديد "أين تقع كل حزمة فعلياً" — فهو مصدر
الحقيقة الوحيد الموثوق 100%، لا تخمين فيه إطلاقاً.

آمن عند التكرار (idempotent).
"""
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse

TARGET_SDK = 36
PACKAGE_CONFIG_PATH = Path(".dart_tool/package_config.json")

PATTERNS = [
    (re.compile(r"(compileSdk\s+)flutter\.compileSdkVersion"), rf"\g<1>{TARGET_SDK}"),
    (re.compile(r"(compileSdk\s*=\s*)flutter\.compileSdkVersion"), rf"\g<1>{TARGET_SDK}"),
    (re.compile(r"(compileSdkVersion\s+)flutter\.compileSdkVersion"), rf"\g<1>{TARGET_SDK}"),
    (re.compile(r"(compileSdk(?:Version)?\s*\(\s*)flutter\.compileSdkVersion(\s*\))"), rf"\g<1>{TARGET_SDK}\g<2>"),
    (re.compile(r"(compileSdk(?:Version)?\s*[=\(\s]\s*)flutter\.compileSdkVersion\.toInteger\(\)"), rf"\g<1>{TARGET_SDK}"),
    # نمط عام شامل احتياطي: يغطي أي بادئة (project.flutter / rootProject.ext.flutter / إلخ)
    # وأي شكل استدعاء (بمسافة، بعلامة =، بقوس)، مع أو بدون .toInteger() في النهاية.
    # يلتقط أي حالة لم تُغطَّ صراحة بالأنماط أعلاه.
    (
        re.compile(
            r"(compileSdk(?:Version)?\s*\(?\s*=?\s*)"
            r"(?:[\w]+\.)*flutter\.compileSdkVersion(?:\.toInteger\(\))?"
            r"(\)?)"
        ),
        rf"\g<1>{TARGET_SDK}\g<2>",
    ),
]


def bump_literal_compile_sdk(match: re.Match) -> str:
    """يستبدل أي رقم compileSdk ثابت أقل من TARGET_SDK بالقيمة TARGET_SDK فقط."""
    prefix, number, suffix = match.group(1), match.group(2), match.group(3)
    if int(number) < TARGET_SDK:
        return f"{prefix}{TARGET_SDK}{suffix}"
    return match.group(0)


NUMERIC_PATTERN = (
    re.compile(r"(compileSdk(?:Version)?\s*\(?\s*=?\s*)(\d+)(\)?)"),
    bump_literal_compile_sdk,
)


def uri_to_path(root_uri: str) -> Path:
    """يحوّل rootUri (قد يكون file:// مطلق أو مسار نسبي) إلى مسار حقيقي على القرص."""
    if root_uri.startswith("file://"):
        parsed = urlparse(root_uri)
        return Path(unquote(parsed.path))
    # مسار نسبي (نادر لحزم hosted، شائع لحزم path محلية) — نسبي لمكان package_config.json
    return (PACKAGE_CONFIG_PATH.parent / root_uri).resolve()


def patch_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="ignore")
    original = text
    for pattern, replacement in PATTERNS:
        text = pattern.sub(replacement, text)
    # نمط احتياطي إضافي: أرقام compileSdk ثابتة مكتوبة يدوياً (مثل file_picker: compileSdk 34)
    pattern, callback = NUMERIC_PATTERN
    text = pattern.sub(callback, text)
    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main():
    if not PACKAGE_CONFIG_PATH.exists():
        print(
            f"خطأ: لم يُعثر على {PACKAGE_CONFIG_PATH} — يجب تشغيل 'flutter pub get' "
            "قبل هذا السكربت. تخطي الترقيع (لن يعمل بدون هذا الملف)."
        )
        return

    config = json.loads(PACKAGE_CONFIG_PATH.read_text(encoding="utf-8"))
    packages = config.get("packages", [])
    print(f"عدد الحزم المسجّلة في package_config.json: {len(packages)}")

    changed = []
    checked_no_match = []

    for pkg in packages:
        name = pkg.get("name", "?")
        root_uri = pkg.get("rootUri", "")
        if not root_uri:
            continue
        try:
            pkg_root = uri_to_path(root_uri)
        except Exception as e:
            print(f"تحذير: تعذّر تحليل مسار الحزمة {name}: {e}")
            continue

        for gradle_name in ("build.gradle", "build.gradle.kts"):
            gradle_path = pkg_root / "android" / gradle_name
            if gradle_path.exists():
                if patch_file(gradle_path):
                    changed.append((name, gradle_path))
                else:
                    checked_no_match.append(name)

    print(f"\nتم فحص {len(changed) + len(checked_no_match)} ملف android/build.gradle(.kts) فعلياً موجود على القرص.")

    if changed:
        print(f"تم رفع compileSdk إلى {TARGET_SDK} فعلياً في {len(changed)} حزمة:")
        for name, path in changed:
            print(f"  - {name}  ->  {path}")
    else:
        print("لم يتم تعديل أي ملف (إما لا يحتوي أي حزمة على flutter.compileSdkVersion، أو تم ترقيعها مسبقاً).")

    # تشخيص إضافي: هل حزمة file_picker موجودة أصلاً ووُجد ملفها؟
    file_picker_pkg = next((p for p in packages if p.get("name") == "file_picker"), None)
    if file_picker_pkg is None:
        print("\nتشخيص: حزمة file_picker غير مسجّلة إطلاقاً في package_config.json!")
    else:
        fp_root = uri_to_path(file_picker_pkg.get("rootUri", ""))
        print(f"\nتشخيص file_picker — المسار: {fp_root}")
        for gradle_name in ("build.gradle", "build.gradle.kts"):
            gradle_path = fp_root / "android" / gradle_name
            exists = gradle_path.exists()
            print(f"  {gradle_name}: موجود = {exists}")
            if exists:
                content = gradle_path.read_text(encoding="utf-8", errors="ignore")
                compile_lines = [
                    (i + 1, line) for i, line in enumerate(content.splitlines())
                    if "compileSdk" in line
                ]
                if compile_lines:
                    print(f"  الأسطر التي تحتوي compileSdk في {gradle_name} (بعد محاولة الترقيع):")
                    for lineno, line in compile_lines:
                        print(f"    [{lineno}] {line.strip()}")
                else:
                    print(f"  لا يوجد أي سطر يحتوي 'compileSdk' في {gradle_name} إطلاقاً!")


if __name__ == "__main__":
    main()
