/// Globale App-Einstellungen: BYOK-Zugangsdaten für die KI (OpenRouter) und
/// optionaler Cloud-Sync-Code.
class AppSettings {
  final String? openRouterApiKey;
  final String selectedModel;
  final String? syncCode;
  final DateTime? lastSyncAt;

  static const defaultModel = 'deepseek/deepseek-chat';

  const AppSettings({
    this.openRouterApiKey,
    this.selectedModel = defaultModel,
    this.syncCode,
    this.lastSyncAt,
  });

  bool get hasApiKey =>
      openRouterApiKey != null && openRouterApiKey!.trim().isNotEmpty;

  AppSettings copyWith({
    String? openRouterApiKey,
    String? selectedModel,
    String? syncCode,
    DateTime? lastSyncAt,
  }) {
    return AppSettings(
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      syncCode: syncCode ?? this.syncCode,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'openRouterApiKey': openRouterApiKey,
        'selectedModel': selectedModel,
        'syncCode': syncCode,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        openRouterApiKey: map['openRouterApiKey'] as String?,
        selectedModel: map['selectedModel'] as String? ?? defaultModel,
        syncCode: map['syncCode'] as String?,
        lastSyncAt: map['lastSyncAt'] == null
            ? null
            : DateTime.parse(map['lastSyncAt'] as String),
      );
}

/// Kuratierte Modellauswahl für OpenRouter (BYOK). Bewusst kurz gehalten –
/// der Fokus der neuen App liegt auf Qualität statt auf Auswahl-Overload.
class AiModelOption {
  final String id;
  final String label;
  final bool vision;
  final bool free;

  const AiModelOption(this.id, this.label, {this.vision = false, this.free = false});
}

const kOpenRouterModels = [
  AiModelOption('deepseek/deepseek-chat', 'DeepSeek Chat (günstig)', free: false),
  AiModelOption('google/gemini-2.5-flash', 'Gemini 2.5 Flash (Vision)', vision: true),
  AiModelOption('openai/gpt-4o-mini', 'GPT-4o mini (Vision)', vision: true),
  AiModelOption('anthropic/claude-3.5-haiku', 'Claude 3.5 Haiku'),
];
