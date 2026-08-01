#!/usr/bin/env python3
"""
الحل الجذري الحقيقي والنهائي لخطأ:
    Could not find method kotlin() for arguments [...] on project ':jni'

السبب الفعلي (موثّق رسمياً من Flutter، الإصدار 3.44+):
ابتداءً من Flutter 3.44 صار AGP (Android Gradle Plugin) الافتراضي هو
الإصدار 9.x الذي يفعّل "Built-in Kotlin" تلقائياً — أي أن AGP نفسه يتولى
دعم Kotlin مباشرة، ولم يعد يطبّق تلقائياً إضافة Kotlin Gradle Plugin
(KGP) بالطريقة القديمة عبر الامتداد kotlin { ... }.

المشكلة: حزم Dart قديمة نسبياً مثل jni-1.0.1 (تصل لمشروعنا بشكل غير
مباشر عبر path_provider_android وغيرها) لا تزال تحتوي android/build.gradle
مكتوبة على افتراض وجود KGP التقليدي مطبَّقاً، فتستدعي الدالة kotlin(...)
مباشرة. مع AGP 9 الجديد هذه الدالة لم تعد موجودة تلقائياً → فشل البناء.

الحل الرسمي من فريق Flutter نفسه (راجع:
https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
و https://github.com/flutter/flutter/issues/183910):
إضافة السطرين التاليين إلى android/gradle.properties:
    android.builtInKotlin=false
    android.newDsl=false
هذا يعيد تفعيل السلوك القديم (تطبيق KGP التقليدي تلقائياً) بشكل متوافق مع
كل الحزم القديمة، وهو "صمام أمان" (escape hatch) مؤقت وفّرته Flutter نفسها
تحديداً لدعم الحزم غير المُهاجَرة بعد لهذا التغيير — بدل تعديل إصدارات
حزم Dart يدوياً (وهو ما جرّبناه سابقاً وكسر توافق أكواد أخرى مولَّدة).

عادةً Flutter tool يضيف هذين السطرين تلقائياً عند ترقية مشروع قديم، لكن
بما أن مجلد android/ عندنا يُولَّد من الصفر بـ flutter create في كل تشغيل
CI، فهو يُنشأ مباشرة بإعدادات AGP 9 الافتراضية (بدون هذا الصمام) — لذلك
يجب إضافته يدوياً بعد كل توليد.

آمن عند التكرار (idempotent).
"""
from pathlib import Path

GRADLE_PROPS_PATH = Path("android/gradle.properties")

REQUIRED_LINES = [
    "android.builtInKotlin=false",
    "android.newDsl=false",
]


def main():
    if not GRADLE_PROPS_PATH.exists():
        print(f"تحذير: لم يُعثر على {GRADLE_PROPS_PATH} — سيتم إنشاؤه.")
        GRADLE_PROPS_PATH.parent.mkdir(parents=True, exist_ok=True)
        GRADLE_PROPS_PATH.write_text("", encoding="utf-8")

    content = GRADLE_PROPS_PATH.read_text(encoding="utf-8")
    existing_lines = {line.strip() for line in content.splitlines()}

    missing = [line for line in REQUIRED_LINES if line not in existing_lines]

    if not missing:
        print("إعدادات android.builtInKotlin / android.newDsl موجودة مسبقاً — لا حاجة للتعديل.")
        return

    addition = "\n".join(missing)
    if content and not content.endswith("\n"):
        content += "\n"
    content += (
        "\n# __CADY_AGP9_BUILTIN_KOTLIN_COMPAT__ "
        "(يعيد سلوك Kotlin Gradle Plugin التقليدي لتوافق الحزم القديمة مثل jni)\n"
        + addition
        + "\n"
    )

    GRADLE_PROPS_PATH.write_text(content, encoding="utf-8")
    print(f"تمت إضافة {len(missing)} إعداد توافق إلى {GRADLE_PROPS_PATH}: {', '.join(missing)}")


if __name__ == "__main__":
    main()
