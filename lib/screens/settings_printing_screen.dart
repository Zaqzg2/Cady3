import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company_settings.dart';
import '../providers/app_provider.dart';
import '../services/print_service.dart';

/// الطباعة والفاتورة: الطابعة الحرارية وحالة الاتصال، حجم خط/تباعد جدول
/// الأصناف مع معاينة حية، حجم خط/تباعد بقية نص الفاتورة والسند، وصيغة
/// طباعة كشف الحساب الافتراضية (A4 / 80مم)
class SettingsPrintingScreen extends StatefulWidget {
  const SettingsPrintingScreen({super.key});

  @override
  State<SettingsPrintingScreen> createState() => _SettingsPrintingScreenState();
}

class _SettingsPrintingScreenState extends State<SettingsPrintingScreen> {
  double _tableFontSize = 9;
  double _rowSpacing = 4;
  double _bodyFontSize = 9;
  double _lineSpacing = 1.2;
  double _blackThreshold = 175;
  StatementFormat _statementFormat = StatementFormat.thermal80;
  List<PrinterDevice> _pairedDevices = [];
  String? _selectedPrinterMac;
  bool _loadingDevices = false;
  bool _liveConnected = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppProvider>().settings;
    _tableFontSize = s.tableFontSize;
    _rowSpacing = s.rowSpacing;
    _bodyFontSize = s.invoiceBodyFontSize;
    _lineSpacing = s.invoiceLineSpacing;
    _blackThreshold = s.printBlackThreshold.toDouble();
    _statementFormat = s.defaultStatementFormat;
    _selectedPrinterMac = s.printerAddress;
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final list = await PrintService.instance.getPairedDevices();
      if (mounted) setState(() => _pairedDevices = list);
    } catch (_) {
      // البلوتوث قد لا يكون مفعّلاً أو الصلاحيات غير ممنوحة بعد
    }
    await _refreshLiveStatus();
    if (mounted) setState(() => _loadingDevices = false);
  }

  /// حالة "متصلة" بالإعدادات كانت تُبنى فقط من كون عنوان الطابعة محفوظًا
  /// (آخر طابعة نجح الاتصال بها)، بغض النظر عن حالة مقبس البلوتوث الفعلية
  /// الآن — وهي تنقطع بصمت كثيرًا (خمول، قفل الشاشة...). لذلك نتحقق من
  /// الاتصال الحي هنا، ونحاول استعادته تلقائيًا وبصمت إن انقطع، بدل إظهار
  /// شارة "متصلة" مضلِّلة لا تعكس ما سيحدث فعلًا عند الطباعة.
  Future<void> _refreshLiveStatus() async {
    if (_selectedPrinterMac == null) {
      if (mounted) setState(() => _liveConnected = false);
      return;
    }
    // تحقّق حقيقي (كتابة فعلية على المقبس) بدل الاكتفاء بـ isConnected —
    // نفس آلية التحقق المستخدمة عند الطباعة الفعلية بالضبط (راجع
    // _writeVerified في print_service_io.dart)، حتى لا تعرض هذه الشاشة
    // "متصلة" بينما الطباعة الفعلية تفشل.
    final live = await PrintService.instance.verifyConnection(_selectedPrinterMac);
    if (mounted) setState(() => _liveConnected = live);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _connectPrinter(PrinterDevice device) async {
    // نحفظ عنوان الطابعة إن نجحت المصافحة الأساسية connect() فقط — لا نشترط
    // نجاح verifyConnection (اختبار كتابة فعلي) للحفظ، لأن كل منطق إعادة
    // المحاولة بباقي التطبيق (printPdfBytes) يعتمد على وجود printerAddress
    // محفوظ ليستخدمه عند إعادة الاتصال. لو اشترطنا نجاح الكتابة قبل الحفظ،
    // وفشلت الكتابة دائمًا لأي سبب (كما حدث هنا)، لن يُحفَظ العنوان أبدًا —
    // فتفقد كل شاشات الطباعة القدرة حتى على المحاولة، ويتفاقم العطل بدل أن
    // يُشخَّص.
    final connected = await PrintService.instance.connect(device.macAddress);
    if (!mounted) return;
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تعذّر الاتصال بالطابعة'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
            label: 'التفاصيل', onPressed: () => showPrintDiagnosticsDialog(context)),
      ));
      return;
    }

    final app = context.read<AppProvider>();
    final s = app.settings;
    s.printerAddress = device.macAddress;
    s.printerName = device.name;
    await app.saveSettings(s);
    if (!mounted) return;
    setState(() => _selectedPrinterMac = device.macAddress);

    // الآن —وبعد الحفظ— نتحقق فعليًا بكتابة حقيقية لعرض حالة دقيقة، دون أن
    // يمنع فشلها حفظ العنوان الذي حصل للتو.
    final verified = await PrintService.instance.verifyConnection(device.macAddress);
    if (!mounted) return;
    setState(() => _liveConnected = verified);
    if (verified) {
      _snack('تم الاتصال بالطابعة ${device.name}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('اتصل الجهاز، لكن فشل اختبار كتابة فعلي — الطباعة الحقيقية ستفشل غالبًا'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
            label: 'التفاصيل', onPressed: () => showPrintDiagnosticsDialog(context)),
      ));
    }
  }

  Future<void> _disconnectPrinter() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.printerAddress = null;
    s.printerName = null;
    await app.saveSettings(s);
    await PrintService.instance.disconnect();
    if (!mounted) return;
    setState(() {
      _selectedPrinterMac = null;
      _liveConnected = false;
    });
  }

  Future<void> _saveNumbers() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.tableFontSize = _tableFontSize;
    s.rowSpacing = _rowSpacing;
    s.invoiceBodyFontSize = _bodyFontSize;
    s.invoiceLineSpacing = _lineSpacing;
    s.printBlackThreshold = _blackThreshold.round();
    s.defaultStatementFormat = _statementFormat;
    await app.saveSettings(s);
    if (mounted) _snack('تم حفظ إعدادات الطباعة');
  }

  @override
  Widget build(BuildContext context) {
    final connected = _liveConnected;
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('الطباعة والفاتورة'),
        actions: [TextButton(onPressed: _saveNumbers, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (kIsWeb)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الطباعة الحرارية عبر بلوتوث متاحة فقط على تطبيق الجوال. '
                      'على المتصفح، يفتح زر "طباعة" حوار الطباعة الأصلي بالمتصفح '
                      '(يمكنك الطباعة على أي طابعة متصلة بجهازك، أو الحفظ كـ PDF).',
                      style: TextStyle(fontSize: 12.5, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                const Text('الطابعة الحرارية 80مم',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (connected ? Colors.green : Colors.red).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: connected ? Colors.green : Colors.red),
                      ),
                      const SizedBox(width: 6),
                      Text(connected ? 'متصلة' : 'غير متصلة',
                          style: TextStyle(
                              fontSize: 12,
                              color: connected ? Colors.green.shade800 : Colors.red.shade800,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            if (connected) ...[
              const SizedBox(height: 6),
              Text('متصلة حاليًا بـ: ${app.settings.printerName ?? _selectedPrinterMac}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _loadingDevices
                        ? const SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: const Text('تحديث قائمة الأجهزة'),
                    onPressed: _loadingDevices ? null : _loadPairedDevices,
                  ),
                ),
                if (connected) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off, color: Colors.red),
                      label: const Text('فصل الطابعة', style: TextStyle(color: Colors.red)),
                      onPressed: _disconnectPrinter,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (_pairedDevices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا توجد أجهزة مقترنة — اقرن الطابعة أولًا من إعدادات بلوتوث الهاتف'),
              )
            else
              ..._pairedDevices.map((d) => RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(d.name),
                    subtitle: Text(d.macAddress),
                    value: d.macAddress,
                    groupValue: _selectedPrinterMac,
                    onChanged: (_) => _connectPrinter(d),
                  )),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اطبع عبر تطبيق آخر بدل الاتصال المباشر'),
              subtitle: const Text(
                  'يتخطى الاتصال المباشر بالبلوتوث ويفتح حوار طباعة النظام مباشرة '
                  '(اختر منه أي تطبيق مثبَّت مثل RawBT). فعّله إن كان جهازك لا '
                  'يطبع مباشرة رغم ظهوره "متصلة".',
                  style: TextStyle(fontSize: 12)),
              value: app.settings.preferSystemPrintDialog,
              onChanged: (v) async {
                final s = app.settings;
                s.preferSystemPrintDialog = v;
                await app.saveSettings(s);
              },
            ),
          ],
          const Divider(height: 32),

          const Text('معاينة حية', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _LivePreview(
            tableFontSize: _tableFontSize,
            rowSpacing: _rowSpacing,
            bodyFontSize: _bodyFontSize,
            lineSpacing: _lineSpacing,
          ),
          const SizedBox(height: 16),

          Text('حجم خط جدول الأصناف: ${_tableFontSize.toStringAsFixed(0)}'),
          Slider(
            value: _tableFontSize,
            min: 6,
            max: 14,
            divisions: 8,
            label: _tableFontSize.toStringAsFixed(0),
            onChanged: (v) => setState(() => _tableFontSize = v),
          ),
          Text('تباعد صفوف الجدول: ${_rowSpacing.toStringAsFixed(0)}'),
          Slider(
            value: _rowSpacing,
            min: 0,
            max: 16,
            divisions: 8,
            label: _rowSpacing.toStringAsFixed(0),
            onChanged: (v) => setState(() => _rowSpacing = v),
          ),
          const SizedBox(height: 8),
          Text('حجم خط بقية الفاتورة والسند: ${_bodyFontSize.toStringAsFixed(0)}'),
          Slider(
            value: _bodyFontSize,
            min: 6,
            max: 14,
            divisions: 8,
            label: _bodyFontSize.toStringAsFixed(0),
            onChanged: (v) => setState(() => _bodyFontSize = v),
          ),
          Text('تباعد أسطر الفاتورة والسند: ${_lineSpacing.toStringAsFixed(1)}x'),
          Slider(
            value: _lineSpacing,
            min: 0.8,
            max: 2.4,
            divisions: 8,
            label: '${_lineSpacing.toStringAsFixed(1)}x',
            onChanged: (v) => setState(() => _lineSpacing = v),
          ),
          Text('كثافة/غمقان النص المطبوع: ${_blackThreshold.toStringAsFixed(0)}'
              '${_blackThreshold >= 200 ? '  (غامق جدًا)' : _blackThreshold <= 140 ? '  (فاتح)' : ''}'),
          Slider(
            value: _blackThreshold,
            min: 120,
            max: 210,
            divisions: 18,
            label: _blackThreshold.toStringAsFixed(0),
            onChanged: (v) => setState(() => _blackThreshold = v),
          ),
          const Text(
              'ارفعها إن كان النص يطبع باهتًا/رماديًا، خفّضها إن كان غامقًا جدًا '
              'أو خطوط الجدول أصبحت سميكة أكثر من اللازم.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const Divider(height: 32),

          const Text('صيغة طباعة كشف الحساب الافتراضية',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('تُستخدم تلقائيًا داخل كل عميل دون الحاجة لاختيارها كل مرة',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          RadioListTile<StatementFormat>(
            contentPadding: EdgeInsets.zero,
            title: const Text('حراري 80مم (مثل الفاتورة)'),
            value: StatementFormat.thermal80,
            groupValue: _statementFormat,
            onChanged: (v) => setState(() => _statementFormat = v!),
          ),
          RadioListTile<StatementFormat>(
            contentPadding: EdgeInsets.zero,
            title: const Text('A4 عادي'),
            value: StatementFormat.a4,
            groupValue: _statementFormat,
            onChanged: (v) => setState(() => _statementFormat = v!),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: _saveNumbers,
            ),
          ),
        ],
      ),
    );
  }
}

