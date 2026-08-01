#!/usr/bin/env python3
"""
الحل لخطأ:
    MissingPluginException(No implementation found for method
    getDatabasesPath on channel com.tekartik.sqflite)
يظهر فقط في بناء release (وليس debug)، بعد التثبيت والفتح مباشرة.

السبب الجذري (موثّق ومتكرر كثيراً في مجتمع Flutter):
Flutter لا يستدعي تسجيل الإضافات (plugin registration) عبر كود صريح
تكتبه أنت، بل عبر ملف مُولَّد تلقائياً اسمه GeneratedPluginRegistrant،
يُستدعى من محرك Flutter (FlutterEngine) بطريقة غير مباشرة (تشبه
reflection من منظور أداة R8). أداة **R8** (المفعّلة افتراضياً في بناء
release لتصغير حجم APK وتشفير الكود) لا تستطيع دائماً اكتشاف هذا
الاستخدام غير المباشر، فتحذف أجزاءً من كود التسجيل هذا معتبرة إياه "غير
مستخدم" — فتنكسر قنوات الإضافات (مثل sqflite) في نسخة release فقط، بينما
تعمل نسخة debug بشكل طبيعي (لأن R8 لا يعمل في debug).

الحل هنا: تعطيل R8 (minification/shrinking) صراحة لنوع بناء release —
مناسب تماماً لتطبيق مبيعات داخلي لا يحتاج أولوية قصوى لتصغير حجم APK،
ويتجنّب الحاجة لكتابة وصيانة قواعد ProGuard/R8 "keep" لكل إضافة يدوياً
(وهي عرضة لنسيان إضافة جديدة مستقبلاً وتكرار نفس العطل بصمت).

آمن عند التكرار (idempotent).
"""
import re
from pathlib import Path

GROOVY_PATH = Path("android/app/build.gradle")
KOTLIN_PATH = Path("android/app/build.gradle.kts")

MARKER = "__CADY_DISABLE_R8_MINIFY__"


def patch_groovy(text: str) -> str:
    if MARKER in text:
        return text
    # نضيف/نستبدل isMinifyEnabled و shrinkResources داخل كتلة release تحديداً
    def replace_release_block(match: re.Match) -> str:
        block = match.group(0)
        block = re.sub(r"minifyEnabled\s+true", "minifyEnabled false", block)
        block = re.sub(r"shrinkResources\s+true", "shrinkResources false", block)
        if "minifyEnabled" not in block:
            block = block.replace("{", "{\n            minifyEnabled false // " + MARKER, 1)
        if "shrinkResources" not in block:
            block = block.replace("{", "{\n            shrinkResources false // " + MARKER, 1)
        return block

    pattern = re.compile(r"release\s*\{[^}]*\}", re.DOTALL)
    new_text, count = pattern.subn(replace_release_block, text, count=1)
    if count == 0:
        print("تحذير: لم يُعثر على كتلة release داخل build.gradle — تخطي.")
        return text
    return new_text


def patch_kotlin(text: str) -> str:
    if MARKER in text:
        return text

    def replace_release_block(match: re.Match) -> str:
        block = match.group(0)
        block = re.sub(r"isMinifyEnabled\s*=\s*true", "isMinifyEnabled = false", block)
        block = re.sub(r"isShrinkResources\s*=\s*true", "isShrinkResources = false", block)
        if "isMinifyEnabled" not in block:
            block = block.replace("{", "{\n            isMinifyEnabled = false // " + MARKER, 1)
        if "isShrinkResources" not in block:
            block = block.replace("{", "{\n            isShrinkResources = false // " + MARKER, 1)
        return block

    pattern = re.compile(r'getByName\("release"\)\s*\{[^}]*\}', re.DOTALL)
    new_text, count = pattern.subn(replace_release_block, text, count=1)
    if count == 0:
        print("تحذير: لم يُعثر على كتلة getByName(\"release\") داخل build.gradle.kts — تخطي.")
        return text
    return new_text


def main():
    if KOTLIN_PATH.exists():
        text = KOTLIN_PATH.read_text(encoding="utf-8")
        new_text = patch_kotlin(text)
        if new_text != text:
            KOTLIN_PATH.write_text(new_text, encoding="utf-8")
            print(f"تم تعطيل R8 (minifyEnabled/shrinkResources) في {KOTLIN_PATH}")
        else:
            print(f"{KOTLIN_PATH}: لا حاجة للتعديل (تم مسبقاً أو لم يُعثر على الكتلة).")
    elif GROOVY_PATH.exists():
        text = GROOVY_PATH.read_text(encoding="utf-8")
        new_text = patch_groovy(text)
        if new_text != text:
            GROOVY_PATH.write_text(new_text, encoding="utf-8")
            print(f"تم تعطيل R8 (minifyEnabled/shrinkResources) في {GROOVY_PATH}")
        else:
            print(f"{GROOVY_PATH}: لا حاجة للتعديل (تم مسبقاً أو لم يُعثر على الكتلة).")
    else:
        print("تحذير: لم يُعثر على android/app/build.gradle(.kts) — تخطي.")


if __name__ == "__main__":
    main()
