import '../../models/ai_model_info.dart';
import '../../models/app_settings.dart';
import '../../repositories/settings_repository.dart';
import '../../services/scene3d_model.dart';

/// Die Modell-Rollen der Einstellungen: 'question', 'help', 'vision',
/// 'crosscheck', 'scene3d'.
String modelRoleLabel(String role) => switch (role) {
  'question' => 'Fragenerstellen',
  'help' => 'Erklärungen & Hilfe',
  'vision' => 'Vision',
  'crosscheck' => 'Crosscheck',
  'scene3d' => '3D-Modelle',
  _ => role,
};

/// Das Modell, das zurzeit für [role] arbeitet (auch wenn es nur „folgt“ oder
/// automatisch gewählt ist).
String modelForRole(AppSettings settings, String role, {AiModelInfo? Function(String id)? info}) => switch (role) {
  'help' => settings.effectiveHelpModelId,
  'vision' => settings.visionModelId,
  'crosscheck' => settings.crosscheckModelId,
  'scene3d' =>
    settings.scene3dModelId ?? Scene3dModel.auto(questionModelId: settings.questionModelId, info: info ?? (_) => null),
  _ => settings.questionModelId,
};

/// Stellt [picked] für [role] ein.
Future<void> setModelForRole(SettingsRepository repo, String role, String picked) async {
  final settings = repo.settings;
  switch (role) {
    case 'question':
      await repo.update(settings.copyWith(questionModelId: picked));
    case 'vision':
      await repo.update(settings.copyWith(visionModelId: picked));
    case 'crosscheck':
      await repo.update(settings.copyWith(crosscheckModelId: picked));
    case 'scene3d':
      await repo.update(
        picked == settings.questionModelId
            ? settings.copyWith(clearScene3dModel: true)
            : settings.copyWith(scene3dModelId: picked),
      );
    case 'help':
      // Dasselbe wie das Fragen-Modell = "folgt ihm" (ändert sich dann mit).
      await repo.update(
        picked == settings.questionModelId
            ? settings.copyWith(clearHelpModel: true)
            : settings.copyWith(helpModelId: picked),
      );
  }
}
