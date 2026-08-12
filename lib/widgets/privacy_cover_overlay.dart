import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import 'stored_image.dart';

/// يُغطّي محتوى الشاشة بشعار/اسم الشركة عند انتقال التطبيق للخلفية أو
/// أثناء تبديل التطبيقات، حتى لا تظهر الأرقام المالية في صورة "التطبيقات
/// الأخيرة" (Recents) — يعمل فقط عندما يكون خيار "إخفاء الأرقام المالية"
/// مفعّلاً في إعدادات الخصوصية.
class PrivacyCoverOverlay extends StatefulWidget {
  final Widget child;
  const PrivacyCoverOverlay({super.key, required this.child});

  @override
  State<PrivacyCoverOverlay> createState() => _PrivacyCoverOverlayState();
}

class _PrivacyCoverOverlayState extends State<PrivacyCoverOverlay>
    with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = context.read<AppProvider>().settings.hideAmountsInRecents;
    if (!enabled) {
      if (_covered) setState(() => _covered = false);
      return;
    }
    final shouldCover = state != AppLifecycleState.resumed;
    if (shouldCover != _covered) setState(() => _covered = shouldCover);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppProvider>().settings;
    return Stack(
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s.logoPath != null)
                        StoredAvatar(
                            imageKey: s.logoPath,
                            radius: 40,
                            placeholderIcon: Icons.storefront)
                      else
                        Icon(Icons.storefront,
                            size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(s.companyName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
