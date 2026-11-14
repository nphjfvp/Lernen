import 'package:flutter/widgets.dart';

/// Schreibt man gerade in ein Textfeld? Dann gehören Pfeiltasten, Leertaste,
/// Rück- und Entf-Taste dem Feld – Tastenkürzel einer Ansicht (Blättern,
/// Balken verschieben …) treten zurück. Gilt im Browser wie in der Windows-App.
bool isEditingText() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorStateOfType<EditableTextState>() != null;
}
