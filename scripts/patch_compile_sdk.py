#!/usr/bin/env python3
"""
يفرض compileSdk = 36 (وtargetSdk تبعًا له) داخل android/app/build.gradle
أو android/app/build.gradle.kts — لأن بعض الحزم الحديثة (مثل file_picker
عبر اعتمادها على flutter_plugin_android_lifecycle) تتطلب compileSdk 36
فأعلى، بينما القالب الافتراضي الذي يولّده flutter create قد يستخدم 34.

بدل محاولة استبدال السطر الأصلي بنمط نصي (قد يفشل إن اختلفت صياغة القالب
بين إصدارات Flutter)، هذا السكربت يُلحق كتلة `android { ... }` جديدة في
نهاية الملف. في Gradle (Groovy وKotlin DSL) يمكن فتح كتلة android{} أكثر
من مرة في نفس الملف، والقيم المضبوطة لاحقًا (بترتيب التنفيذ من الأعلى
للأسفل) تطغى على ما سبقها — فهذا يضمن أن compileSdk يصبح 36 دائمًا مهما
كانت صياغة القالب الأصلي، وهو آمن عند التكرار (idempotent).
"""
from pathlib import Path

TARGET_SDK = 36
MARKER = "// __CADY_COMPILE_SDK_OVERRIDE__"

GROOVY_PATH = Path("android/app/build.gradle")
KOTLIN_PATH = Path("android/app/build.gradle.kts")


def patch(path: Path):
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"{path}: الترقيع مطبَّق مسبقًا — تخطي.")
        return

    is_kotlin_dsl = path.suffix == ".kts"
    if is_kotlin_dsl:
        block = f"""
{MARKER}
android {{
    compileSdk = {TARGET_SDK}
    defaultConfig {{
        targetSdk = {TARGET_SDK}
    }}
}}
"""
    else:
        block = f"""
{MARKER}
android {{
    compileSdk {TARGET_SDK}
    defaultConfig {{
        targetSdk {TARGET_SDK}
    }}
}}
"""
    path.write_text(text + "\n" + block, encoding="utf-8")
    print(f"تم إلحاق كتلة تفرض compileSdk/targetSdk = {TARGET_SDK} في {path}")


def main():
    if GROOVY_PATH.exists():
        patch(GROOVY_PATH)
    elif KOTLIN_PATH.exists():
        patch(KOTLIN_PATH)
    else:
        print("تحذير: لم يُعثر على build.gradle أو build.gradle.kts — تخطي الترقيع.")


if __name__ == "__main__":
    main()

