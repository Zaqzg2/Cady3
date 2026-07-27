# تطبيق كادي للمنظفات — مندوب المبيعات (Flutter)

تطبيق Flutter كامل (Mobile First) لمندوب مبيعات "كادي للمنظفات"، بالريال اليمني،
يحتوي على: الشاشة الرئيسية (عميل نقدي / فاتورة مرتجع / فاتورة بيع / سند قبض)،
إدارة العملاء وكشوف الحساب، إدارة المنتجات، التقارير، الإعدادات، توليد PDF
حقيقي بعرض 80مم، والطباعة الحرارية عبر بلوتوث.

## الخطوات المطلوبة عندك (لأنه لا توجد بيئة Flutter الآن)

هذا المجلد يحتوي فقط على كود Dart + pubspec.yaml (لا يحتوي على مجلدات
android/ios لأن إنشاءها يتطلب تشغيل أداة flutter فعليًا). عندما يتوفر لديك
جهاز فيه Flutter SDK (ويفضّل ليس عبر Termux لنفس مشكلة lightningcss/الترجمة
الأصلية التي واجهتها سابقًا مع مشروع React — استخدم كمبيوتر عادي أو
GitHub Codemagic/Codespaces إن أمكن):

```bash
# 1) أنشئ مشروع فلاتر فارغ بنفس الاسم في مجلد جديد
flutter create cady_sales_app_host
cd cady_sales_app_host

# 2) احذف lib/ الافتراضي وانسخ محتويات هذا المجلد فوقه
rm -rf lib
cp -r /path/to/cady_sales_app/lib .
cp /path/to/cady_sales_app/pubspec.yaml .
cp -r /path/to/cady_sales_app/assets . 2>/dev/null || true

# 3) نزّل الحزم
flutter pub get

# 4) شغّل التطبيق
flutter run
```

## صلاحيات أندرويد المطلوبة (مهم جدًا للطباعة عبر بلوتوث)

أضف هذه الصلاحيات داخل `android/app/src/main/AndroidManifest.xml` قبل وسم
`<application>`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

كذلك تأكد أن `minSdkVersion` داخل `android/app/build.gradle` لا يقل عن 21
(الأفضل 23+ لتوافق أفضل مع مكتبات البلوتوث الحديثة).

## دعم اللغة العربية داخل ملفات PDF (مهم)

مكتبة `pdf` لا تدعم رسم الحروف العربية افتراضيًا. يجب إضافة خط عربي (مثل
Noto Naskh Arabic) كالتالي:

1. نزّل الخط (مثلاً من Google Fonts: Noto Naskh Arabic) بصيغة `.ttf`.
2. ضع الملفين هنا:
   - `assets/fonts/NotoNaskhArabic-Regular.ttf`
   - `assets/fonts/NotoNaskhArabic-Bold.ttf`
3. أضف في `pubspec.yaml` تحت `flutter:`:

```yaml
  fonts:
    - family: NotoNaskhArabic
      fonts:
        - asset: assets/fonts/NotoNaskhArabic-Regular.ttf
        - asset: assets/fonts/NotoNaskhArabic-Bold.ttf
          weight: 700
```

الكود في `lib/services/pdf_service.dart` يحاول تحميل هذين الملفين تلقائيًا
عبر `rootBundle.load(...)`؛ إن لم تجدهما فسيستمر التطبيق بالعمل لكن الحروف
العربية داخل ملف الـPDF قد تظهر بشكل غير صحيح إلى أن تضيف الخط.

## ملاحظات حول مكتبة الطباعة الحرارية

تم استخدام `print_bluetooth_thermal` + `esc_pos_utils_plus`. لأن الطابعات
الحرارية عبر ESC/POS لا تدعم تشكيل الحروف العربية بشكل موثوق، الكود يحوّل
نفس ملف الـPDF (المصمم أصلاً بعرض 80مm) إلى صورة (raster) عبر حزمة
`printing` ثم يرسلها كصورة للطابعة — فتخرج الطباعة مطابقة تمامًا لِـPDF بما
في ذلك الشعار والتوقيع والنص العربي.

