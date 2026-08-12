#!/usr/bin/env python3
"""
يضيف إعداد توقيع الإصدار (signingConfigs.release) المعتمِد على ملف
key.properties داخل android/app/build.gradle (Groovy) أو
android/app/build.gradle.kts (Kotlin DSL) — أيهما موجودًا فعليًا،
وذلك بشكل آمن وقابل للتكرار (idempotent) دون تكرار الإدراج إن أُعيد التشغيل.

إن لم يوجد android/key.properties (لأن أسرار التوقيع غير متوفرة بعد)
يتم تخطي الترقيع تمامًا ويُبنى APK بتوقيع debug الافتراضي فقط.
"""
from pathlib import Path

GROOVY_PATH = Path("android/app/build.gradle")
KOTLIN_PATH = Path("android/app/build.gradle.kts")
KEY_PROPS_PATH = Path("android/key.properties")

MARKER = "// __CADY_SIGNING_PATCH__"


def patch_groovy(text: str) -> str:
    if MARKER in text:
        return text

    header = f"""{MARKER}
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {{
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}}

"""
    text = header + text

    signing_block = """
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
"""
    # أدرج signingConfigs داخل كتلة android { قبل buildTypes
    if "buildTypes" in text:
        idx = text.index("buildTypes")
        text = text[:idx] + signing_block.strip("\n") + "\n\n    " + text[idx:]

    # اجعل نسخة الإصدار (release) تستخدم توقيع release بدل debug
    text = text.replace(
        "signingConfig signingConfigs.debug",
        "signingConfig signingConfigs.release",
    )
    return text


def patch_kotlin(text: str) -> str:
    if MARKER in text:
        return text

    header = f"""{MARKER}
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {{
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}}

"""
    text = header + text

    signing_block = """
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
"""
    if "buildTypes" in text:
        idx = text.index("buildTypes")
        text = text[:idx] + signing_block.strip("\n") + "\n\n    " + text[idx:]

    text = text.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )
    return text


def main():
    if not KEY_PROPS_PATH.exists():
        print("لا يوجد key.properties بعد — سيُبنى APK بتوقيع debug الافتراضي فقط.")
        return

    if GROOVY_PATH.exists():
        content = GROOVY_PATH.read_text(encoding="utf-8")
        GROOVY_PATH.write_text(patch_groovy(content), encoding="utf-8")
        print(f"تم ترقيع {GROOVY_PATH} لإضافة توقيع الإصدار.")
    elif KOTLIN_PATH.exists():
        content = KOTLIN_PATH.read_text(encoding="utf-8")
        KOTLIN_PATH.write_text(patch_kotlin(content), encoding="utf-8")
        print(f"تم ترقيع {KOTLIN_PATH} لإضافة توقيع الإصدار.")
    else:
        print("تحذير: لم يُعثر على build.gradle أو build.gradle.kts — تخطي الترقيع.")


if __name__ == "__main__":
    main()
