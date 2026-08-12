#!/usr/bin/env python3
"""
يضيف إعدادات Google Services (Firebase) إلى ملفات Gradle بعد
توليد مجلد android/ عبر flutter create.

يعمل بشكل آمن وقابل للتكرار (idempotent).
"""
from pathlib import Path
import re

ROOT = Path("android")

# ------------------------------------------------------------------
# 1) settings.gradle / settings.gradle.kts  — pluginManagement
# ------------------------------------------------------------------
SETTINGS_CANDIDATES = [
    ROOT / "settings.gradle",
    ROOT / "settings.gradle.kts",
]

GOOGLE_SERVICES_PLUGIN = 'id "com.google.gms.google-services" version "4.4.2" apply false'

def patch_settings():
    for path in SETTINGS_CANDIDATES:
        if not path.exists():
            continue
        content = path.read_text(encoding="utf-8")
        if "com.google.gms.google-services" in content:
            print(f"[settings] Google Services موجود مسبقاً في {path.name}")
            return

        # أضف داخل كتلة plugins { ... }
        if "plugins {" in content:
            content = content.replace(
                "plugins {",
                "plugins {\n    " + GOOGLE_SERVICES_PLUGIN,
                1,
            )
            path.write_text(content, encoding="utf-8")
            print(f"[settings] أُضيف Google Services plugin إلى {path.name}")
            return

        print(f"[settings] تحذير: لم يُعثر على كتلة plugins في {path.name}")

# ------------------------------------------------------------------
# 2) app/build.gradle / app/build.gradle.kts
# ------------------------------------------------------------------
APP_BUILD_CANDIDATES = [
    ROOT / "app" / "build.gradle",
    ROOT / "app" / "build.gradle.kts",
]

APPLY_PLUGIN_GROOVY = 'apply plugin: \'com.google.gms.google-services\''
APPLY_PLUGIN_KTS = 'id("com.google.gms.google-services")'

def patch_app_build():
    for path in APP_BUILD_CANDIDATES:
        if not path.exists():
            continue
        content = path.read_text(encoding="utf-8")
        if "com.google.gms.google-services" in content:
            print(f"[app] Google Services موجود مسبقاً في {path.name}")
            return

        is_kts = path.suffix == ".kts"

        if is_kts:
            # أضف داخل plugins { }
            if "plugins {" in content:
                content = content.replace(
                    "plugins {",
                    'plugins {\n    id("com.google.gms.google-services")',
                    1,
                )
            else:
                content = 'plugins {\n    id("com.google.gms.google-services")\n}\n\n' + content
        else:
            # Groovy: أضف في نهاية الملف
            content = content.rstrip() + "\n\n" + APPLY_PLUGIN_GROOVY + "\n"

        path.write_text(content, encoding="utf-8")
        print(f"[app] أُضيف Google Services plugin إلى {path.name}")
        return

# ------------------------------------------------------------------
# 3) التأكد من وجود google-services.json
# ------------------------------------------------------------------
def check_json():
    json_path = ROOT / "app" / "google-services.json"
    if json_path.exists():
        text = json_path.read_text(encoding="utf-8")
        if "YOUR_PROJECT_ID" in text:
            print("[json] ⚠️  google-services.json موجود لكنه PLACEHOLDER — "
                  "استبدله بالملف الحقيقي من Firebase Console أو شغّل flutterfire configure")
        else:
            print("[json] google-services.json يبدو مهيأً بالقيم الحقيقية")
    else:
        print("[json] ⚠️  لا يوجد google-services.json — "
              "انسخه من Firebase Console إلى android/app/")

def main():
    if not ROOT.exists():
        print("تحذير: مجلد android/ غير موجود — تخطي ترقيع Firebase.")
        return
    patch_settings()
    patch_app_build()
    check_json()
    print("\n✅ ترقيع Firebase Gradle اكتمل.")
    print("   الخطوة التالية: شغّل  flutterfire configure  (أو ضع الملفات يدوياً)")

if __name__ == "__main__":
    main()
