#!/usr/bin/env python3
"""
يفرض compileSdk = 36 على كل المشاريع الفرعية (كل الحزم/الإضافات مثل
file_picker وflutter_plugin_android_lifecycle وimage_picker_android إلخ)
عبر إلحاق كتلة `subprojects { ... }` في ملف Gradle الجذري
(android/build.gradle أو android/build.gradle.kts) — وليس فقط تطبيق التطبيق
(:app). هذا ضروري لأن بعض الحزم (مثل flutter_plugin_android_lifecycle)
تفرض متطلب compileSdk 36 على أي مشروع يعتمد عليها، بما في ذلك مشاريع
الإضافات الأخرى نفسها (file_picker, image_picker_android, ...) التي لا
تزال تُبنى افتراضيًا بقيمة flutter.compileSdkVersion الأقدم.

آمن عند التكرار (idempotent) عبر علامة مميزة.
"""
from pathlib import Path

TARGET_SDK = 36
MARKER = "// __CADY_ROOT_COMPILE_SDK_OVERRIDE__"

GROOVY_PATH = Path("android/build.gradle")
KOTLIN_PATH = Path("android/build.gradle.kts")

GROOVY_BLOCK = f"""
{MARKER}
subprojects {{ sub ->
    sub.plugins.withId("com.android.application") {{
        sub.android {{
            compileSdk {TARGET_SDK}
        }}
    }}
    sub.plugins.withId("com.android.library") {{
        sub.android {{
            compileSdk {TARGET_SDK}
        }}
    }}
}}
"""

KOTLIN_BLOCK = f"""
{MARKER}
subprojects {{
    plugins.withId("com.android.application") {{
        extensions.configure<com.android.build.gradle.BaseExtension> {{
            compileSdkVersion({TARGET_SDK})
        }}
    }}
    plugins.withId("com.android.library") {{
        extensions.configure<com.android.build.gradle.BaseExtension> {{
            compileSdkVersion({TARGET_SDK})
        }}
    }}
}}
"""


def patch(path: Path, block: str):
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"{path}: الترقيع مطبَّق مسبقًا — تخطي.")
        return
    path.write_text(text + "\n" + block, encoding="utf-8")
    print(f"تم إلحاق كتلة subprojects لفرض compileSdk={TARGET_SDK} على كل الإضافات في {path}")


def main():
    if GROOVY_PATH.exists():
        patch(GROOVY_PATH, GROOVY_BLOCK)
    elif KOTLIN_PATH.exists():
        patch(KOTLIN_PATH, KOTLIN_BLOCK)
    else:
        print("تحذير: لم يُعثر على android/build.gradle أو android/build.gradle.kts الجذري — تخطي الترقيع.")


if __name__ == "__main__":
    main()
