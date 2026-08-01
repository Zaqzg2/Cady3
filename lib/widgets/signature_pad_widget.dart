import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

/// منطقة توقيع بارزة باللمس (تُستخدم لتوقيع العميل في الفاتورة، وتوقيع
/// المندوب في سند القبض). تحفظ الناتج كصورة PNG محليًا وتُرجع مسارها.
class SignaturePadWidget extends StatefulWidget {
  final String label;
  final String? existingPath;
  final ValueChanged<String?> onSaved;

  const SignaturePadWidget({
    super.key,
    required this.label,
    required this.onSaved,
    this.existingPath,
  });

  @override
  State<SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<SignaturePadWidget> {
  late final SignatureController _controller;
  // إذا كان هناك توقيع محفوظ مسبقًا (تعديل فاتورة قديمة)، نعرضه كصورة
  // ثابتة بدل لوحة رسم فاضية، حتى لا يُعتبر "فاضياً" ويُمسح بالخطأ عند
  // الحفظ دون رسم توقيع جديد. المستخدم يقدر يضغط "إعادة التوقيع" إذا
  // يريد تغييره فعليًا.
  late bool _showingExistingImage;
  String? _existingPath;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _existingPath = widget.existingPath;
    _showingExistingImage =
        _existingPath != null && File(_existingPath!).existsSync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.isEmpty) {
      // لا نمسح توقيعًا محفوظًا مسبقًا لمجرد أن لوحة الرسم فاضية —
      // هذا يحصل فقط إذا لم يرسم المستخدم شيئًا جديدًا أصلاً.
      widget.onSaved(_existingPath);
      return;
    }
    final data = await _controller.toPngBytes();
    if (data == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data);
    _existingPath = file.path;
    widget.onSaved(file.path);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            TextButton.icon(
              onPressed: () {
                _controller.clear();
                setState(() => _showingExistingImage = false);
                _existingPath = null;
                widget.onSaved(null);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('مسح'),
            ),
          ],
        ),
        // منطقة التوقيع بارزة بإطار سميك وخلفية مميزة
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.orange, width: 2.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: _showingExistingImage
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: Image.file(File(_existingPath!), fit: BoxFit.contain),
                    ),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.orange.shade50,
                        ),
                        onPressed: () =>
                            setState(() => _showingExistingImage = false),
                        child: const Text('إعادة التوقيع'),
                      ),
                    ),
                  ],
                )
              : Signature(
                  controller: _controller,
                  backgroundColor: Colors.white,
                ),
        ),
        const SizedBox(height: 6),
        if (!_showingExistingImage)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _save,
              child: const Text('اعتماد التوقيع'),
            ),
          ),
      ],
    );
  }
}
