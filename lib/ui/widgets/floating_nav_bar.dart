import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class NavItem {
  const NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Schwebende Pillen-Navigationsleiste (Design-Grundlage "Ruhig &
/// Fokussiert") statt der Standard-Material-NavigationBar – bewusst mit
/// Abstand zum Rand statt Vollbreite, um weniger nach Baukasten-App
/// auszusehen.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.45 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavButton(
              item: items[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? c.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, size: 19, color: selected ? c.accent : c.inkMuted),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? c.accentOnSoft : c.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
