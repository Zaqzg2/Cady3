import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
  // نلتقط أي خطأ غير متوقّع في أي مكان بالتطبيق (بما فيه أخطاء غير متزامنة)
  // ونطبعه بوضوح في السجل (logcat) بدل ما يختفي بصمت ويترك المستخدم أمام
  // شاشة بيضاء بلا أي تفسير.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
      debugPrint('${details.stack}');
    };
    // افتراضياً، في نسخة release، أي خطأ أثناء بناء widget يظهر كمربع
    // رمادي فارغ بلا أي رسالة (لإخفاء التفاصيل التقنية عن المستخدم
    // النهائي). نتجاوز هذا مؤقتاً لعرض رسالة الخطأ الحقيقية على الشاشة
    // نفسها، لتسهيل التشخيص، بدل تخمين السبب من مربع رمادي بلا معنى.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // نستخرج فقط الأسطر المتعلقة بكود التطبيق نفسه (package:cady_sales_app)
      // من تتبّع الخطأ (stack trace)، ونتجاهل أسطر إطار عمل Flutter الداخلية
      // الطويلة، حتى تظهر رسالة قصيرة وواضحة تحدد الملف والسطر بالضبط.
      final stackLines = details.stack
              ?.toString()
              .split('\n')
              .where((l) => l.contains('package:cady_sales_app'))
              .take(4)
              .join('\n') ??
          '';
      return Container(
        color: Colors.red.shade50,
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Text(
            'خطأ في بناء الواجهة:\n${details.exceptionAsString()}\n\n$stackLines',
            style: const TextStyle(color: Colors.red, fontSize: 10),
          ),
        ),
      );
    };
    runApp(const CadySalesApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error');
    debugPrint('$stack');
  });
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
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: app.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
            home: app.loading
                ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                : app.initError != null
                    ? Scaffold(
                        body: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 56),
                                const SizedBox(height: 16),
                                const Text(
                                  'حدث خطأ أثناء بدء التطبيق',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  app.initError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () => app.init(),
                                  child: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final set = await AuthService.instance.isPasswordSet();
      if (mounted) setState(() => _needsUnlock = set);
    } catch (e) {
      debugPrint('AppGate._check() failed: $e');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('خطأ: $_error', textAlign: TextAlign.center),
          ),
        ),
      );
    }
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
