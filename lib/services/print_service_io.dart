import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';

import 'native_bt_bridge.dart';
import 'printer_device.dart';

/// خدمة الطباعة الحرارية 80مم عبر البلوتوث مباشرة (بدون تطبيقات وسيطة) —
/// النسخة الحقيقية لأندرويد/iOS/سطح المكتب. لا تُستخدم هذه النسخة إطلاقًا
/// على الويب (راجع print_service_web.dart وprint_service.dart).
///
/// طبقة الاتصال الفعلية الآن NativeBtBridge (Kotlin أصلي، راجع
/// android/app/src/main/kotlin/.../BluetoothPrinterBridge.kt) بدل مكتبة
/// print_bluetooth_thermal الخارجية — تبيّن أن تلك المكتبة تفشل بالكتابة
/// على أجهزة معيّنة رغم نجاح الاتصال الظاهري في كل مرة (سجلات lastAttemptLog
/// أثبتت هذا بشكل قاطع: connect() ينجح دائمًا، writeBytes() يفشل فورًا)،
/// بينما نفس الجهاز ونفس الطابعة يعملان بلا مشاكل عبر تطبيقات أخرى. الطبقة
/// الأصلية الجديدة تستخدم فقط android.bluetooth القياسية، مع مقبس احتياطي
/// على القناة الخام (راجع تعليق BluetoothPrinterBridge.kt للتفاصيل).
///
/// السبب في طباعة "صورة" بدل نص ESC/POS مباشر: الطابعات الحرارية
/// تعتمد على صفحات ترميز (codepages) لا تدعم تشكيل الحروف العربية بشكل
/// صحيح. لذلك نحوّل نفس PDF المُنتَج فعليًا (نفس تصميم 80مم) إلى صورة
/// نقطية (raster) ثم نرسلها بأوامر ESC/POS كصورة — فتخرج مطابقة تمامًا
/// لما يظهر في PDF، بما في ذلك النصوص العربية والشعار والتوقيع.
///
/// طبقات حماية ضد فشل الاتصال/الطباعة "الصامت" (راجع lastAttemptLog
/// لتشخيص أي حالة فعلية على أي جهاز):
/// 1) صلاحيات بلوتوث أندرويد 12+ تُطلَب صراحة قبل أي عملية (_ensurePermissions).
/// 2) الكتابة الفعلية مجزّأة على دفعات صغيرة (_writeChunked) بدل دفعة واحدة
///    ضخمة، لأن صورة فاتورة كاملة قد تتجاوز عشرات الكيلوبايتات، وإرسالها
///    دفعة واحدة عبر Bluetooth Classic SPP يُفيض مخزن الطابعة المؤقت
///    المحدود على كثير من الطابعات الرخيصة فتفشل الكتابة أو تتوقف منتصف
///    الإرسال.
/// 3) تحقّق حقيقي من الاتصال (_writeVerified) بدل الاكتفاء بحالة الاتصال
///    وحدها: نكتب فعليًا، وإن فشلت الكتابة رغم "الاتصال"، نفرض إعادة اتصال
///    كاملة (فصل ثم اتصال) ونعيد الكتابة مرة أخيرة قبل اعتبارها فشلت فعلًا.
/// 4) عند فشل كل ما سبق: printViaSystemDialog يفوّض الطباعة الفعلية لأي
///    خدمة طباعة مُثبَّتة بالنظام (مثل RawBT)، مسار مستقل تمامًا عن كل ما
///    سبق ومُثبَت أنه يعمل على هذا الجهاز.
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  /// سجل خطوة-بخطوة (مع التوقيت بالمللي ثانية) لآخر محاولة طباعة أو تحقق
  /// اتصال. يُعرض للمستخدم عبر زر "التفاصيل" في رسالة الفشل (راجع
  /// showPrintDiagnosticsDialog في print_service.dart) بدل رسالة عامة واحدة
  /// لا تكفي لتحديد أين تحديدًا يفشل الاتصال على جهاز بعينه.
  final List<String> lastAttemptLog = [];
  String? lastError;
  DateTime? _attemptStart;

  void _resetLog() {
    lastAttemptLog.clear();
    lastError = null;
    _attemptStart = DateTime.now();
  }

  void _log(String msg) {
    final ms = _attemptStart == null
        ? 0
        : DateTime.now().difference(_attemptStart!).inMilliseconds;
    lastAttemptLog.add('+${ms}ms  $msg');
  }

  /// يطلب صلاحيات البلوتوث اللازمة على أندرويد 12+ (BLUETOOTH_CONNECT/SCAN)
  /// ويُسجّل النتيجة تشخيصيًا. لا يمنع المحاولة التالية حتى لو بدت الصلاحية
  /// مرفوضة (بعض قراءات الصلاحية غير دقيقة على أجهزة/إصدارات أقدم) — لكنه
  /// يجعل السبب الحقيقي ظاهرًا في السجل إن كانت هذه هي المشكلة فعلًا.
  ///
  /// ملاحظة لازمة خارج هذا الملف: التصريح بالصلاحية داخل
  /// android/app/src/main/AndroidManifest.xml شرط إضافي لازم — طلبها من
  /// الكود وحده لا يكفي إطلاقًا إن لم تكن مُعلنة هناك:
  ///   <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
  ///       android:usesPermissionFlags="neverForLocation" />
  ///   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  ///   <uses-permission android:name="android.permission.BLUETOOTH"
  ///       android:maxSdkVersion="30" />
  ///   <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
  ///       android:maxSdkVersion="30" />
  Future<void> _ensurePermissions() async {
    try {
      final already = await Permission.bluetoothConnect.status;
      if (already.isGranted) {
        _log('صلاحية البلوتوث: ممنوحة ✓');
        return;
      }
      _log('صلاحية البلوتوث: غير ممنوحة — يُطلب الآن من النظام...');
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      final granted2 = (statuses[Permission.bluetoothConnect]?.isGranted ?? true) &&
          (statuses[Permission.bluetoothScan]?.isGranted ?? true);
      _log('نتيجة طلب الصلاحية: '
          '${statuses.entries.map((e) => '${e.key}=${e.value}').join('، ')}'
          ' ⇒ ${granted2 ? "ممنوحة الآن" : "لا تزال مرفوضة — تحقق من إعدادات النظام > التطبيقات > كادي > الصلاحيات"}');
    } catch (e) {
      _log('⚠️ تعذّر التحقق من صلاحية البلوتوث (قد يكون الجهاز أقدم من أندرويد 12): $e');
    }
  }

  Future<List<PrinterDevice>> getPairedDevices() async {
    await _ensurePermissions();
    return NativeBtBridge.instance.pairedDevices();
  }

  Future<bool> connect(String macAddress) async {
    return NativeBtBridge.instance.connect(macAddress);
  }

  Future<bool> get isConnected => NativeBtBridge.instance.isConnected();

  Future<void> disconnect() => NativeBtBridge.instance.disconnect();

  /// يكتب [bytes] على دفعات صغيرة بدل دفعة واحدة ضخمة (راجع الشرح أعلى
  /// الملف، البند 2). مهلة قصيرة بين كل دفعة والتالية تعطي الطابعة وقتًا
  /// لتفريغ مخزنها المؤقت قبل استقبال المزيد.
  Future<bool> _writeChunked(Uint8List bytes) async {
    const chunkSize = 1024;
    if (bytes.length <= chunkSize) {
      final ok = await NativeBtBridge.instance.writeBytes(bytes);
      _log('كتابة ${bytes.length} بايت (دفعة واحدة): ${ok ? "نجحت" : "فشلت"}');
      return ok;
    }
    var offset = 0;
    var chunkIndex = 0;
    final totalChunks = (bytes.length / chunkSize).ceil();
    while (offset < bytes.length) {
      final end =
          (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
      final chunk = bytes.sublist(offset, end);
      chunkIndex++;
      bool ok;
      try {
        ok = await NativeBtBridge.instance.writeBytes(chunk);
      } catch (e) {
        _log('❌ استثناء أثناء كتابة الدفعة $chunkIndex/$totalChunks: $e');
        return false;
      }
      if (!ok) {
        _log('❌ فشلت كتابة الدفعة $chunkIndex/$totalChunks عند البايت $offset');
        return false;
      }
      offset = end;
      await Future.delayed(const Duration(milliseconds: 12));
    }
    _log('كتابة ${bytes.length} بايت على $totalChunks دفعة: نجحت جميعها ✓');
    return true;
  }

  /// إرسال [bytes] فعليًا مع تحقّق حقيقي من الاتصال ومعالجة كاملة
  /// للاستثناءات (راجع الشرح أعلى الملف، البند 3). يُسجّل كل خطوة في
  /// lastAttemptLog بدل أن ينهار الاستدعاء بصمت أو يُعيد فقط true/false بلا
  /// تفسير.
  Future<bool> _writeVerified(Uint8List bytes, String? printerMac) async {
    try {
      await _ensurePermissions();

      var connected = await isConnected;
      _log('isConnected قبل المحاولة: $connected');
      if (!connected && printerMac != null && printerMac.isNotEmpty) {
        _log('محاولة اتصال بـ $printerMac...');
        connected = await connect(printerMac);
        _log('نتيجة connect(): $connected');
        if (connected) {
          // مهلة استقرار قصيرة بعد اتصال جديد مباشرة — بعض الطابعات
          // الرخيصة تحتاج جزءًا من الثانية قبل أن تصبح جاهزة فعليًا لاستقبال
          // بيانات رغم أن المصافحة الأولية اكتملت. إضافتها لا تضر شيئًا في
          // أسوأ الأحوال.
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      if (!connected) {
        _log('❌ فشل نهائي: لا يوجد اتصال حي، ولا عنوان طابعة محفوظ لإعادة المحاولة');
        lastError = 'لا يوجد اتصال بالطابعة';
        return false;
      }

      var ok = await _writeChunked(bytes);
      if (!ok && printerMac != null && printerMac.isNotEmpty) {
        _log('الكتابة فشلت رغم أن الحالة كانت "متصلة" — هذا يعني أن المقبس '
            'كان ميتًا بصمت. إعادة اتصال كاملة كمحاولة أخيرة...');
        try {
          await NativeBtBridge.instance.disconnect();
        } catch (e) {
          _log('⚠️ استثناء أثناء disconnect(): $e');
        }
        final reconnected = await connect(printerMac);
        _log('نتيجة إعادة الاتصال: $reconnected');
        if (reconnected) {
          await Future.delayed(const Duration(milliseconds: 300));
          ok = await _writeChunked(bytes);
        }
      }
      if (!ok) lastError = 'فشلت الكتابة على المقبس رغم محاولات إعادة الاتصال';
      _log(ok ? '✅ نجحت الكتابة النهائية' : '❌ فشلت الكتابة نهائيًا');
      return ok;
    } catch (e) {
      _log('❌ استثناء غير متوقع لم تتم معالجته: $e');
      lastError = e.toString();
      return false;
    }
  }

  /// أمر تهيئة ESC/POS صامت (ESC @) — لا يطبع شيئًا ولا يغذّي ورقًا مرئيًا،
  /// يُستخدم فقط للتحقق أن الكتابة الفعلية على المقبس تنجح.
  static final Uint8List _pingBytes = Uint8List.fromList(const [0x1B, 0x40]);

  /// يحوّل صورة [image] (حزمة image v4.x، RGBA) إلى بيانات أمر ESC/POS
  /// GS v 0 (طباعة نقطية خام) كاملة، بعتبة تحويل رمادي←أسود ثابتة (بلا
  /// تنقيط/dithering) — بدل استخدام Generator.imageRaster من حزمة
  /// esc_pos_utils_plus (راجع الشرح أعلى الملف لسبب استبدالها أصلاً).
  ///
  /// لماذا عتبة بسيطة لا تنقيط Floyd–Steinberg (كما كان بإصدار سابق من هذا
  /// الملف): التنقيط ممتاز لصور فوتوغرافية بتدرّجات لونية، لكنه يجعل النص
  /// يبدو باهتًا على طابعة حرارية منخفضة الدقة نسبيًا (203dpi) — لأن حواف
  /// الحروف المُنعَّمة (anti-aliasing) تحتوي بكسلات رمادية كثيرة، والتنقيط
  /// يحوّل نصفها تقريبًا لأبيض بدل أسود لمحاكاة اللون الرمادي "بصريًا"، وهذا
  /// بالضبط ما لاحظه المستخدم: نص باهت مقابل توقيع (صورة ثنائية أصلاً بلا
  /// رمادي يُذكر) طبع بلون قوي واضح. عتبة ثابتة تُلزم كل بكسل غامق نسبيًا
  /// بالأسود الصرف فتخرج الحروف أعرض وأغمق وأوضح — وهذا هو المطلوب فعليًا
  /// لمستند نصي/جدولي كالفاتورة، لا لصورة.
  ///
  /// [threshold] بين 0-255: كل بكسل إضاءته (luminance) أقل من أو تساوي هذه
  /// القيمة يُطبع أسود، وإلا أبيض. أعلى من المنتصف الرياضي 127 عمدًا (القيمة
  /// الافتراضية بالإعدادات 175) لتعويض بكسلات تنعيم الحواف الرمادية الفاتحة
  /// نسبيًا التي يجب أن تُطبع أسود حتى يبدو النص كثيفًا لا باهتًا. قابل
  /// للتعديل من شاشة إعدادات الطباعة (company_settings.dart: printBlackThreshold).
  Uint8List _buildRasterCommand(img.Image image, {required int threshold}) {
    final width = image.width;
    final height = image.height;
    final rowBytes = (width + 7) >> 3;
    final packed = Uint8List(rowBytes * height);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final px = image.getPixel(x, y);
        // إضاءة قياسية (luminance) — نفس المعامل العالمي لتحويل RGB لرمادي
        final gray = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
        if (gray <= threshold) {
          packed[y * rowBytes + (x >> 3)] |= (0x80 >> (x & 7));
        }
      }
    }

    // رأس أمر GS v 0: 1D 76 30 m xL xH yL yH ثم بيانات الصورة (m=0 عادي،
    // xL/xH عرض السطر بالبايت، yL/yH الارتفاع بالبكسل، كلاهما little-endian)
    final header = <int>[
      0x1D, 0x76, 0x30, 0x00,
      rowBytes & 0xFF, (rowBytes >> 8) & 0xFF,
      height & 0xFF, (height >> 8) & 0xFF,
    ];
    return Uint8List.fromList([...header, ...packed]);
  }

  /// تحقّق حقيقي من الاتصال بالطابعة عبر كتابة فعلية صغيرة، وليس
  /// connectionStatus وحدها. تستخدمها شاشة الإعدادات لعرض حالة "متصلة"
  /// تعكس فعلًا ما سيحدث عند الطباعة الحقيقية، بدل شارة متفائلة قد تكون
  /// كاذبة (هذا بالضبط ما كان يُنتج "متصلة" بالإعدادات مع فشل الطباعة).
  Future<bool> verifyConnection(String? printerMac) async {
    _resetLog();
    _log('— بدء تحقق اتصال حقيقي —');
    return _writeVerified(_pingBytes, printerMac);
  }

  /// يحوّل أول صفحة من ملف PDF (المُصمَّم أصلاً بعرض 80مم) إلى صورة، ثم
  /// يطبعها عبر البلوتوث على طابعة 80مم حرارية متصلة مسبقًا، مع كل طبقات
  /// الحماية الثلاث الموثّقة أعلى الملف.
  Future<bool> printPdfBytes(Uint8List pdfBytes,
      {String? printerMac, int blackThreshold = 175}) async {
    _resetLog();
    _log('— بدء طباعة (PDF: ${pdfBytes.length} بايت) —');

    // عرض 80مم عند 203 نقطة/إنش (الدقة القياسية لأغلب طابعات الإيصالات)
    // 80mm ≈ 3.15in => العرض بالبكسل ≈ 576
    const targetWidthPx = 576;

    img.Image? finalImage;
    try {
      await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
        final pngBytes = await page.toPng();
        final decoded = img.decodePng(pngBytes);
        if (decoded == null) continue;
        // نُسطّح الصورة على خلفية بيضاء صريحة قبل أي تصغير أو تنقيط — دفاعًا
        // عن أي احتمال أن مساحات الصفحة "الفارغة" تخرج من محوّل PDF←→صورة
        // بقناة شفافية (alpha=0) بدل أبيض صريح. صورة شفافة تُقرأ لاحقًا فقط
        // عبر قنوات r/g/b (بدون a) قد تُفسَّر خطأً كسواد، فتسطيحها هنا يمنع
        // هذا الاحتمال نهائيًا بغض النظر عمّا يفعله المحوّل فعليًا.
        final flattened = img.Image(
          width: decoded.width,
          height: decoded.height,
          numChannels: 4,
        );
        img.fill(flattened, color: img.ColorRgba8(255, 255, 255, 255));
        img.compositeImage(flattened, decoded, blend: img.BlendMode.alpha);
        finalImage = img.copyResize(
          flattened,
          width: targetWidthPx,
          interpolation: img.Interpolation.average,
        );
        break; // فاتورة/سند عادة صفحة واحدة (roll80)
      }
    } catch (e) {
      _log('❌ فشل تحويل PDF إلى صورة: $e');
      lastError = 'فشل تحويل الفاتورة إلى صورة قابلة للطباعة';
      return false;
    }

    if (finalImage == null) {
      _log('❌ فشل تحويل PDF إلى صورة (نتيجة فارغة بلا استثناء)');
      lastError = 'فشل تحويل الفاتورة إلى صورة قابلة للطباعة';
      return false;
    }
    _log('تم تحويل PDF إلى صورة ${finalImage.width}×${finalImage.height}');

    late final Uint8List payload;
    try {
      final raster = _buildRasterCommand(finalImage, threshold: blackThreshold);
      payload = Uint8List.fromList([
        0x1B, 0x40, // ESC @  — تهيئة
        ...raster, // GS v 0 — بيانات الصورة النقطية
        0x1B, 0x64, 0x02, // ESC d 2 — تغذية سطرين
        0x1D, 0x56, 0x01, // GS V 1  — قص جزئي (يُتجاهل بأمان إن لم تدعمه الطابعة)
      ]);
      _log('حجم أوامر ESC/POS النهائية: ${payload.length} بايت');
    } catch (e) {
      _log('❌ فشل بناء أوامر ESC/POS: $e');
      lastError = 'فشل تجهيز بيانات الطباعة';
      return false;
    }

    return _writeVerified(payload, printerMac);
  }

  /// يطبع عبر مربع حوار نظام التشغيل القياسي (Android/iOS) بدل الاتصال
  /// المباشر بمكتبة print_bluetooth_thermal. يظهر فيه أي خدمة طباعة
  /// مُثبَّتة ومُفعَّلة على الجهاز (مثل RawBT) كخيار "طابعة" — النظام نفسه
  /// يتولى الاتصال بالطابعة عندها، لا كود التطبيق ولا هذه المكتبة إطلاقًا.
  ///
  /// هذا مسار بديل مُثبَت عمليًا: عند فشل الاتصال المباشر رغم كل محاولات
  /// الإصلاح (صلاحيات، تجزئة الكتابة، إعادة اتصال، مهلة استقرار)، تبيّن أن
  /// نفس الهاتف ونفس الطابعة يطبعان بلا أي مشكلة عبر تطبيق RawBT — أي أن
  /// العطل داخل مكتبة print_bluetooth_thermal نفسها وليس بجهاز المستخدم أو
  /// بمنطق التطبيق. تفويض الاتصال الفعلي لتطبيق مُثبَت يعمل فعلاً هو الحل
  /// العملي الأضمن بدل الاستمرار بمحاولة إصلاح مكتبة لا نملك مصدرها.
  Future<bool> printViaSystemDialog(Uint8List pdfBytes) async {
    _resetLog();
    _log('— طباعة عبر مربع حوار نظام التشغيل —');
    try {
      final ok = await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
      _log(ok ? '✅ تم تسليم المستند لخدمة الطباعة' : '❌ ألغى المستخدم الحوار أو فشلت الخدمة');
      return ok;
    } catch (e) {
      _log('❌ استثناء أثناء فتح حوار الطباعة: $e');
      lastError = e.toString();
      return false;
    }
  }
}
