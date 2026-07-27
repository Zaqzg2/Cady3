#!/usr/bin/env python3
"""
يضيف صلاحيات البلوتوث/الموقع اللازمة للطباعة الحرارية إلى
android/app/src/main/AndroidManifest.xml بشكل آمن وقابل للتكرار
(لا يضيف نفس الصلاحية مرتين إن أُعيد تشغيل السكربت).
"""
import re
from pathlib import Path

MANIFEST_PATH = Path("android/app/src/main/AndroidManifest.xml")

REQUIRED_PERMISSIONS = [
    '<uses-permission android:name="android.permission.BLUETOOTH" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
]


def main():
    if not MANIFEST_PATH.exists():
        print(f"تحذير: لم يُعثر على {MANIFEST_PATH} — تخطي الترقيع.")
        return

    content = MANIFEST_PATH.read_text(encoding="utf-8")

    missing = [p for p in REQUIRED_PERMISSIONS
               if re.search(re.escape(p.split('"')[1]), content) is None]

    if not missing:
        print("جميع الصلاحيات المطلوبة موجودة مسبقًا — لا حاجة للتعديل.")
        return

    block = "\n    " + "\n    ".join(missing)
    # أدرج الصلاحيات الناقصة قبل وسم <application
    if "<application" in content:
        content = content.replace("<application", block + "\n\n    <application", 1)
    else:
        # احتياطًا: أدرجها بعد وسم <manifest ...>
        content = re.sub(r"(<manifest[^>]*>)", r"\1" + block, content, count=1)

    MANIFEST_PATH.write_text(content, encoding="utf-8")
    print(f"تمت إضافة {len(missing)} صلاحية جديدة إلى AndroidManifest.xml")


if __name__ == "__main__":
    main()
