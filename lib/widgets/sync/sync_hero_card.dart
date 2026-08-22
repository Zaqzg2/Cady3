import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'sync_pulse.dart';

/// نوع الزر الرئيسي في البطاقة — يحدّد شكله بما يتناسب مع خطورة/أولوية
/// الإجراء الحالي (حلّ عاجل بالأحمر، إجراء موصى به فيروزي، فحص اختياري
/// ثانوي بالحدود فقط)
enum SyncHeroCta { none, ghost, solid, danger }

/// البطاقة الرئيسية أعلى شاشة المزامنة: تُجيب بلمحة على "هل بياناتي آمنة؟"
/// و"ماذا أفعل الآن؟" عبر عنصر واحد بدل عدة بطاقات متفرقة. اضغطة عادية
/// على البطاقة تفتح التفاصيل عبر [onTap]، والزر الرئيسي يبقى مستقلًا حتى
/// لا يتعارض الاثنان
class SyncHeroCard extends StatelessWidget {
  final SyncPulseState state;
  final double? progress;
  final String? centerLabel;
  final String pendingCaption;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final SyncHeroCta ctaKind;
  final VoidCallback? onCtaPressed;
  final VoidCallback? onTap;

  const SyncHeroCard({
    super.key,
    required this.state,
    this.progress,
    this.centerLabel,
    this.pendingCaption = 'معلّق',
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.ctaKind = SyncHeroCta.solid,
    this.onCtaPressed,
    this.onTap,
  });

  Color get _soft {
    switch (state) {
      case SyncPulseState.synced:
      case SyncPulseState.syncing:
        return AppTheme.syncSuccessSoft;
      case SyncPulseState.pending:
        return AppTheme.syncPendingSoft;
      case SyncPulseState.failed:
        return AppTheme.syncErrorSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_soft, theme.cardColor],
        ),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          SyncPulse(
            state: state,
            progress: progress,
            centerLabel: centerLabel,
            pendingCaption: pendingCaption,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodySmall?.color, height: 1.5),
          ),
          if (ctaLabel != null && ctaKind != SyncHeroCta.none) ...[
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: _buildCta(context)),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: card,
      ),
    );
  }

  Widget _buildCta(BuildContext context) {
    switch (ctaKind) {
      case SyncHeroCta.solid:
        return FilledButton(
          onPressed: onCtaPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.syncSuccess,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(ctaLabel!),
        );
      case SyncHeroCta.danger:
        return FilledButton(
          onPressed: onCtaPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.syncError,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(ctaLabel!),
        );
      case SyncHeroCta.ghost:
        return OutlinedButton(
          onPressed: onCtaPressed,
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(ctaLabel!),
        );
      case SyncHeroCta.none:
        return const SizedBox.shrink();
    }
  }
}
