import 'package:flutter/material.dart';

import 'manager_dashboard_screen.dart';
import 'manager_users_screen.dart';
import 'manager_sync_hub_screen.dart';
import 'manager_live_activity_screen.dart';

/// شريط التنقل السفلي لوضع المدير: لوحة التحكم / المندوبون / المزامنة /
/// نشاط مباشر. التنقل بالضغط على الشريط، أو بالسحب يمين/يسار مباشرة
/// (PageView) بين الصفحات الأربع — نفس اتجاه القراءة بالتطبيق (RTL).
class ManagerRootNav extends StatefulWidget {
  const ManagerRootNav({super.key});

  @override
  State<ManagerRootNav> createState() => _ManagerRootNavState();
}

class _ManagerRootNavState extends State<ManagerRootNav> {
  int _index = 0;
  late final PageController _controller;

  static const _pages = [
    ManagerDashboardScreen(),
    ManagerUsersScreen(),
    ManagerSyncHubScreen(),
    ManagerLiveActivityScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    setState(() => _index = i);
    _controller.animateToPage(i,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'لوحة التحكم'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined), label: 'المندوبون'),
          NavigationDestination(
              icon: Icon(Icons.sync_outlined), label: 'المزامنة'),
          NavigationDestination(
              icon: Icon(Icons.cloud_sync_outlined), label: 'نشاط مباشر'),
        ],
      ),
    );
  }
}
