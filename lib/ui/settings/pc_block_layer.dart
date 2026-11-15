import 'package:flutter/material.dart';

import '../../services/windows_guard.dart';
import '../../theme/app_colors.dart';

/// Lernzeit-Sperre am PC: legt den Sperrbildschirm über die ganze App,
/// sobald [WindowsGuard] ein Fenster gesperrt hat (das Fenster ist dann schon
/// minimiert und die Lern-App vorn).
class PcBlockLayer extends StatelessWidget {
  const PcBlockLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PcBlock?>(
    valueListenable: WindowsGuard.instance.block,
    builder: (context, block, _) => Stack(
      children: [
        child,
        if (block != null) Positioned.fill(child: _BlockScreen(block: block)),
      ],
    ),
  );
}

class _BlockScreen extends StatelessWidget {
  const _BlockScreen({required this.block});

  final PcBlock block;

  String _hours(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final game = block.group == PcGroup.game;
    return Material(
      key: const ValueKey('pc-block'),
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(game ? Icons.sports_esports_rounded : Icons.lock_clock_rounded, size: 56, color: Colors.white),
                  const SizedBox(height: 14),
                  Text(
                    game ? 'Spielzeit aufgebraucht' : 'Lernzeit aufgebraucht',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    game
                        ? 'Diese Woche ${_hours(block.usedMinutes)} von ${_hours(block.allowedMinutes)} gespielt.'
                        : 'Heute ${block.usedMinutes} von ${block.allowedMinutes} Minuten genutzt – Handy und PC '
                              'zusammen.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFC5CAE9), fontSize: 16, height: 1.4),
                  ),
                  if (block.what.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '„${block.what.trim()}“ wurde minimiert.',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF9FA8DA), fontSize: 13),
                    ),
                  ],
                  if (block.nextStep.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      block.nextStep,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                    ),
                  ],
                  if (!game) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Im Hintergrund weiterhören geht – gezählt und gesperrt wird nur, was vorn zu sehen ist.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9FA8DA), fontSize: 13, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('pc-block-learn'),
                      style: FilledButton.styleFrom(backgroundColor: c.accent),
                      onPressed: WindowsGuard.instance.dismissBlock,
                      icon: const Icon(Icons.school_rounded),
                      label: const Text('Jetzt lernen'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const ValueKey('pc-block-hide'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF7986CB)),
                      ),
                      onPressed: WindowsGuard.instance.hideApp,
                      child: const Text('Lern-App ausblenden'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
