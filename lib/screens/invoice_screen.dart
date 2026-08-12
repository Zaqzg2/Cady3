import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pdf_preview_screen.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../providers/app_provider.dart';
import '../services/pdf_service.dart';
import '../services/print_service.dart';
import '../services/feedback_service.dart';
import '../services/share_util.dart';
import '../utils/formatters.dart';
import '../widgets/big_card.dart';
import '../widgets/quantity_selector.dart';
import '../widgets/signature_pad_widget.dart';

/// شاشة الفاتورة: تدعم فاتورة بيع وفاتورة مرتجع، نقدًا أو آجل
/// يمكن فتحها لإنشاء فاتورة جديدة، أو لتعديل فاتورة محفوظة (existing)
class InvoiceScreen extends StatefulWidget {
  final InvoiceKind kind;
  final bool forceCashCustomer;
  final Invoice? existing;
  final Customer? initialCustomer;

  const InvoiceScreen({
    super.key,
    required this.kind,
    this.forceCashCustomer = false,
    this.existing,
    this.initialCustomer,
  });

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final _uuid = const Uuid();
  late String _id;
  late DateTime _date;
  final _docNumberCtrl = TextEditingController();
  PaymentMode _paymentMode = PaymentMode.cash;
  Customer? _customer;
  final Map<String, InvoiceItem> _items = {}; // productId -> item
  final _discountPercentCtrl = TextEditingController(text: '0');
  final _discountAmountCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  String? _signaturePath;
  // اسم المندوب يُلتقط مرة واحدة فقط عند إنشاء الفاتورة (أو يُحافَظ عليه
  // كما هو عند تعديل فاتورة قديمة) — لا يتغيّر لاحقًا حتى لو عدّلها مستخدم
  // آخر، لأنه يمثّل مَن أجرى عملية البيع فعليًا.
  String _repName = '';
  double _previewBalance = 0;
  bool _saving = false;

