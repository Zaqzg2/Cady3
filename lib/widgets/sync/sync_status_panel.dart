import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum _Phase { preparing, running, done, failed }

enum _StepState { pending, active, done, failed }

/// لوحة حالة تُعرض كـ bottom sheet أثناء تنفيذ عملية مزامنة (إرسال،
/// استيراد، سحب من فايربيس...) بدل الاكتفاء بـ SnackBar صغيرة أسفل
/// الشاشة. تعرض 3 أطوار حقيقية فقط: تجهيز، تنفيذ (وهو الانتظار الفعلي
/// لنتيجة [action])، ثم النتيجة — بلا أي تأخير مصطنع أو خطوات وهمية
/// لغرض العرض فقط. مغلقة أثناء التنفيذ (isDismissible: false) حتى لا
/// يُطلق المستخدم نفس العملية مرتين بالخطأ
class SyncStatusPanel extends StatefulWidget {
  final String title;
  final String runningLabel;
  final Future<String> Function() action;

  const SyncStatusPanel({
    super.key,
    required this.title,
    required this.runningLabel,
    required this.action,
  });

  @override
  State<SyncStatusPanel> createState() => _SyncStatusPanelState();
}

class _SyncStatusPanelState extends State<SyncStatusPanel> {
  _Phase _phase = _Phase.preparing;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.preparing;
      _error = null;
    });
    // يسمح لطور "التجهيز" بالرسم فعليًا قبل بدء التنفيذ، دون أي تأخير مصطنع إضافي
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    setState(() => _phase = _Phase.running);
    try {
      final result = await widget.action();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 22),
            _StepRow(
              label: 'تجهيز البيانات',
              state: _phase == _Phase.preparing ? _StepState.active : _StepState.done,
            ),
            _StepRow(
              label: widget.runningLabel,
              state: _phase == _Phase.preparing
                  ? _StepState.pending
                  : (_phase == _Phase.running
                      ? _StepState.active
                      : (_phase == _Phase.failed ? _StepState.failed : _StepState.done)),
            ),
            _StepRow(
              label: _phase == _Phase.failed ? 'حدث خطأ' : 'اكتملت العملية',
              state: _phase == _Phase.done
                  ? _StepState.done
                  : (_phase == _Phase.failed ? _StepState.failed : _StepState.pending),
              isLast: true,
            ),
            const SizedBox(height: 14),
            if (_phase == _Phase.done) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.syncSuccessSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.syncSuccess, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_result ?? 'تمت العملية بنجاح',
                            style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تم'),
              ),
            ] else if (_phase == _Phase.failed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.syncErrorSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error, color: AppTheme.syncError, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error ?? 'حدث خطأ غير متوقع',
                            style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إغلاق'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _run,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              ),
            ] else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final _StepState state;
  final bool isLast;
  const _StepRow({required this.label, required this.state, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    late final Widget icon;
    late final Color color;
    switch (state) {
      case _StepState.done:
        color = AppTheme.syncSuccess;
        icon = Icon(Icons.check_circle, color: color, size: 20);
        break;
      case _StepState.active:
        color = AppTheme.primary;
        icon = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
        );
        break;
      case _StepState.failed:
        color = AppTheme.syncError;
        icon = Icon(Icons.cancel, color: color, size: 20);
        break;
      case _StepState.pending:
        color = Colors.grey.shade400;
        icon = Icon(Icons.radio_button_unchecked, color: color, size: 20);
        break;
    }
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        children: [
          SizedBox(width: 22, child: Center(child: icon)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: state == _StepState.active ? FontWeight.bold : FontWeight.normal,
              color: state == _StepState.pending ? Colors.grey.shade500 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// يعرض [SyncStatusPanel] كـ bottom sheet وينفّذ [action] فعليًا. يعيد
/// true لو ضغط المستخدم "تم" بعد نجاح العملية، و false لو ضغط "إغلاق"
/// بعد فشلها (null لا يحدث عمليًا لأن الطيّ بالسحب معطّل)
Future<bool?> showSyncStatusPanel(
  BuildContext context, {
  required String title,
  required String runningLabel,
  required Future<String> Function() action,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SyncStatusPanel(title: title, runningLabel: runningLabel, action: action),
  );
}
