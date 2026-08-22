import 'package:flutter/material.dart';

/// إجراء واحد يظهر في القائمة السفلية عند الضغط المطوّل على بطاقة القناة
class SyncQuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const SyncQuickAction(
      {required this.icon, required this.label, required this.onPressed});
}

/// بطاقة صغيرة تمثّل قناة مزامنة واحدة (فايربيس أو يدوي). الضغط العادي
/// يعرض شرحًا سريعًا لما تفعله القناة، والضغط المطوّل يفتح قائمة
/// الإجراءات السريعة الخاصة بها — بدل إخفاء كل الإجراءات خلف ملاحة كاملة
class SyncChannelCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String line1;
  final String? line2;
  final Color? dotColor;
  final String infoText;
  final List<SyncQuickAction> quickActions;

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
  });

  void _showInfo(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(infoText), duration: const Duration(seconds: 4)),
    );
  }

  void _showQuickActions(BuildContext context) {
    if (quickActions.isEmpty) {
      _showInfo(context);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).dividerColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(title,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
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
            const SizedBox(height: 6),
          ],
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
        onTap: () => _showInfo(context),
        onLongPress: () => _showQuickActions(context),
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
                    ),
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
