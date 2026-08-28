import 'package:flutter/material.dart';

import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';

/// صفّ نسخة احتياطية واحدة بالمعاينة المختصرة على شاشتَي المزامنة —
/// مشاركة واستعادة فقط، بلا حذف؛ الحذف يبقى حصرًا داخل شاشة "إدارة النسخ
/// الاحتياطية" الكاملة حتى لا يُحذف شيء بالخطأ من شاشة سريعة
class BackupPreviewCard extends StatelessWidget {
  final BackupRecord record;
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onRestore;

  const BackupPreviewCard({
    super.key,
    required this.record,
    required this.busy,
    required this.onShare,
    required this.onRestore,
  });

  String _when(DateTime d) {
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'اليوم $time';
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday =
        d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
    if (wasYesterday) return 'أمس $time';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppTheme.syncPendingSoft,
              child: Icon(Icons.archive_outlined, color: AppTheme.syncPending, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_when(record.createdAt),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(record.formattedSize,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 19),
              tooltip: 'مشاركة',
              onPressed: busy ? null : onShare,
            ),
            IconButton(
              icon: const Icon(Icons.restore, size: 19),
              tooltip: 'استعادة',
              onPressed: busy ? null : onRestore,
            ),
          ],
        ),
      ),
    );
  }
}
