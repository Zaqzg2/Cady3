import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company_settings.dart';
import '../models/invoice.dart';
import '../models/ledger_entry.dart';
import '../models/receipt.dart';
import 'image_store.dart';

/// توليد ملفات PDF حقيقية بعرض 80مم مطابقة تمامًا لما تطبعه
/// الطابعة الحرارية (نفس التخطيط يُستخدم أيضًا لأوامر ESC/POS في print_service).
///
/// ملاحظة مهمة: لدعم الحروف العربية داخل PDF يجب توفير خط TTF عربي
/// ضمن assets/fonts/NotoNaskhArabic-Regular.ttf وتسجيله في pubspec.yaml
/// تحت fonts: — بدون ذلك ستظهر الحروف العربية كمربعات فارغة.
///
/// كل صور الشعار/التوقيع تُحمَّل من ImageStore *قبل* بناء المستند، لأن
/// دوال البناء (build/header) في مكتبة pdf متزامنة (غير async) ولا يمكن
/// انتظار Future بداخلها مباشرة.
class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  pw.Font? _arabicFont;
  pw.Font? _arabicFontBold;

  Future<void> _ensureFonts() async {
    if (_arabicFont != null) return;
    try {
      final regular =
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      _arabicFont = pw.Font.ttf(regular);
      try {
        final bold =
            await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
        _arabicFontBold = pw.Font.ttf(bold);
      } catch (_) {
        _arabicFontBold = _arabicFont;
      }
    } catch (_) {
      // في حال عدم توفر الخط بعد سيستخدم الخط الافتراضي (لن يدعم العربية بشكل مثالي)
      _arabicFont = null;
      _arabicFontBold = null;
    }
  }

  final _currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'ر.ي',
    decimalDigits: 0,
  );

  pw.Widget _header(CompanySettings s,
      {required String docTitle, Uint8List? logoBytes}) {
    final scale = s.invoiceBodyFontSize / 9.0;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoBytes != null)
          pw.Container(
            height: 55,
            margin: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Image(pw.MemoryImage(logoBytes)),
          ),
        pw.Text(
          s.companyName,
          style: pw.TextStyle(font: _arabicFontBold, fontSize: 13 * scale),
          textDirection: pw.TextDirection.rtl,
        ),
        if (s.companyPhone.isNotEmpty)
          pw.Text(s.companyPhone,
              style: pw.TextStyle(font: _arabicFont, fontSize: 8 * scale),
              textDirection: pw.TextDirection.rtl),
        if (s.companyAddress.isNotEmpty)
          pw.Text(s.companyAddress,
              style: pw.TextStyle(font: _arabicFont, fontSize: 8 * scale),
              textDirection: pw.TextDirection.rtl),
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 5 * s.invoiceLineSpacing),
          child: pw.Divider(thickness: 0.7),
        ),
        pw.Text(
          docTitle,
          style: pw.TextStyle(font: _arabicFontBold, fontSize: 11 * scale),
          textDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  /// فراغ رأسي يتناسب مع "تباعد أسطر الفاتورة" من شاشة الإعدادات — يُستخدم
  /// بين أقسام الفاتورة/السند (بعد الترويسة، قبل/بعد الملاحظات، قبل التوقيع
  /// والتذييل). قبل هذا التعديل كانت هذه الفراغات قيمًا ثابتة (SizedBox)
  /// لا تتغيّر أبدًا عند تحريك شريط "تباعد الأسطر"، بعكس صفوف _kv التي كانت
  /// تستجيب له فعلاً — لذلك كان تصغير الشريط يبدو بلا أثر يُذكر على شكل
  /// الفاتورة الكامل رغم عمله جزئيًا. الجدول (pw.Table) لا علاقة له بهذا
  /// المتغيّر أصلاً؛ تباعده الخاص يأتي من settings.rowSpacing وحده.
  pw.Widget _gap(CompanySettings s, double base) =>
      pw.SizedBox(height: base * s.invoiceLineSpacing);

  pw.Widget _kv(String k, String v, CompanySettings s, {double? fontSize}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 1.5 * s.invoiceLineSpacing),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(v,
              style: pw.TextStyle(
                  font: _arabicFont, fontSize: fontSize ?? s.invoiceBodyFontSize),
              textDirection: pw.TextDirection.rtl),
          pw.Text(k,
              style: pw.TextStyle(
                  font: _arabicFont, fontSize: fontSize ?? s.invoiceBodyFontSize),
              textDirection: pw.TextDirection.rtl),
        ],
      ),
    );
  }

  Future<Uint8List> generateInvoicePdf(
      Invoice inv, CompanySettings settings) async {
    await _ensureFonts();
    final logoBytes = await ImageStore.instance.load(settings.logoPath);
    final signatureBytes = await ImageStore.instance.load(inv.signaturePath);
    final df = DateFormat('yyyy/MM/dd');
    final title = inv.kind == InvoiceKind.sale ? 'فاتورة بيع' : 'فاتورة مرتجع';
    // ملاحظة RTL: مكتبة pdf لا "تعكس" ترتيب أعمدة pw.Table تلقائيًا حسب
    // اتجاه اللغة (بعكس pw.Row الذي عالجناه يدويًا في _kv بوضع القيمة قبل
    // العنوان). لذلك نعكس ترتيب القائمة هنا فقط، مرة واحدة، بحيث يظهر أول
    // عمود منطقي (الصنف) على أقصى اليمين كما في القراءة العربية الصحيحة —
    // نفس الترتيب المستخدم في جدول كشف الحساب أدناه.
    final visibleCols =
        settings.tableColumns.where((c) => c.visible).toList().reversed.toList();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(settings, docTitle: title, logoBytes: logoBytes),
              _gap(settings, 4),
              _kv('رقم الفاتورة', inv.docNumber, settings),
              _kv('التاريخ', df.format(inv.date), settings),
              _kv('العميل', inv.customerName, settings),
              if (inv.repName.trim().isNotEmpty)
                _kv('المندوب', inv.repName, settings),
              _kv('نوع الدفع',
                  inv.paymentMode == PaymentMode.cash ? 'نقدًا' : 'آجل', settings),
              pw.Divider(thickness: 0.5),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
                columnWidths: {
                  for (int i = 0; i < visibleCols.length; i++)
                    i: pw.FlexColumnWidth(visibleCols[i].widthFlex),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: visibleCols
                        .map((c) => pw.Padding(
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Text(
                                c.label,
                                style: pw.TextStyle(
                                    font: _arabicFontBold,
                                    fontSize: settings.tableFontSize),
                                textDirection: pw.TextDirection.rtl,
                                textAlign: pw.TextAlign.center,
                              ),
                            ))
                        .toList(),
                  ),
                  for (final item in inv.items)
                    pw.TableRow(
                      children: visibleCols.map((c) {
                        String val;
                        switch (c.key) {
                          case 'productName':
                            val = item.productName;
                            break;
                          case 'quantity':
                            val = item.quantity.toString();
                            break;
                          case 'price':
                            val = item.price.toStringAsFixed(0);
                            break;
                          case 'total':
                            val = item.total.toStringAsFixed(0);
                            break;
                          default:
                            val = '';
                        }
                        return pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(
                            val,
                            style: pw.TextStyle(
                                font: _arabicFont,
                                fontSize: settings.tableFontSize),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.center,
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
              _gap(settings, 4),
              pw.Divider(thickness: 0.5),
              _kv('الإجمالي الفرعي', _currency.format(inv.subTotal), settings),
              if (inv.discountValue > 0)
                _kv('الخصم', _currency.format(inv.discountValue), settings),
              _kv('الإجمالي النهائي', _currency.format(inv.grandTotal), settings,
                  fontSize: 11 * (settings.invoiceBodyFontSize / 9.0)),
              pw.Divider(thickness: 0.5),
              _kv('رصيد العميل بعد الفاتورة',
                  _currency.format(inv.balanceAfter), settings),
              if (inv.notes.isNotEmpty) ...[
                _gap(settings, 4),
                pw.Text('ملاحظات:',
                    style: pw.TextStyle(
                        font: _arabicFontBold,
                        fontSize: 9 * (settings.invoiceBodyFontSize / 9.0)),
                    textDirection: pw.TextDirection.rtl),
                pw.Text(inv.notes,
                    style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 8 * (settings.invoiceBodyFontSize / 9.0)),
                    textDirection: pw.TextDirection.rtl),
              ],
              if (signatureBytes != null) ...[
                _gap(settings, 8),
                pw.Text('توقيع العميل:',
                    style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 8 * (settings.invoiceBodyFontSize / 9.0)),
                    textDirection: pw.TextDirection.rtl),
                pw.Container(
                  height: 60,
                  alignment: pw.Alignment.center,
                  child: pw.Image(pw.MemoryImage(signatureBytes)),
                ),
              ],
              _gap(settings, 6),
              pw.Center(
                child: pw.Text(settings.invoiceFooterText,
                    style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 8 * (settings.invoiceBodyFontSize / 9.0)),
                    textDirection: pw.TextDirection.rtl),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<Uint8List> generateReceiptPdf(
      Receipt r, CompanySettings settings) async {
    await _ensureFonts();
    final logoBytes = await ImageStore.instance.load(settings.logoPath);
    final signatureBytes = await ImageStore.instance.load(r.repSignaturePath);
    final df = DateFormat('yyyy/MM/dd');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(settings, docTitle: 'سند قبض', logoBytes: logoBytes),
              _gap(settings, 4),
              _kv('رقم السند', r.docNumber, settings),
              _kv('التاريخ', df.format(r.date), settings),
              _kv('العميل', r.customerName, settings),
              if (r.repName.trim().isNotEmpty)
                _kv('المندوب', r.repName, settings),
              _kv('طريقة الدفع',
                  r.method == ReceiptMethod.cash ? 'نقدًا' : 'تحويل', settings),
              pw.Divider(thickness: 0.5),
              _kv('المبلغ المستلم', _currency.format(r.amount), settings,
                  fontSize: 12 * (settings.invoiceBodyFontSize / 9.0)),
              pw.Divider(thickness: 0.5),
              _kv('رصيد العميل بعد السند', _currency.format(r.balanceAfter), settings),
              if (r.notes.isNotEmpty) ...[
                _gap(settings, 4),
                pw.Text(r.notes,
                    style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 8 * (settings.invoiceBodyFontSize / 9.0)),
                    textDirection: pw.TextDirection.rtl),
              ],
              if (signatureBytes != null) ...[
                _gap(settings, 8),
                pw.Text('توقيع المندوب:',
                    style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 8 * (settings.invoiceBodyFontSize / 9.0)),
                    textDirection: pw.TextDirection.rtl),
                pw.Container(
                  height: 60,
                  alignment: pw.Alignment.center,
                  child: pw.Image(pw.MemoryImage(signatureBytes)),
                ),
              ],
              _gap(settings, 6),
              pw.Center(
                child: pw.Text(settings.invoiceFooterText,
                    style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 8 * (settings.invoiceBodyFontSize / 9.0)),
                    textDirection: pw.TextDirection.rtl),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// كشف حساب العميل — يدعم صيغتين حسب إعدادات الشركة: 80مم حراري (صفحة
  /// واحدة مستمرة الطول عبر pw.Page، تمامًا كالفاتورة/السند) أو A4 عادي
  /// (صفحات متعددة حقيقية عبر pw.MultiPage، مناسب لكشوفات طويلة).
  Future<Uint8List> generateStatementPdf(
    String customerName,
    List<LedgerEntry> entries,
    CompanySettings settings,
  ) async {
    await _ensureFonts();
    final logoBytes = await ImageStore.instance.load(settings.logoPath);
    final df = DateFormat('yyyy/MM/dd');
    final doc = pw.Document();

    String docTypeLabel(LedgerDocType t) {
      switch (t) {
        case LedgerDocType.invoiceSale:
          return 'فاتورة بيع';
        case LedgerDocType.invoiceReturn:
          return 'فاتورة مرتجع';
        case LedgerDocType.receipt:
          return 'سند قبض';
        case LedgerDocType.opening:
          return 'رصيد افتتاحي';
      }
    }

    final isThermal = settings.defaultStatementFormat == StatementFormat.thermal80;
    final pageFormat = isThermal ? PdfPageFormat.roll80 : PdfPageFormat.a4;

    // ترتيب الأعمدة معكوس عمدًا هنا (الرصيد أولاً بالقائمة) لأن pw.Table
    // يضع العنصر الأول بالقائمة أقصى اليسار دائمًا (لا يوجد عكس تلقائي
    // حسب اتجاه اللغة في هذه المكتبة، بعكس pw.Row الذي عالجناه يدويًا في
    // _kv). هذا يجعل "التاريخ" (أول عمود منطقيًا) يظهر أقصى اليمين، مطابقًا
    // للقراءة العربية الصحيحة.
    pw.Widget buildTable() {
      return pw.Table(
        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4), // الرصيد
          1: pw.FlexColumnWidth(1.2), // دائن
          2: pw.FlexColumnWidth(1.2), // مدين
          3: pw.FlexColumnWidth(1.3), // رقم المستند
          4: pw.FlexColumnWidth(2), // البيان
          5: pw.FlexColumnWidth(1.3), // التاريخ
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              'الرصيد',
              'دائن',
              'مدين',
              'رقم المستند',
              'البيان',
              'التاريخ',
            ]
                .map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        h,
                        style: pw.TextStyle(
                            font: _arabicFontBold,
                            fontSize: settings.tableFontSize),
                        textDirection: pw.TextDirection.rtl,
                        textAlign: pw.TextAlign.center,
                      ),
                    ))
                .toList(),
          ),
          for (final e in entries)
            pw.TableRow(
              children: [
                _currency.format(e.runningBalance),
                e.credit > 0 ? _currency.format(e.credit) : '-',
                e.debit > 0 ? _currency.format(e.debit) : '-',
                e.docNumber,
                docTypeLabel(e.docType),
                df.format(e.date),
              ]
                  .map((v) => pw.Padding(
                        padding: pw.EdgeInsets.symmetric(
                            vertical: settings.rowSpacing, horizontal: 3),
                        child: pw.Text(
                          v,
                          style: pw.TextStyle(
                              font: _arabicFont,
                              fontSize: settings.tableFontSize),
                          textDirection: pw.TextDirection.rtl,
                          textAlign: pw.TextAlign.center,
                        ),
                      ))
                  .toList(),
            ),
        ],
      );
    }

    final summary = entries.isEmpty
        ? null
        : _kv('الرصيد الحالي', _currency.format(entries.last.runningBalance),
            settings, fontSize: 12);

    if (isThermal) {
      // صيغة 80مم: صفحة واحدة مستمرة الطول بدون تقسيم صفحات — تمامًا مثل
      // generateInvoicePdf/generateReceiptPdf أعلاه. هذا هو صلب إصلاح مشكلة
      // "الصفحة البيضاء": roll80 ارتفاعه غير محدود، واستخدام MultiPage معه
      // (كما كان سابقًا) يُنتج صفحات فارغة لأن خوارزمية تقسيم صفحات
      // MultiPage لا تتعامل بشكل صحيح مع ارتفاع صفحة غير محدود.
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(8),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(settings,
                  docTitle: 'كشف حساب: $customerName', logoBytes: logoBytes),
              _gap(settings, 8),
              buildTable(),
              _gap(settings, 12),
              if (summary != null) summary,
            ],
          ),
        ),
      );
    } else {
      // صيغة A4: كشف الحساب قد يحتوي عشرات الصفوف، فيحتاج تقسيم صفحات
      // حقيقي — MultiPage مناسب هنا تمامًا لأن ارتفاع صفحة A4 محدود.
      doc.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              _header(settings,
                  docTitle: 'كشف حساب: $customerName', logoBytes: logoBytes),
              _gap(settings, 8),
            ],
          ),
          build: (context) => [
            buildTable(),
            _gap(settings, 12),
            if (summary != null) summary,
          ],
        ),
      );
    }
    return doc.save();
  }
}
