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

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.isEmpty) {
      widget.onSaved(null);
      return;
    }
    final data = await _controller.toPngBytes();
    if (data == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data);
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
          child: Signature(
            controller: _controller,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
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
