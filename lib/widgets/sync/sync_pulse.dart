import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// حالة حلقة النبض المعروضة على الشاشة — طبقة عرض منفصلة عن SyncStatus في
/// الموديل، لأنها تشمل حالتين انتقاليتين (جارٍ/فشل) لا تُخزَّن في قاعدة
/// البيانات أصلًا، فقط تعكسان ما يجري حاليًا في الشاشة
enum SyncPulseState { synced, pending, syncing, failed }

/// الحلقة المتحركة التي تلخّص حالة المزامنة بلمحة: هادئة ونابضة ببطء وهي
/// متزامنة، ثابتة بالذهبي وهي معلّقة مع عدد العمليات، حلقة تقدّم حقيقية
/// بالنسبة المئوية أثناء التنفيذ، وثابتة بالأحمر عند الفشل
class SyncPulse extends StatefulWidget {
  final SyncPulseState state;
  // null = مزامنة جارية بدون نسبة معروفة (مؤشر غير محدد) — لا نعرض رقمًا
  // وهميًا إن لم يكن لدينا تقدّم حقيقي من العملية نفسها
  final double? progress;
  final String? centerLabel; // نص العدّ في حالة pending (مثال: "12")
  final String pendingCaption; // النص أسفل centerLabel، قابل للتخصيص
  final double size;

  const SyncPulse({
    super.key,
    required this.state,
    this.progress,
    this.centerLabel,
    this.pendingCaption = 'معلّق',
    this.size = 104,
  });

  @override
  State<SyncPulse> createState() => _SyncPulseState();
}

class _SyncPulseState extends State<SyncPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.state) {
      case SyncPulseState.synced:
      case SyncPulseState.syncing:
        return AppTheme.syncSuccess;
      case SyncPulseState.pending:
        return AppTheme.syncPending;
      case SyncPulseState.failed:
        return AppTheme.syncError;
    }
  }

  Color get _soft {
    switch (widget.state) {
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final innerSize = widget.size - 16;

    Widget inner = Container(
      width: innerSize,
      height: innerSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _soft),
      child: _buildCenter(),
    );

    if (widget.state == SyncPulseState.synced && !reduceMotion) {
      inner = AnimatedBuilder(
        animation: _breathe,
        builder: (context, child) {
          final scale = 1.0 + (_breathe.value * 0.045);
          return Transform.scale(scale: scale, child: child);
        },
        child: inner,
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.state == SyncPulseState.syncing)
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                value: widget.progress,
                strokeWidth: 4,
                backgroundColor: _color.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation<Color>(_color),
              ),
            )
          else
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _color.withOpacity(0.16), width: 3),
              ),
            ),
          inner,
        ],
      ),
    );
  }

  Widget _buildCenter() {
    switch (widget.state) {
      case SyncPulseState.synced:
        return Icon(Icons.check_circle_rounded,
            color: _color, size: widget.size * 0.32);
      case SyncPulseState.pending:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.centerLabel ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: widget.size * 0.24,
                fontWeight: FontWeight.w800,
                color: _color,
              ),
            ),
            Text(
              widget.pendingCaption,
              style: TextStyle(
                fontSize: widget.size * 0.095,
                fontWeight: FontWeight.bold,
                color: _color,
              ),
            ),
          ],
        );
      case SyncPulseState.syncing:
        if (widget.progress == null) {
          return Icon(Icons.sync_rounded, color: _color, size: widget.size * 0.3);
        }
        final pct = (widget.progress! * 100).clamp(0, 100).round();
        return Text(
          '$pct%',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: widget.size * 0.2,
            fontWeight: FontWeight.w800,
            color: _color,
          ),
        );
      case SyncPulseState.failed:
        return Icon(Icons.priority_high_rounded,
            color: _color, size: widget.size * 0.32);
    }
  }
}
