import 'package:flutter/material.dart';

/// إجراء واحد يظهر بالقائمة السفلية لبطاقة القناة
class SyncQuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const SyncQuickAction(
      {required this.icon, required this.label, required this.onPressed});
}

/// بطاقة صغيرة تمثّل قناة مزامنة واحدة (فايربيس أو يدوي). ضغطة واحدة
/// عادية — بدون اعتماد على ضغط مطوّل قد لا يُلتقط بموثوقية على كل جهاز
/// أو متصفّح — تفتح لوحة سفلية واضحة فيها الشرح ثم الإجراءات، بدل
/// SnackBar خافت يسهل تفويته
class SyncChannelCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String line1;
  final String? line2;
  final Color? dotColor;
  final String infoText;
  final List<SyncQuickAction> quickActions;
  // لو مررت onTap صراحةً (مثال: فتح شاشة الصادر/الوارد مباشرة) تُستخدم
  // بدل اللوحة الافتراضية — لأي بطاقة تحتاج فتح شاشة كاملة مباشرة
  final VoidCallback? onTap;

  const SyncChannelCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.line1,
    this.line2,
    this.dotColor,
    required this.infoText,
    this.quickActions = const [],
    this.onTap,
  });

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).dividerColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Icon(icon, color: iconColor, size: 20),
                    const SizedBox(width: 8),
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                child: Text(
                  infoText,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.6),
                ),
              ),
              if (quickActions.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                  child: Divider(height: 1),
                ),
                for (final action in quickActions)
                  ListTile(
                    leading: Icon(action.icon),
                    title: Text(action.label),
                    onTap: () {
                      Navigator.pop(ctx);
                      action.onPressed();
                    },
                  ),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ?? () => _showSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  if (dotColor != null)
                    Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: dotColor),
                    )
                  else
                    Icon(Icons.chevron_left, size: 16, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(line1,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              if (line2 != null)
                Text(line2!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