قبل استخدام الطباعة يجب:
1. إقران الطابعة الحرارية من إعدادات بلوتوث النظام في الهاتف أولًا.
2. فتح شاشة الإعدادات داخل التطبيق واختيار الطابعة من قائمة "الأجهزة المقترنة".

أسماء بعض الدوال في حزمة `print_bluetooth_thermal` قد تختلف قليلًا بين
الإصدارات (مثل تهجئة `macAdress`)، تأكد من مطابقتها لإصدار الحزمة الذي
سيتم تثبيته فعليًا عبر `flutter pub get` وعدّل عند الحاجة حسب رسائل الخطأ.

## ميزات إضافية: الحماية بكلمة مرور والنسخ الاحتياطي

- **قفل التطبيق بكلمة مرور**: من الإعدادات ← "حماية التطبيق بكلمة مرور" فعّل
  كلمة مرور (تُخزَّن مشفّرة SHA-256 محليًا فقط). عند التفعيل تظهر شاشة قفل
  (لوحة أرقام كبيرة) في كل مرة يُفتح فيها التطبيق.
- **نسخ احتياطي / استيراد**: من الإعدادات ← "النسخ الاحتياطي":
  - "تصدير نسخة احتياطية" يُنشئ ملف JSON واحد يحتوي كل العملاء والمنتجات
    والفواتير والسندات والإعدادات، ثم يفتح واجهة المشاركة (يمكن حفظه في
    Google Drive أو إرساله عبر واتساب/بريد للاحتفاظ به أو نقله لجهاز آخر).
  - "استيراد نسخة" يفتح منتقي ملفات لاختيار ملف JSON سابق، ويدمج بياناته مع
    البيانات الحالية (دمج بالمعرّف، لا يحذف شيئًا موجودًا).

## اعتماديات إضافية أُضيفت لهذه الميزات

- `crypto` لتشفير كلمة المرور (SHA-256) قبل تخزينها.
- `file_picker` لاختيار ملف النسخة الاحتياطية عند الاستيراد.

## الرفع على GitHub وبناء APK تلقائيًا (GitHub Actions)

المشروع يحتوي الآن كل ما يلزم لهذا:

```
.github/workflows/build-apk.yml        # يبني APK فقط عند كل push لفرع main
.github/workflows/generate-keystore.yml # يولّد كيستور توقيع مرة واحدة في السحابة
scripts/patch_manifest.py               # يضيف صلاحيات البلوتوث تلقائيًا
scripts/patch_build_gradle.py           # يفعّل توقيع الإصدار (release) تلقائيًا
.gitignore                              # يستثني الكيستور وملفات البناء المحلية
key.properties.example                  # نموذج للاستخدام المحلي فقط
```

### 1) ارفع المشروع على GitHub

```bash
cd cady_sales_app
git init
git add .
git commit -m "الإصدار الأول من تطبيق كادي للمنظفات"
git branch -M main
git remote add origin https://github.com/USERNAME/REPO.git
git push -u origin main
```

### 2) ولّد كيستور التوقيع في السحابة (مرة واحدة فقط)

1. من تبويب **Actions** في مستودع GitHub، شغّل يدويًا workflow باسم
   **"توليد كيستور (Keystore) للتوقيع - مرة واحدة فقط"**.
2. بعد انتهائه، افتح الـ Artifact الناتج (`android-keystore-and-secrets`)
   ونزّله — سيختفي تلقائيًا بعد يوم واحد فقط (`retention-days: 1`) لذا
   نزّله فورًا.
3. داخل الملف المضغوط ستجد `SECRETS_TO_ADD.txt` فيه 4 قيم جاهزة.
4. احتفظ بنسخة من ملف `android_keystore.jks` في مكان آمن جدًا خارج
   GitHub (فقدانه يعني عدم القدرة على تحديث التطبيق بنفس التوقيع لاحقًا).

### 3) أضف الأسرار (Secrets) في إعدادات المستودع

من **Settings → Secrets and variables → Actions → New repository secret**
أضف 4 أسرار بهذه الأسماء بالضبط:

