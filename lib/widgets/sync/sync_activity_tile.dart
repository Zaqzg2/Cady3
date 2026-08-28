import 'package:flutter/material.dart';

/// عنصر واحد بقائمة "النشاط الأخير": وقت، أيقونة ملوّنة، عنوان وعنوان
/// فرعي، وشارة حالة صغيرة. نفس الشكل بشاشتَي المندوب والمدير — كل طرف
/// يبني قائمته من مصدر بياناته الحقيقي الخاص (الصادر/الوارد عند المندوب،
/// سجلّي الاستيراد والتصدير عند المدير)
class SyncActivityTile extends StatelessWidget {
  final String time;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;

  const SyncActivityTile({
    super.key,
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              time,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(shape: BoxShape.circle, color: iconColor.withOpacity(0.12)),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              badgeText,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: badgeColor),
            ),
          ),
        ],
      ),
    );
  }
}
