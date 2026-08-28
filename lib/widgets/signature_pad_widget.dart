import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:signature/signature.dart';

import '../services/image_store.dart';

/// منطقة توقيع بارزة باللمس (تُستخدم لتوقيع العميل في الفاتورة، وتوقيع
/// المندوب في سند القبض). تحفظ الناتج داخل ImageStore (يعمل على الجوال
/// والويب معًا) وتُرجع مفتاحه.
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
  final _boundaryKey = GlobalKey();
  // إذا كان هناك توقيع محفوظ مسبقًا (تعديل فاتورة قديمة)، نعرضه كصورة
  // ثابتة بدل لوحة رسم فاضية، حتى لا يُعتبر "فاضياً" ويُمسح بالخطأ عند
  // الحفظ دون رسم توقيع جديد. المستخدم يقدر يضغط "إعادة التوقيع" إذا
  // يريد تغييره فعليًا.
  bool _showingExistingImage = false;
  bool _loadingExisting = false;
  String? _existingKey;
  Uint8List? _existingBytes;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 4,
      penColor: Colors.black,
      // يحفظ التوقيع تلقائيًا فور رفع الإصبع بعد كل خط، بدون الحاجة لزر
      // "اعتماد التوقيع" — كل خط جديد يستبدل الحفظة السابقة بنفس المفتاح
      // (_save تتعامل مع هذا عبر ImageStore.save(key: _existingKey))، وينتهي
      // الأمر بحفظ التوقيع الكامل تلقائيًا بعد آخر خط يرسمه المستخدم.
      onDrawEnd: _save,
    );
    _existingKey = widget.existingPath;
    if (_existingKey != null) {
      _showingExistingImage = true;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    final bytes = await ImageStore.instance.load(_existingKey);
    if (!mounted) return;
    setState(() {
      _existingBytes = bytes;
      _showingExistingImage = bytes != null;
      _loadingExisting = false;
    });
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
      widget.onSaved(_existingKey);
      return;
    }
    // ملاحظة مهمة حول جودة الصورة: SignatureController.toPngBytes() يُصدّر
    // بأبعاد صندوق الخطوط المرسومة بالبكسل المنطقي (logical pixels) فقط،
    // وليس بكثافة بكسلات الجهاز الفعلية — فتخرج صورة منخفضة الدقة تُعرض
    // لاحقًا مكبَّرة داخل نفس الصندوق، فتظهر عريضة ومُبكسلة (هذا بالضبط ما
    // كان يظهر). لذلك نلتقط الصورة مباشرة من الشاشة عبر RepaintBoundary
    // بنفس كثافة بكسلات الجهاز — يطابق تمامًا ما يُرسم حيًا، بدقة كاملة.
    await WidgetsBinding.instance.endOfFrame; // نضمن اكتمال رسم آخر خط أولاً
    if (!mounted) return;
    final boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: dpr);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return;
    final data = byteData.buffer.asUint8List();
    final key = await ImageStore.instance.save(data, key: _existingKey);
    _existingKey = key;
    _existingBytes = data;
    widget.onSaved(key);
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
                _existingKey = null;
                _existingBytes = null;
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
          child: _loadingExisting
              ? const Center(child: CircularProgressIndicator())
              : (_showingExistingImage && _existingBytes != null)
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: Image.memory(_existingBytes!, fit: BoxFit.contain),
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
                  : RepaintBoundary(
                      key: _boundaryKey,
                      child: Signature(
                        controller: _controller,
                        backgroundColor: Colors.white,
                      ),
                    ),
        ),
      ],
    );
  }
}
