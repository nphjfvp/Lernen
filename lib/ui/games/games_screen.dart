import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../sprint/sprint_screen.dart';
import 'boss_battle_screen.dart';

/// Spiele zur Auflockerung (Fortschritts-Tab). Alle bestehen aus deinen
/// echten Karten und zählen fürs Lernen wie das Daily Quiz – keine Münzen,
/// kein Shop, nur der eigene Stand.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Spiele')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Jede Antwort zählt wie im Daily Quiz für Ampel und Wiederholungsplan – nur verpackt als Spiel.',
            style: TextStyle(color: c.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _GameTile(
            key: const ValueKey('game-boss'),
            icon: Icons.pest_control_rounded,
            color: c.danger,
            title: 'Boss-Kampf',
            subtitle: 'Die schwächsten Karten eines Fachs als Endgegner – falsche kommen wieder, bis alles sitzt.',
            builder: (_) => const BossBattleScreen(),
          ),
          const SizedBox(height: 10),
          _GameTile(
            key: const ValueKey('game-sprint'),
            icon: Icons.bolt_rounded,
            color: c.warn,
            title: 'Sprint',
            subtitle: '60 Sekunden gegen deine schwächsten Karten, mit persönlicher Bestleistung.',
            builder: (_) => const SprintScreen(),
          ),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
