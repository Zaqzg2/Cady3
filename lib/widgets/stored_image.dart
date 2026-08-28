import 'package:flutter/material.dart';

import '../services/image_store.dart';

/// دائرة صورة (Avatar) تُحمَّل من ImageStore بالمفتاح المُعطى، مع حالة
/// انتظار وحالة افتراضية عند عدم وجود صورة — تُستخدم لعرض شعار الشركة
/// في أكثر من مكان بدون تكرار منطق التحميل
class StoredAvatar extends StatelessWidget {
  final String? imageKey;
  final double radius;
  final IconData placeholderIcon;

  const StoredAvatar({
    super.key,
    required this.imageKey,
    this.radius = 30,
    this.placeholderIcon = Icons.image,
  });

  @override
  Widget build(BuildContext context) {
    if (imageKey == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade200,
        child: Icon(placeholderIcon, size: radius * 0.85),
      );
    }
    return FutureBuilder(
      future: ImageStore.instance.load(imageKey),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: Colors.grey.shade200,
            child: snapshot.connectionState == ConnectionState.waiting
                ? SizedBox(
                    width: radius * 0.7,
                    height: radius * 0.7,
                    child: const CircularProgressIndicator(strokeWidth: 2))
                : Icon(placeholderIcon, size: radius * 0.85),
          );
        }
        return CircleAvatar(
          radius: radius,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: MemoryImage(bytes),
        );
      },
    );
  }
}
