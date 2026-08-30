#!/usr/bin/env python3
"""يعدّل android:label داخل AndroidManifest.xml المولَّد حديثًا من
'cadysalesapp' (اسم المشروع الافتراضي الذي يضعه flutter create) إلى 'كادي'
— اسم العرض الفعلي للتطبيق. يجب أن يعمل بعد كل توليد لمجلد android (وليس
مرة واحدة فقط) لأن المجلد غير متتبَّع بـ git ويُبنى من الصفر في كل تشغيلة،
تمامًا مثل باقي سكربتات patch_*.py المجاورة له.
"""
import re
import sys
from pathlib import Path

MANIFEST_PATH = Path("android/app/src/main/AndroidManifest.xml")
NEW_LABEL = "كادي"


def main() -> int:
    if not MANIFEST_PATH.exists():
        print(f"✗ لم يُعثر على {MANIFEST_PATH} — هل سبقت هذه الخطوة توليد مجلد android؟")
        return 1

    content = MANIFEST_PATH.read_text(encoding="utf-8")

    if f'android:label="{NEW_LABEL}"' in content:
        print(f"✓ android:label يساوي '{NEW_LABEL}' مسبقًا — لا حاجة لتعديل")
        return 0

    new_content, count = re.subn(
        r'android:label="[^"]*"',
        f'android:label="{NEW_LABEL}"',
        content,
        count=1,
    )

    if count == 0:
        print("✗ لم يُعثر على android:label بالملف إطلاقًا — راجع بنية AndroidManifest.xml يدويًا")
        return 1

    MANIFEST_PATH.write_text(new_content, encoding="utf-8")
    print(f"✓ تم تحديث android:label إلى '{NEW_LABEL}'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
