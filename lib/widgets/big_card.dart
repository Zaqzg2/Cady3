import 'package:flutter/material.dart';

/// بطاقة كبيرة قابلة للمس تُستخدم في الشاشة الرئيسية، واختيار العميل،
/// واختيار المنتج
class BigCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;
  final bool selected;

  const BigCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.primaryContainer;
    return Card(
      color: selected ? scheme.primary.withOpacity(0.15) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: bg,
                child: Icon(icon, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
