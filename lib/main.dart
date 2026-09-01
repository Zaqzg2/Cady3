import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_paddle_ocr/flutter_paddle_ocr.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const ProtoApp());
}

class ProtoApp extends StatelessWidget {
  const ProtoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaddleOCR عربي — اختبار Prototype',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0F6B5C)),
      home: const OcrTestPage(),
    );
  }
}

class OcrTestPage extends StatefulWidget {
  const OcrTestPage({super.key});

  @override
  State<OcrTestPage> createState() => _OcrTestPageState();
}

class _OcrTestPageState extends State<OcrTestPage> {
  PaddleOcr? _ocr;
  bool _initializing = true;
  String? _initError;
  bool _recognizing = false;
  String? _recognizeError;
  List<dynamic> _results = [];
  Uint8List? _pickedBytes;
  Duration? _lastDuration;

  @override
  void initState() {
    super.initState();
    _initOcr();
  }

  Future<void> _initOcr() async {
    if (!kIsWeb) {
      setState(() {
        _initializing = false;
        _initError =
            'هذا الـ Prototype يستهدف الويب فقط حاليًا (flutter run -d chrome) — '
            'لأن نموذج PP-OCRv5 العربي غير متاح بصيغة .nb على الجوال بعد. راجع README.';
      });
      return;
    }
    try {
      // ⚠️ lang: 'ar' مبنيّ على مطابقة موثَّقة لقواعد تسمية PaddleOCR (نفس
      // القيمة المستخدَمة في مكتبة Python الرسمية)، وليس تجربة مباشرة من
      // مصدر الحزمة نفسها — هذا أول سطر يستحق التحقق يدويًا إن فشلت التهيئة.
      final ocr = await PaddleOcr.create(
        source: const ModelSource.bundled(lang: 'ar', version: 'PP-OCRv5'),
      );
      setState(() {
        _ocr = ocr;
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _initializing = false;
        _initError = 'فشلت تهيئة محرك OCR: $e';
      });
    }
  }

  Future<void> _pickAndRecognize() async {
    if (_ocr == null) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    setState(() {
      _pickedBytes = bytes;
      _recognizing = true;
      _recognizeError = null;
      _results = [];
    });

    final stopwatch = Stopwatch()..start();
    try {
      final results = await _ocr!.recognize(bytes, runClassification: !kIsWeb);
      stopwatch.stop();
      setState(() {
        _results = results;
        _lastDuration = stopwatch.elapsed;
      });
    } catch (e) {
      setState(() => _recognizeError = 'فشل التعرّف: $e');
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  @override
  void dispose() {
    _ocr?.dispose(); // dispose() في State متزامنة؛ لا يمكن انتظارها هنا
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PaddleOCR عربي — اختبار Prototype')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_initializing) const LinearProgressIndicator(),
            if (_initError != null)
              Card(
                color: const Color(0x1AFF0000),
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_initError!)),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (_ocr == null || _recognizing) ? null : _pickAndRecognize,
              icon: const Icon(Icons.image_search_rounded),
              label: Text(_recognizing ? 'جارٍ التعرّف...' : 'اختر صورة كشف حقيقي وجرّب'),
            ),
            if (_lastDuration != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('زمن التعرّف: ${_lastDuration!.inMilliseconds} مللي ثانية',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            if (_recognizeError != null)
              Card(
                color: const Color(0x1AFF0000),
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_recognizeError!)),
              ),
            const SizedBox(height: 12),
            if (_pickedBytes != null)
              SizedBox(height: 180, child: Image.memory(_pickedBytes!, fit: BoxFit.contain)),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('النتائج ستظهر هنا بعد اختيار صورة.'))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = _results[i];
                        // بنية النتيجة (.text / .confidence / .points) موثَّقة في
                        // صفحة الحزمة على pub.dev. إن اختلفت التسمية الفعلية بعد
                        // أول تجربة حقيقية، هذا أول سطر يحتاج تعديلًا — التقاط
                        // الخطأ هنا فقط لإظهار قيمة خام بدل انهيار الشاشة.
                        String text;
                        String confidence;
                        try {
                          text = (r.text ?? '?').toString();
                          confidence = (r.confidence as num?)?.toStringAsFixed(2) ?? '?';
                        } catch (_) {
                          text = r.toString();
                          confidence = '?';
                        }
                        return ListTile(
                          dense: true,
                          title: Text(text, textDirection: TextDirection.rtl),
                          trailing: Text(confidence),
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
