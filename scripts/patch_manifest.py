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


# مطلوب لحزمة url_launcher على أندرويد 11+ (حتى تنجح launchUrl لفتح
# تطبيق الاتصال، واتساب، والخرائط من بطاقة/صفحة العميل) — بدون هذا الوسم
# ترفض أندرويد الوصول لهذه التطبيقات بصمت (PlatformException).
QUERIES_BLOCK = """    <queries>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="geo" />
        </intent>
    </queries>"""


def _ensure_queries(content: str) -> str:
    if "<queries>" in content:
        return content
    if "</application>" in content:
        return content.replace(
            "</application>", "</application>\n\n" + QUERIES_BLOCK, 1)
    # احتياطًا: أدرجها قبل إغلاق <manifest>
    return content.replace("</manifest>", QUERIES_BLOCK + "\n</manifest>", 1)


# يسمح لكادي بالظهور كخيار عند مشاركة ملف مزامنة/نسخة احتياطية من تطبيق
# آخر (واتساب مثلًا)، أو عند فتح ملف .json مباشرة من مدير الملفات — بدل
# اضطرار المستخدم لفتح منتقي الملفات والبحث عن الملف يدويًا (راجع
# ShareIntentBridge.kt وشرحها لتفاصيل الآلية الكاملة، بما فيها الطرف
# الأصلي الذي يقرأ الملف فعليًا).
SHARE_INTENT_FILTER_BLOCK = """
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="application/json" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:mimeType="application/json" />
            </intent-filter>"""

MAIN_ACTIVITY_RE = re.compile(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>')


def _ensure_share_intent_filter(content: str) -> str:
    if "android.intent.action.SEND" in content:
        return content
    m = MAIN_ACTIVITY_RE.search(content)
    if not m:
        print("تحذير: لم يُعثر على وسم <activity> الخاص بـ MainActivity — تخطي فلتر المشاركة.")
        return content
    close_idx = content.find("</activity>", m.end())
    if close_idx == -1:
        print("تحذير: لم يُعثر على </activity> بعد MainActivity — تخطي فلتر المشاركة.")
        return content
    return content[:close_idx] + SHARE_INTENT_FILTER_BLOCK + "\n        " + content[close_idx:]


def main():
    if not MANIFEST_PATH.exists():
        print(f"تحذير: لم يُعثر على {MANIFEST_PATH} — تخطي الترقيع.")
        return

    content = MANIFEST_PATH.read_text(encoding="utf-8")
    original = content

    missing = [p for p in REQUIRED_PERMISSIONS
               if re.search(re.escape(p.split('"')[1]), content) is None]

    if missing:
        block = "\n    " + "\n    ".join(missing)
        # أدرج الصلاحيات الناقصة قبل وسم <application
        if "<application" in content:
            content = content.replace("<application", block + "\n\n    <application", 1)
        else:
            # احتياطًا: أدرجها بعد وسم <manifest ...>
            content = re.sub(r"(<manifest[^>]*>)", r"\1" + block, content, count=1)
        print(f"تمت إضافة {len(missing)} صلاحية جديدة إلى AndroidManifest.xml")
    else:
        print("جميع الصلاحيات المطلوبة موجودة مسبقًا — لا حاجة لإضافتها.")

    content = _ensure_queries(content)
    if "<queries>" not in original:
        print("تمت إضافة وسم <queries> لدعم url_launcher (اتصال/واتساب/خرائط).")

    before_share_filter = content
    content = _ensure_share_intent_filter(content)
    if "android.intent.action.SEND" not in before_share_filter:
        print("تمت إضافة intent-filter لاستقبال ملفات JSON مُشارَكة من تطبيقات أخرى.")

    if content != original:
        MANIFEST_PATH.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    main()