  bool get _isReturn => widget.kind == InvoiceKind.saleReturn;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    if (widget.existing != null) {
      final e = widget.existing!;
      _id = e.id;
      _date = e.date;
      _docNumberCtrl.text = e.docNumber;
      _paymentMode = e.paymentMode;
      for (final it in e.items) {
        _items[it.productId] = it;
      }
      _discountPercentCtrl.text = e.discountPercent.toString();
      _discountAmountCtrl.text = e.discountAmount.toString();
      _notesCtrl.text = e.notes;
      _signaturePath = e.signaturePath;
      _repName = e.repName;
      _customer = app.customers.firstWhere((c) => c.id == e.customerId,
          orElse: () => Customer(id: e.customerId, name: e.customerName));
    } else {
      _id = _uuid.v4();
      _date = DateTime.now();
      final currentName = app.currentUser?.displayName.trim() ?? '';
      _repName = currentName.isNotEmpty ? currentName : app.settings.repName;
      app.peekNextInvoiceNumber(widget.kind).then((n) {
        if (mounted) setState(() => _docNumberCtrl.text = n);
      });
      if (widget.forceCashCustomer) {
        _customer = Customer(id: 'cash_customer', name: 'عميل نقدي');
      } else if (widget.initialCustomer != null) {
        _customer = widget.initialCustomer;
      }
    }
    _recalcBalance();
  }

  Future<void> _recalcBalance() async {
    if (_customer == null) return;
    final app = context.read<AppProvider>();
    final base = await app.getCustomerBalanceExcluding(_customer!.id,
        excludeInvoiceId: _id);
    final subTotal = _items.values.fold(0.0, (s, i) => s + i.total);
    final percent = double.tryParse(_discountPercentCtrl.text) ?? 0;
    final amount = double.tryParse(_discountAmountCtrl.text) ?? 0;
    final discountVal = subTotal * (percent / 100) + amount;
    final grand = (subTotal - discountVal).clamp(0, double.infinity);
    final effect = _isReturn ? -grand : grand;
    if (mounted) setState(() => _previewBalance = base + effect);
  }

  double get _subTotal => _items.values.fold(0.0, (s, i) => s + i.total);
  double get _discountValue {
    final percent = double.tryParse(_discountPercentCtrl.text) ?? 0;
    final amount = double.tryParse(_discountAmountCtrl.text) ?? 0;
    return _subTotal * (percent / 100) + amount;
  }

  double get _grandTotal {
    final t = _subTotal - _discountValue;
    return t < 0 ? 0 : t;
  }

  Future<void> _pickCustomer() async {
    final app = context.read<AppProvider>();
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CustomerPickerSheet(customers: app.customers),
    );
    if (selected != null) {
      setState(() => _customer = selected);
      _recalcBalance();
    }
  }

  void _addProduct(Product p) {
    setState(() {
      final existing = _items[p.id];
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _items[p.id] = InvoiceItem(
            productId: p.id, productName: p.name, price: p.price, quantity: 1);
      }
    });
    _recalcBalance();
  }

  Invoice _buildInvoice() {
    return Invoice(
      id: _id,
      docNumber: _docNumberCtrl.text.trim(),
      date: _date,
      kind: widget.kind,
      paymentMode: _paymentMode,
      customerId: _customer!.id,
      customerName: _customer!.name,
      items: _items.values.toList(),
      discountPercent: double.tryParse(_discountPercentCtrl.text) ?? 0,
      discountAmount: double.tryParse(_discountAmountCtrl.text) ?? 0,
      notes: _notesCtrl.text.trim(),
      signaturePath: _signaturePath,
      repName: _repName,
    );
  }

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    _discountPercentCtrl.dispose();
    _discountAmountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _validate() {
    if (_customer == null) {
      _snack('الرجاء اختيار العميل');
      return false;
    }
    if (_items.isEmpty) {
      _snack('الرجاء إضافة منتج واحد على الأقل');
      return false;
    }
    if (_docNumberCtrl.text.trim().isEmpty) {
      _snack('الرجاء إدخال رقم الفاتورة');
      return false;
    }
    return true;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      final inv = _buildInvoice();
      await context.read<AppProvider>().saveInvoice(inv);
      if (mounted) {
        FeedbackService.onSaved(context);
        _snack('تم حفظ الفاتورة بنجاح');
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Invoice?> _finalizedForOutput() async {
    if (!_validate()) return null;
    return _buildInvoice();
  }

  Future<void> _printInvoice() async {
    final inv = await _finalizedForOutput();
    if (inv == null) return;
    final app = context.read<AppProvider>();
    final bytes = await PdfService.instance.generateInvoicePdf(inv, app.settings);
    final ok = await PrintService.instance
        .printPdfBytes(bytes, printerMac: app.settings.printerAddress);
    _snack(ok ? 'تمت الطباعة' : 'تعذّر الاتصال بالطابعة — تحقق من الإعدادات');
  }

  Future<void> _downloadPdf() async {
    final inv = await _finalizedForOutput();
    if (inv == null) return;
    final app = context.read<AppProvider>();
    final bytes = await PdfService.instance.generateInvoicePdf(inv, app.settings);
    // نستخدم file_picker لنطلب من المستخدم يختار مكان حفظ حقيقي يقدر
    // يوصله بعدين (مثل مجلد التنزيلات)، بدل حفظه بصمت داخل مساحة
    // التطبيق الخاصة غير المرئية له عبر مدير الملفات.
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر مكان حفظ الفاتورة',
      fileName: 'فاتورة_${inv.docNumber}.pdf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputPath == null) return; // ألغى المستخدم
    _snack('تم حفظ PDF بنجاح');
  }

  Future<void> _previewInvoice() async {
    final inv = await _finalizedForOutput();
    if (inv == null) return;
    final app = context.read<AppProvider>();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: _isReturn ? 'فاتورة مرتجع' : 'فاتورة بيع',
          shareFileName: 'فاتورة_${inv.docNumber}.pdf',
          buildPdf: () => PdfService.instance.generateInvoicePdf(inv, app.settings),
        ),
      ),
    );
  }

  Future<void> _sharePdf() async {
    final inv = await _finalizedForOutput();
    if (inv == null) return;
    final app = context.read<AppProvider>();
    final bytes = await PdfService.instance.generateInvoicePdf(inv, app.settings);
    await ShareUtil.shareBytes(bytes, 'فاتورة_${inv.docNumber}.pdf',
        text: 'فاتورة ${inv.docNumber}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final title = _isReturn ? 'فاتورة مرتجع' : 'فاتورة بيع';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // التاريخ ورقم الفاتورة (قابلان للتعديل)
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
                        decoration: const InputDecoration(labelText: 'رقم الفاتورة'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // نقد / آجل
                SegmentedButton<PaymentMode>(
                  segments: const [
                    ButtonSegment(
                        value: PaymentMode.cash,
                        label: Text('نقدًا'),
                        icon: Icon(Icons.money)),
                    ButtonSegment(
                        value: PaymentMode.credit,
                        label: Text('آجل'),
                        icon: Icon(Icons.schedule)),
                  ],
                  selected: {_paymentMode},
                  onSelectionChanged: (s) => setState(() => _paymentMode = s.first),
                ),
                const SizedBox(height: 16),

                // اختيار العميل
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

                // إضافة المنتجات (بطاقات كبيرة)
                Text('المنتجات', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                  children: app.products
                      .map((p) => BigCard(
                            icon: Icons.inventory_2,
                            title: p.name,
                            subtitle: Formatters.money(p.price),
                            selected: _items.containsKey(p.id),
                            onTap: () => _addProduct(p),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),

                // قائمة الأصناف المختارة
                if (_items.isNotEmpty) ...[
                  Text('الأصناف المختارة',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._items.values.map((it) => Card(
                        child: ListTile(
                          title: Text(it.productName),
                          subtitle: Text(
                              '${Formatters.money(it.price)}  ×  ${it.quantity} = ${Formatters.money(it.total)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QuantitySelector(
                                quantity: it.quantity,
                                min: 1,
                                onChanged: (v) {
                                  setState(() => it.quantity = v);
                                  _recalcBalance();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  setState(() => _items.remove(it.productId));
                                  _recalcBalance();
                                },
                              ),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 10),
                ],

                // الخصم
                Text('الخصم (اختياري)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _discountPercentCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'نسبة % '),
                        onChanged: (_) => _recalcBalance(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _discountAmountCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'مبلغ ثابت'),
                        onChanged: (_) => _recalcBalance(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ملاحظات
                TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                const SizedBox(height: 18),

                // توقيع العميل
                SignaturePadWidget(
                  label: 'توقيع العميل',
                  existingPath: _signaturePath,
                  onSaved: (path) => setState(() => _signaturePath = path),
                ),
                const SizedBox(height: 18),

                // الإجماليات + المديونية
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        _totalRow('الإجمالي الفرعي', Formatters.money(_subTotal)),
                        _totalRow('الخصم', Formatters.money(_discountValue)),
                        const Divider(),
                        _totalRow('الإجمالي النهائي', Formatters.money(_grandTotal),
                            bold: true),
                        const Divider(),
                        _totalRow('رصيد المديونية المتوقع بعد الحفظ',
                            Formatters.money(_previewBalance),
                            bold: true),
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
                  label: const Text('معاينة الفاتورة'),
                  onPressed: _previewInvoice,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print),
                        label: const Text('طباعة 80مم'),
                        onPressed: _printInvoice,
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

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  fontSize: bold ? 16 : 14)),
        ],
      ),
    );
  }
}

class _CustomerPickerSheet extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerPickerSheet({required this.customers});

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                  labelText: 'بحث عن عميل', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.builder(
                controller: controller,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.3,
                ),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final c = filtered[i];
                  return BigCard(
                    icon: Icons.person,
                    title: c.name,
                    subtitle: c.phone,
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
