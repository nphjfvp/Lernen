import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'calendar/calendar_screen.dart';
import 'daily/daily_quiz_screen.dart';
import 'home/home_screen.dart';
import 'modules/module_form_screen.dart';
import 'settings/settings_screen.dart';
import 'stats/stats_screen.dart';
import 'widgets/floating_nav_bar.dart';

/// Schwebende Pillen-Navigation über die drei Hauptbereiche der App (siehe
/// Design-Grundlage "Ruhig & Fokussiert") statt einer randlosen Standard-
/// NavigationBar.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    DailyQuizScreen(),
    CalendarScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  static const _navItems = [
    NavItem(icon: Icons.folder_rounded, label: 'Fächer'),
    NavItem(icon: Icons.style_rounded, label: 'Daily Quiz'),
    NavItem(icon: Icons.calendar_today_rounded, label: 'Kalender'),
    NavItem(icon: Icons.insights_rounded, label: 'Fortschritt'),
    NavItem(icon: Icons.settings_rounded, label: 'Einstellungen'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _screens),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: FloatingNavBar(
              items: _navItems,
              selectedIndex: _index,
              onSelect: (i) => setState(() => _index = i),
            ),
          ),
          if (_index == 0)
            Positioned(
              right: 24,
              bottom: 104,
              child: FloatingActionButton(
                backgroundColor: context.colors.accentSolid,
                foregroundColor: context.colors.accentInk,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ModuleFormScreen()),
                ),
                child: const Icon(Icons.add),
              ),
            ),
        ],
      ),
    );
  }
}
