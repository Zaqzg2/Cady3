/// واجهة موحّدة للطباعة تختار تلقائيًا التنفيذ المناسب حسب المنصة وقت
/// الترجمة (compile time) — بدون أي فرع كود يدوي في باقي التطبيق:
/// - على أندرويد/iOS/سطح المكتب (dart:io متاحة): طباعة حرارية بلوتوث حقيقية
///   عبر NativeBtBridge (طبقة Kotlin أصلية، راجع print_service_io.dart).
/// - على الويب (dart:io غير متاحة): حوار طباعة المتصفح الأصلي.
///
/// كل الشاشات تستورد هذا الملف فقط، ولا تستورد native_bt_bridge.dart أو
/// print_service_io.dart مباشرة أبدًا — هذا يضمن أن كود الويب لا "يرى" أي
/// كود خاص بالبلوتوث غير المدعوم على الويب إطلاقًا.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'print_service_web.dart' if (dart.library.io) 'print_service_io.dart';

export 'printer_device.dart';
export 'print_service_web.dart' if (dart.library.io) 'print_service_io.dart';

/// نقطة الدخول الموصى بها للطباعة من كل شاشات التطبيق. تُغني عن استدعاء
/// PrintService.instance.printPdfBytes يدويًا من كل شاشة على حدة، وتضمن
/// نفس سلوك التعافي في كل مكان.
///
/// خلفية القرار: على بعض الأجهزة، مكتبة print_bluetooth_thermal تفشل في
/// الكتابة على المقبس دائمًا (raced، صلاحيات، أو خلل بالمكتبة نفسها) رغم
/// أن الطابعة سليمة تمامًا — أُثبت هذا عمليًا بأن نفس الهاتف ونفس الطابعة
/// يطبعان بلا مشاكل عبر تطبيق خارجي (RawBT) يستخدم مربع حوار الطباعة
/// القياسي بنظام أندرويد. لذلك بدل الاستمرار بمحاولة إصلاح مكتبة لا نملك
/// مصدرها، نوفّر مسارًا بديلاً مضمونًا يستخدم نفس آلية النظام تلك مباشرة.
///
/// - [preferSystem] = false (الافتراضي): يحاول الاتصال المباشر بالبلوتوث
///   أولاً (أسرع، بلا تطبيق إضافي مطلوب)؛ إن فشل، يعرض زر "جرّب تطبيق آخر"
///   يفتح فورًا مربع حوار نظام التشغيل بنفس بيانات الفاتورة دون أي خطوة
///   إضافية من المستخدم.
/// - [preferSystem] = true: يتخطى المحاولة المباشرة تمامًا ويذهب لمربع حوار
///   النظام فورًا — للأجهزة التي أثبتت أن مسارها المباشر يفشل دائمًا، حتى
///   لا ننتظر محاولة محكوم عليها بالفشل (~2-3 ثوانٍ) في كل عملية طباعة.
///   يُضبط هذا الخيار من شاشة إعدادات الطباعة (company_settings.dart:
///   preferSystemPrintDialog).
Future<void> printDocument(
  BuildContext context,
  Uint8List pdfBytes, {
  String? printerMac,
  bool preferSystem = false,
  int blackThreshold = 175,
  VoidCallback? onPrinted,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  if (preferSystem) {
    final ok = await PrintService.instance.printViaSystemDialog(pdfBytes);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'تم إرسال الفاتورة لخدمة الطباعة' : 'أُلغيت الطباعة')));
    if (ok) onPrinted?.call();
    return;
  }

  final ok = await PrintService.instance
      .printPdfBytes(pdfBytes, printerMac: printerMac, blackThreshold: blackThreshold);
  if (!context.mounted) return;
  if (ok) {
    messenger.showSnackBar(const SnackBar(content: Text('تمت الطباعة')));
    onPrinted?.call();
    return;
  }
  messenger.showSnackBar(SnackBar(
    content: const Text('تعذّر الاتصال المباشر بالطابعة'),
    duration: const Duration(seconds: 8),
    action: SnackBarAction(
      label: 'جرّب تطبيق آخر',
      onPressed: () async {
        final ok2 = await PrintService.instance.printViaSystemDialog(pdfBytes);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok2 ? 'تم إرسال الفاتورة لخدمة الطباعة' : 'أُلغيت الطباعة')));
        if (ok2) onPrinted?.call();
      },
    ),
  ));
}

/// حوار يعرض سجل آخر محاولة طباعة/اتصال خطوة بخطوة (بالتوقيت وأي استثناء
/// فعلي حدث)، مع زر نسخ لإرسال النص كاملاً عند طلب دعم فني. هذا يستبدل
/// رسالة "تعذّر الاتصال بالطابعة" العامة التي لا تُبيّن أين تحديدًا يفشل
/// الاتصال (صلاحيات؟ مقبس ميت؟ حجم البيانات؟ استثناء غير متوقع؟).
Future<void> showPrintDiagnosticsDialog(BuildContext context) async {
  final log = PrintService.instance.lastAttemptLog;
  final text = log.isEmpty
      ? 'لا يوجد سجل بعد — جرّب الطباعة أو الاتصال مرة أخرى ثم افتح التفاصيل.'
      : log.join('\n');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تفاصيل محاولة الاتصال'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(ctx)
                .showSnackBar(const SnackBar(content: Text('تم نسخ التفاصيل')));
          },
          child: const Text('نسخ'),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
      ],
    ),
  );
}
