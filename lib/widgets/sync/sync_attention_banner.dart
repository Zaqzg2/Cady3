import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// بطاقة تنبيه تظهر فقط عند وجود سبب حقيقي — الشاشة المستدعية تقرّر
/// الشرط (خطأ فعلي، عمليات معلّقة فعلية...) وتبني هذا الودجت أو لا
/// تبنيه أصلًا؛ لا توجد هنا حالة افتراضية "دائمًا ظاهرة"
class SyncAttentionBanner extends StatelessWidget {
  final String title;
  final List<String> lines;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const SyncAttentionBanner({
    super.key,
    required this.title,
    required this.lines,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.syncPendingSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.syncPending.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: AppTheme.syncPending, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 4),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '•  $l',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800, height: 1.5),
                    ),
                  ),
                if (ctaLabel != null && onCta != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: onCta,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(ctaLabel!,
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            )),
                        const Icon(Icons.chevron_left, size: 16, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
