import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'pdf_preview_screen.dart';

import '../models/customer.dart';
import '../models/receipt.dart';
import '../providers/app_provider.dart';
import '../services/pdf_service.dart';
import '../services/print_service.dart';
import '../services/feedback_service.dart';
import '../services/share_util.dart';
import '../utils/formatters.dart';
import '../widgets/big_card.dart';
import '../widgets/signature_pad_widget.dart';

/// شاشة سند القبض: مبلغ، طريقة الدفع (نقدًا/تحويل)، تاريخ ورقم قابلان
/// للتعديل، اختيار العميل، توقيع المندوب، ثم عرض رصيد العميل بعد السند
class ReceiptScreen extends StatefulWidget {
  final Receipt? existing;
  final Customer? initialCustomer;
  const ReceiptScreen({super.key, this.existing, this.initialCustomer});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _uuid = const Uuid();
  late String _id;
  late DateTime _date;
  final _docNumberCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  ReceiptMethod _method = ReceiptMethod.cash;
  Customer? _customer;
  String? _repSignaturePath;
  // يُلتقط مرة واحدة فقط عند الإنشاء، ويُحافَظ عليه كما هو عند التعديل
  String _repName = '';
  double _previewBalance = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    if (widget.existing != null) {
      final e = widget.existing!;
      _id = e.id;
      _date = e.date;
      _docNumberCtrl.text = e.docNumber;
      _amountCtrl.text = e.amount.toString();
      _method = e.method;
      _notesCtrl.text = e.notes;
      _repSignaturePath = e.repSignaturePath;
      _repName = e.repName;
      _customer = app.customers.firstWhere((c) => c.id == e.customerId,
          orElse: () => Customer(id: e.customerId, name: e.customerName));
    } else {
      _id = _uuid.v4();
      _date = DateTime.now();
      // توقيع افتراضي محفوظ للمندوب من الإعدادات، بدل توقيعه يدويًا بكل سند
      _repSignaturePath = app.settings.defaultRepSignaturePath;
      final currentName = app.currentUser?.displayName.trim() ?? '';
      _repName = currentName.isNotEmpty ? currentName : app.settings.repName;
      app.peekNextReceiptNumber().then((n) {
        if (mounted) setState(() => _docNumberCtrl.text = n);
      });
      if (widget.initialCustomer != null) {
        _customer = widget.initialCustomer;
      }
    }
    _amountCtrl.addListener(_recalc);
    _recalc();
  }

  Future<void> _recalc() async {
    if (_customer == null) return;
    final app = context.read<AppProvider>();
    final base = await app.getCustomerBalanceExcluding(_customer!.id,
        excludeReceiptId: _id);
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (mounted) setState(() => _previewBalance = base - amount);
  }

  Future<void> _pickCustomer() async {
    final app = context.read<AppProvider>();
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.all(14),
          child: GridView.builder(
            controller: controller,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.3,
            ),
            itemCount: app.customers.length,
            itemBuilder: (ctx, i) {
              final c = app.customers[i];
              return BigCard(
                icon: Icons.person,
                title: c.name,
                subtitle: c.phone,
                onTap: () => Navigator.pop(context, c),
              );
            },
          ),
        ),
      ),
    );
    if (selected != null) {
      setState(() => _customer = selected);
      _recalc();
    }
  }

  Receipt? _build() {
    if (_customer == null) {
      _snack('الرجاء اختيار العميل');
      return null;
    }
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      _snack('الرجاء إدخال مبلغ صحيح');
      return null;
    }
    if (_docNumberCtrl.text.trim().isEmpty) {
      _snack('الرجاء إدخال رقم السند');
      return null;
    }
    return Receipt(
      id: _id,
      docNumber: _docNumberCtrl.text.trim(),
      date: _date,
      amount: amount,
      method: _method,
      customerId: _customer!.id,
      customerName: _customer!.name,
      repSignaturePath: _repSignaturePath,
      repName: _repName,
      notes: _notesCtrl.text.trim(),
    );
  }

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final r = _build();
    if (r == null) return;
    setState(() => _saving = true);
    try {
      await context.read<AppProvider>().saveReceipt(r);
      if (mounted) {
        FeedbackService.onSaved(context);
        _snack('تم حفظ السند بنجاح');
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printReceipt() async {
    final r = _build();
    if (r == null) return;
    final app = context.read<AppProvider>();
    final bytes = await PdfService.instance.generateReceiptPdf(r, app.settings);
    final ok = await PrintService.instance
        .printPdfBytes(bytes, printerMac: app.settings.printerAddress);
    _snack(ok ? 'تمت الطباعة' : 'تعذّر الاتصال بالطابعة — تحقق من الإعدادات');
  }

  Future<void> _downloadPdf() async {
    final r = _build();
    if (r == null) return;
    final app = context.read<AppProvider>();
    final bytes = await PdfService.instance.generateReceiptPdf(r, app.settings);
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر مكان حفظ السند',
      fileName: 'سند_قبض_${r.docNumber}.pdf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputPath == null) return;
    _snack('تم حفظ PDF بنجاح');
  }

  Future<void> _previewReceipt() async {
    final r = _build();
    if (r == null) return;
    final app = context.read<AppProvider>();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: 'سند قبض',
          shareFileName: 'سند_قبض_${r.docNumber}.pdf',
          buildPdf: () => PdfService.instance.generateReceiptPdf(r, app.settings),
        ),
      ),
    );
  }

  Future<void> _sharePdf() async {
    final r = _build();
    if (r == null) return;
    final app = context.read<AppProvider>();
    final bytes = await PdfService.instance.generateReceiptPdf(r, app.settings);
    await ShareUtil.shareBytes(bytes, 'سند_قبض_${r.docNumber}.pdf',
        text: 'سند قبض ${r.docNumber}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سند قبض')),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(Formatters.d(_date)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _docNumberCtrl,
                        decoration: const InputDecoration(labelText: 'رقم السند'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('العميل', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickCustomer,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_pin_circle),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _customer?.name ?? 'اضغط لاختيار العميل',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Icon(Icons.chevron_left),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                      labelText: 'المبلغ المستلم', prefixIcon: Icon(Icons.payments)),
                ),
                const SizedBox(height: 16),
                SegmentedButton<ReceiptMethod>(
                  segments: const [
                    ButtonSegment(
                        value: ReceiptMethod.cash,
                        label: Text('نقدًا'),
                        icon: Icon(Icons.money)),
                    ButtonSegment(
                        value: ReceiptMethod.transfer,
                        label: Text('تحويل'),
                        icon: Icon(Icons.account_balance)),
                  ],
                  selected: {_method},
                  onSelectionChanged: (s) => setState(() => _method = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                const SizedBox(height: 18),
                SignaturePadWidget(
                  label: 'توقيع المندوب',
                  existingPath: _repSignaturePath,
                  onSaved: (path) => setState(() => _repSignaturePath = path),
                ),
                const SizedBox(height: 18),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('رصيد المديونية المتوقع بعد الحفظ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(Formatters.money(_previewBalance),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                  onPressed: _save,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('معاينة السند'),
                  onPressed: _previewReceipt,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print),
                        label: const Text('طباعة 80مم'),
                        onPressed: _printReceipt,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('تحميل PDF'),
                        onPressed: _downloadPdf,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: _sharePdf,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
