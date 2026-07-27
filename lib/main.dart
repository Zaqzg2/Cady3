import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/products_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/lock_screen.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const CadySalesApp());
}

class CadySalesApp extends StatelessWidget {
  const CadySalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..init(),
      child: Consumer<AppProvider>(
        builder: (context, app, _) {
          return MaterialApp(
            title: 'كادي للمنظفات',
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: app.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
            home: app.loading
                ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                : const AppGate(),
          );
        },
      ),
    );
  }
}

/// يتحقق من وجود كلمة مرور مفعّلة قبل عرض التطبيق
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool? _needsUnlock;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final set = await AuthService.instance.isPasswordSet();
    if (mounted) setState(() => _needsUnlock = set);
  }

  @override
  Widget build(BuildContext context) {
    if (_needsUnlock == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_needsUnlock == true) {
      return LockScreen(onUnlocked: () => setState(() => _needsUnlock = false));
    }
    return const RootNav();
  }
}

/// شريط التنقل السفلي: الرئيسية / العملاء / المنتجات / التقارير
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  final _pages = const [
    HomeScreen(),
    CustomersScreen(),
    ProductsScreen(),
    ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.people), label: 'العملاء'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'المنتجات'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'التقارير'),
        ],
      ),
    );
  }
}
