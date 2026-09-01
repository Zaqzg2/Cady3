import 'package:flutter/material.dart';

/// عنوان قسم بسيط + إجراء اختياري بالطرف الآخر (عادة "عرض الكل") — نمط
/// موحّد بدل تكرار نفس الـ Row في كل قسم من أقسام شاشتَي المزامنة
class SyncSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SyncSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: Colors.grey.shade700),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          if (actionLabel != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(actionLabel!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        )),
                    Icon(Icons.chevron_left,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
