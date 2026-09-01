import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// شاشة معاينة PDF عامة قابلة لإعادة الاستخدام (للفواتير، السندات، وكشف
/// الحساب). تستخدم widget جاهز من حزمة printing يوفر تكبير/تصغير وطباعة
/// ومشاركة مباشرة من نفس شاشة المعاينة.
class PdfPreviewScreen extends StatelessWidget {
  final String title;
  final Future<Uint8List> Function() buildPdf;
  final String shareFileName;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.buildPdf,
    required this.shareFileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('معاينة: $title')),
      body: PdfPreview(
        build: (format) => buildPdf(),
        allowPrinting: true,
        allowSharing: true,
        canDebug: false,
        pdfFileName: shareFileName,
        initialPageFormat: null,
      ),
    );
  }
}
