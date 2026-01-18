import 'package:flutter/material.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/companies_tab.dart';
import 'tabs/users_tab.dart';
import 'tabs/photographers_tab.dart';
import 'tabs/access_control_tab.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/auth_repository.dart';
import '../../state/project_state.dart';
import '../dialogs/event_config_dialog.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text("Configurações & Painel"),
        backgroundColor: const Color(0xFF2C2C2C),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
               showDialog(
                 context: context, 
                 builder: (context) => const EventConfigDialog()
               );
            },
            icon: const Icon(Icons.settings),
            tooltip: "Configurar Eventos",
          ),
          IconButton(
            onPressed: () {
               // 1. Clear Project State (Legacy of previous user)
               ref.read(projectProvider.notifier).resetProject();
               // 2. Sign Out
               ref.read(authProvider.notifier).signOut();
               Navigator.of(context).pop(); // Back to main/login check
            },
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: "Sair do Sistema",
          )
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: const Color(0xFF2C2C2C),
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            unselectedLabelTextStyle: const TextStyle(color: Colors.white54),
            selectedLabelTextStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined, color: Colors.white54),
                selectedIcon: Icon(Icons.dashboard, color: Colors.blueAccent),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.domain, color: Colors.white54),
                selectedIcon: Icon(Icons.domain, color: Colors.blueAccent),
                label: Text('Empresas'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline, color: Colors.white54),
                selectedIcon: Icon(Icons.people, color: Colors.blueAccent),
                label: Text('Usuários'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.camera_alt_outlined, color: Colors.white54),
                selectedIcon: Icon(Icons.camera_alt, color: Colors.blueAccent),
                label: Text('Fotógrafos'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.admin_panel_settings_outlined, color: Colors.white54),
                selectedIcon: Icon(Icons.admin_panel_settings, color: Colors.redAccent),
                label: Text('Acesso'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white10),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                AnalyticsTab(),
                CompaniesTab(),
                UsersTab(),
                PhotographersTab(),
                AccessControlTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