| اسم السر                     | القيمة                                              |
|-------------------------------|------------------------------------------------------|
| `ANDROID_KEYSTORE_BASE64`     | محتوى ملف `android_keystore_base64.txt` كاملاً       |
| `ANDROID_KEYSTORE_PASSWORD`   | من `SECRETS_TO_ADD.txt`                               |
| `ANDROID_KEY_ALIAS`           | من `SECRETS_TO_ADD.txt`                               |
| `ANDROID_KEY_PASSWORD`        | من `SECRETS_TO_ADD.txt`                               |

### 4) شغّل بناء الـ APK

أي `push` جديد لفرع `main` يُشغّل workflow **"بناء APK"** تلقائيًا،
أو شغّله يدويًا من تبويب Actions. في نهاية التشغيل ستجد ملف APK جاهزًا
للتنزيل من قسم **Artifacts** أسفل صفحة التشغيل:

- `cady-sales-app-apk` → لتثبيت التطبيق مباشرة على الهاتف

(بناء AAB لرفعه على Google Play أُزيل مؤقتًا حسب الطلب؛ يمكن إعادته لاحقًا
بإضافة خطوة `flutter build appbundle --release` من جديد في الـ workflow
عند الحاجة لرفع التطبيق على المتجر.)

### ملاحظة تقنية مهمة (لتفادي مشاكل شائعة)

- في أول تشغيل، الـ workflow يولّد مجلد `android/` تلقائيًا عبر
  `flutter create` (لأن المستودع يحتوي كود Dart فقط حاليًا). إذا رغبت
  لاحقًا بتخصيص أيقونة التطبيق أو أي إعداد Android يدويًا، اسحب مجلد
  `android/` الناتج من تشغيل ناجح (أو ولّده محليًا بنفس الأمر) وارفعه
  إلى المستودع — عندها سيتوقف الـ workflow عن إعادة توليده تلقائيًا
  ويستخدم نسختك المخصّصة كما هي في كل مرة.
- سكربتا الترقيع (`patch_manifest.py` و`patch_build_gradle.py`) مصمَّمان
  ليكونا **آمنين عند التكرار (idempotent)** — لا يكرران نفس التعديل إذا
  شُغِّلا أكثر من مرة على نفس الملفات، لتفادي نفس مشاكل هشاشة ترقيع
  الملفات التي قد تكون واجهتها في مشاريع سابقة.

### ملاحظة توافق: إصدار Flutter/Gradle

بعد تحديث `share_plus` إلى الإصدار 12 (لحل تعارض إصدارات مع حزمة
`printing`)، صارت الحزمة تتطلب Android Gradle Plugin ≥ 8.12.1 وGradle
Wrapper ≥ 8.13 وKotlin ≥ 2.2.0. عند استخدام قناة Flutter stable الحديثة
(كما في GitHub Actions عبر `subosito/flutter-action` بدون تحديد إصدار)
فهذا متوفر افتراضيًا. إن بنيت المشروع محليًا بإصدار Flutter/Android Studio
قديم وظهرت أخطاء Gradle، حدّث Flutter وAndroid Studio لأحدث إصدار مستقر.

## هيكل المشروع


```
lib/
  models/         # العميل، المنتج، الفاتورة، السند، الإعدادات، كشف الحساب
  services/       # قاعدة البيانات SQLite، الترقيم، الإعدادات، PDF، الطباعة،
                  # كلمة المرور (auth_service)، النسخ الاحتياطي (backup_service)
  providers/      # AppProvider — الحالة المركزية للتطبيق
  theme/          # الوضع الفاتح/الليلي
  widgets/        # البطاقة الكبيرة، محدد الكمية، لوحة التوقيع
  screens/        # كل شاشات التطبيق (بما فيها lock_screen.dart لقفل التطبيق)
  utils/          # تنسيق العملة (ريال يمني) والتاريخ
  main.dart       # نقطة الدخول + التحقق من كلمة المرور + شريط التنقل السفلي
```

## قاعدة استمرار ترقيم المستندات

عند تعديل رقم فاتورة أو سند يدويًا، النظام (`numbering_service.dart`) يحفظ
دائمًا "أعلى رقم استُخدم"، بحيث يقترح دومًا (أعلى رقم + 1) للمستند التالي —
ولا يعود أبدًا إلى التسلسل القديم حتى لو كان الرقم الجديد المُدخَل أصغر أو
أكبر من المتسلسل الطبيعي.
