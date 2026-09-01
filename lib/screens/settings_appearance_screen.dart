import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company_settings.dart';
import '../providers/app_provider.dart';

/// المظهر: الوضع الليلي (تلقائي/فاتح/داكن)، حجم خط واجهة التطبيق، اهتزاز
/// وصوت عند الحفظ، ولون الهوية الرئيسي للتطبيق
class SettingsAppearanceScreen extends StatefulWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  State<SettingsAppearanceScreen> createState() => _SettingsAppearanceScreenState();
}

class _SettingsAppearanceScreenState extends State<SettingsAppearanceScreen> {
  Future<void> _update(void Function(CompanySettings s) mutate) async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    mutate(s);
    await app.saveSettings(s);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppProvider>().settings;
    return Scaffold(
      appBar: AppBar(title: const Text('المظهر')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('الوضع الليلي', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(value: AppThemeMode.system, label: Text('تلقائي')),
              ButtonSegment(value: AppThemeMode.light, label: Text('فاتح')),
              ButtonSegment(value: AppThemeMode.dark, label: Text('داكن')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => _update((s) => s.themeMode = v.first),
          ),
          const Divider(height: 32),

          Text('حجم خط واجهة التطبيق: ${(s.appFontScale * 100).toStringAsFixed(0)}٪',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('لا يغيّر حجم خط الفاتورة أو السند',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          Slider(
            value: s.appFontScale,
            min: 0.85,
            max: 1.3,
            divisions: 9,
            label: '${(s.appFontScale * 100).toStringAsFixed(0)}٪',
            onChanged: (v) => _update((s) => s.appFontScale = v),
          ),
          const Divider(height: 32),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('اهتزاز عند الحفظ الناجح'),
            value: s.hapticOnSave,
            onChanged: (v) => _update((s) => s.hapticOnSave = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('صوت تنبيه عند حفظ فاتورة/سند'),
            value: s.soundOnSave,
            onChanged: (v) => _update((s) => s.soundOnSave = v),
          ),
          const Divider(height: 32),

          const Text('لون الهوية الرئيسي', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('يُطبَّق فورًا على أزرار وعناصر التطبيق',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kBrandColorPalette.map((c) {
              final selected = c.value == s.themeColorValue;
              return InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _update((s) => s.themeColorValue = c.value),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: selected ? Border.all(color: Colors.black87, width: 2.5) : null,
                  ),
                  child: selected ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
