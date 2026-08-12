import 'package:flutter/material.dart';

import 'manager_dashboard_screen.dart';
import 'manager_users_screen.dart';
import 'manager_sync_hub_screen.dart';

/// شريط التنقل السفلي لوضع المدير: لوحة التحكم / المندوبون / المزامنة
class ManagerRootNav extends StatefulWidget {
  const ManagerRootNav({super.key});

  @override
  State<ManagerRootNav> createState() => _ManagerRootNavState();
}

class _ManagerRootNavState extends State<ManagerRootNav> {
  int _index = 0;

  final _pages = const [
    ManagerDashboardScreen(),
    ManagerUsersScreen(),
    ManagerSyncHubScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'لوحة التحكم'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined), label: 'المندوبون'),
          NavigationDestination(
              icon: Icon(Icons.sync_outlined), label: 'المزامنة'),
        ],
      ),
    );
  }
}
