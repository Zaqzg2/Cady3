import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../models/company_settings.dart';
import '../models/user_account.dart';
import '../services/auth_service.dart';
import '../widgets/settings_tile.dart';
import 'settings_company_screen.dart';
import 'settings_printing_screen.dart';
import 'settings_appearance_screen.dart';
import 'settings_privacy_screen.dart';
import 'settings_data_screen.dart';
import 'sync_screen.dart';

/// الشاشة الرئيسية للإعدادات — قائمة أقسام بنمط iOS/Android الرسمي:
/// كل قسم سطر واحد بأيقونة + عنوان + سطر فرعي يلخّص الحالة + سهم يفتح
/// شاشة مستقلة كاملة لذلك القسم فقط
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _passwordEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    final set = await AuthService.instance.isPasswordSet();
    if (mounted) setState(() => _passwordEnabled = set);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadAuthState();
    if (mounted) setState(() {});
  }

  Future<void> _confirmLogout(BuildContext context, AppProvider app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من هذا الحساب؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تسجيل الخروج')),
        ],
      ),
    );
    if (confirmed == true) await app.logout();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final s = app.settings;

    final companySubtitle = s.companyName.trim().isEmpty
        ? 'أضف بيانات شركتك ومندوبك'
        : '${s.companyName}${s.repName.isNotEmpty ? ' • ${s.repName}' : ''}';

    final printerSubtitle = s.printerAddress != null
        ? 'الطابعة: ${s.printerName ?? 'غير معروفة'} متصلة'
        : 'لا توجد طابعة متصلة';

    final appearanceSubtitle = switch (s.themeMode) {
      AppThemeMode.system => 'تلقائي حسب النظام',
      AppThemeMode.dark => 'داكن دائمًا',
      AppThemeMode.light => 'فاتح دائمًا',
    };

    final privacySubtitle = _passwordEnabled ? 'محمي بكلمة مرور' : 'بدون حماية';

    final backupSubtitle = switch (s.autoBackupFrequency) {
      AutoBackupFrequency.daily => 'نسخ تلقائي يومي',
      AutoBackupFrequency.weekly => 'نسخ تلقائي أسبوعي',
      AutoBackupFrequency.off => 'النسخ الاحتياطي والبيانات',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSection(
            children: [
              SettingsTile(
                icon: Icons.account_circle_outlined,
                iconColor: Colors.brown,
                title: app.currentUser?.displayName ?? 'الحساب',
                subtitle: app.currentUser?.role == UserRole.manager
                    ? 'مدير • تسجيل الخروج'
                    : 'مندوب • تسجيل الخروج',
                onTap: () => _confirmLogout(context, app),
              ),
              SettingsTile(
                icon: Icons.store_outlined,
                iconColor: Colors.teal,
                title: 'بيانات الشركة والمندوب',
                subtitle: companySubtitle,
                onTap: () => _open(const SettingsCompanyScreen()),
              ),
              SettingsTile(
                icon: Icons.print_outlined,
                iconColor: Colors.indigo,
                title: 'الطباعة والفاتورة',
                subtitle: printerSubtitle,
                onTap: () => _open(const SettingsPrintingScreen()),
              ),
              SettingsTile(
                icon: Icons.palette_outlined,
                iconColor: Colors.deepOrange,
                title: 'المظهر',
                subtitle: appearanceSubtitle,
                onTap: () => _open(const SettingsAppearanceScreen()),
              ),
              SettingsTile(
                icon: Icons.lock_outline,
                iconColor: Colors.blueGrey,
                title: 'الخصوصية والأمان',
                subtitle: privacySubtitle,
                onTap: () => _open(const SettingsPrivacyScreen()),
              ),
              SettingsTile(
                icon: Icons.sync_outlined,
                iconColor: Colors.orange,
                title: 'المزامنة',
                subtitle: app.currentUser?.lastSyncAt != null
                    ? 'آخر مزامنة مسجّلة'
                    : 'لم تتم أي مزامنة بعد',
                onTap: () => _open(const SyncScreen()),
              ),
              SettingsTile(
                icon: Icons.backup_outlined,
                iconColor: Colors.green,
                title: 'البيانات والنسخ الاحتياطي',
                subtitle: backupSubtitle,
                onTap: () => _open(const SettingsDataScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
