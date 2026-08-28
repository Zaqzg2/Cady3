import 'package:flutter/material.dart';

/// قسم مُجمّع من صفوف الإعدادات (بطاقة بحواف دائرية تحوي عدة أسطر)،
/// بنفس نمط شاشات الإعدادات الرسمية بأنظمة iOS/Android
class SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SettingsSection({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 6),
              child: Text(title!,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
            ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1)
                    Divider(height: 1, indent: 56, color: Colors.grey.shade200),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// سطر إعداد واحد: أيقونة دائرية ملوّنة + عنوان + سطر فرعي يلخّص الحالة +
/// سهم (أو أي عنصر Trailing آخر مثل Switch)
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  const SettingsTile({
    super.key,
    required this.icon,
    this.iconColor = Colors.blueGrey,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14.5)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
          : null,
      trailing: trailing ??
          (showChevron && onTap != null
              ? Icon(Icons.chevron_left, color: Colors.grey.shade400)
              : null),
    );
  }
}