/// معاينة مصغّرة حيّة لشكل جدول الفاتورة تتغيّر فورًا أثناء تحريك الشرائط
class _LivePreview extends StatelessWidget {
  final double tableFontSize;
  final double rowSpacing;
  final double bodyFontSize;
  final double lineSpacing;

  const _LivePreview({
    required this.tableFontSize,
    required this.rowSpacing,
    required this.bodyFontSize,
    required this.lineSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كادي للمنظفات',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: bodyFontSize + 3, fontWeight: FontWeight.bold)),
          SizedBox(height: 4 * lineSpacing),
          Text('فاتورة بيع #1003',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: bodyFontSize + 1, fontWeight: FontWeight.w600)),
          SizedBox(height: 6 * lineSpacing),
          Table(
            border: TableBorder.all(color: Colors.grey.shade400, width: 0.6),
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade200),
                children: ['الصنف', 'الكمية', 'السعر']
                    .map((h) => Padding(
                          padding: EdgeInsets.symmetric(vertical: rowSpacing / 2, horizontal: 3),
                          child: Text(h,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: tableFontSize, fontWeight: FontWeight.bold)),
                        ))
                    .toList(),
              ),
              TableRow(
                children: ['صابون سائل', '3', '1500']
                    .map((v) => Padding(
                          padding: EdgeInsets.symmetric(vertical: rowSpacing / 2, horizontal: 3),
                          child: Text(v,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: tableFontSize)),
                        ))
                    .toList(),
              ),
            ],
          ),
          SizedBox(height: 6 * lineSpacing),
          Text('الرصيد بعد الفاتورة: 8,850 ر.ي',
              textAlign: TextAlign.center, style: TextStyle(fontSize: bodyFontSize)),
        ],
      ),
    );
  }
}
