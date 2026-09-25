/// Wie stark ein großer Text vor der KI-Generierung in Abschnitte zerlegt
/// wird. "auto" wählt die Granularität selbst anhand der Textlänge (siehe
/// AiService.chunkText); die anderen Stufen erzwingen eine feste Chunkgröße.
enum ChunkGranularity { auto, off, coarse, medium, fine }

extension ChunkGranularityLabel on ChunkGranularity {
  String get label => switch (this) {
        ChunkGranularity.auto => 'Automatisch',
        ChunkGranularity.off => 'Aus',
        ChunkGranularity.coarse => 'Grob',
        ChunkGranularity.medium => 'Mittel',
        ChunkGranularity.fine => 'Fein',
      };
}

/// Globale App-Einstellungen: BYOK-Zugangsdaten für die KI (OpenRouter),
/// ein Modell pro Aufgaben-Rolle und optionaler Cloud-Sync-Code.
///
/// Drei Rollen statt eines einzigen Modells, weil die Aufgaben sich stark
/// unterscheiden: Fragenerstellen ist reiner Text, Vision braucht ein
/// bildfähiges Modell (z.B. für gescannte Foliensätze ohne Textebene), und
/// Crosscheck ist bewusst ein ZWEITES Modell, damit ein Fehler des ersten
/// Modells nicht unbemerkt bleibt.
class AppSettings {
  final String? openRouterApiKey;
  final String questionModelId;
  final String visionModelId;
  final String crosscheckModelId;
  final ChunkGranularity chunkGranularity;
  final bool rollingContextEnabled;
  final String? syncCode;
  final DateTime? lastSyncAt;
  final bool dailyReminderEnabled;

  /// Uhrzeit der täglichen Lernerinnerung, als Minuten seit Mitternacht
  /// (kein `TimeOfDay` hier, damit dieses Modell ohne Flutter-Import
  /// testbar bleibt). Default 18:00.
  final int dailyReminderMinuteOfDay;

  /// Persönliche Bestleistung im Sprint-Pausenmodus (siehe SprintScreen) –
  /// Anzahl richtig beantworteter Karten in einer Runde. Bewusst rein
  /// geräte-lokal wie die Lernerinnerungs-Uhrzeit (kein Leaderboard, kein
  /// Vergleich mit anderen Nutzern): Kompetenz-Feedback gegen den eigenen
  /// früheren Stand motiviert nachhaltiger als sozialer Vergleich.
  final int bestSprintScore;

  /// Alle wie viele gelesenen Seiten der "Lernmodus" (siehe
  /// MaterialViewerScreen) einen kurzen Zwischen-Check anbietet – 0
  /// deaktiviert das Feature komplett. Rein informativ/nicht blockierend:
  /// der Nutzer kann den Check jederzeit wegtippen und weiterlesen.
  final int checkpointQuizPageInterval;

  /// Lädt Änderungen automatisch (kurz verzögert) in die Cloud hoch, siehe
  /// AutoSyncService. Ziel: das angemeldete Konto, sonst [syncCode].
  final bool autoSyncEnabled;

  /// Zufällige, einmalig erzeugte Kennung dieses Geräts – erkennt beim
  /// Auto-Sync, ob der Cloud-Stand von einem ANDEREN Gerät stammt.
  final String? deviceId;

  /// `pushId` des Cloud-Stands, mit dem dieses Gerät zuletzt abgeglichen
  /// war (eigener Upload oder Download). Weicht der Cloud-Stand davon ab und
  /// stammt von einem anderen Gerät, lädt der Auto-Sync NICHT hoch, sondern
  /// bittet erst um einen Download.
  final String? lastSyncedPushId;

  static const defaultQuestionModel = 'deepseek/deepseek-chat';
  static const defaultVisionModel = 'google/gemini-2.5-flash';
  static const defaultCrosscheckModel = 'anthropic/claude-3.5-haiku';
  static const defaultReminderMinuteOfDay = 18 * 60;
  static const defaultCheckpointQuizPageInterval = 5;

  const AppSettings({
    this.openRouterApiKey,
    this.questionModelId = defaultQuestionModel,
    this.visionModelId = defaultVisionModel,
    this.crosscheckModelId = defaultCrosscheckModel,
    this.chunkGranularity = ChunkGranularity.auto,
    this.rollingContextEnabled = true,
    this.syncCode,
    this.lastSyncAt,
    this.dailyReminderEnabled = false,
    this.dailyReminderMinuteOfDay = defaultReminderMinuteOfDay,
    this.bestSprintScore = 0,
    this.checkpointQuizPageInterval = defaultCheckpointQuizPageInterval,
    this.autoSyncEnabled = false,
    this.deviceId,
    this.lastSyncedPushId,
  });

  bool get hasApiKey =>
      openRouterApiKey != null && openRouterApiKey!.trim().isNotEmpty;

  int get dailyReminderHour => dailyReminderMinuteOfDay ~/ 60;
  int get dailyReminderMinute => dailyReminderMinuteOfDay % 60;

  AppSettings copyWith({
    String? openRouterApiKey,
    String? questionModelId,
    String? visionModelId,
    String? crosscheckModelId,
    ChunkGranularity? chunkGranularity,
    bool? rollingContextEnabled,
    String? syncCode,
    DateTime? lastSyncAt,
    bool? dailyReminderEnabled,
    int? dailyReminderMinuteOfDay,
    int? bestSprintScore,
    int? checkpointQuizPageInterval,
    bool? autoSyncEnabled,
    String? deviceId,
    String? lastSyncedPushId,
  }) {
    return AppSettings(
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      questionModelId: questionModelId ?? this.questionModelId,
      visionModelId: visionModelId ?? this.visionModelId,
      crosscheckModelId: crosscheckModelId ?? this.crosscheckModelId,
      chunkGranularity: chunkGranularity ?? this.chunkGranularity,
      rollingContextEnabled: rollingContextEnabled ?? this.rollingContextEnabled,
      syncCode: syncCode ?? this.syncCode,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      dailyReminderMinuteOfDay: dailyReminderMinuteOfDay ?? this.dailyReminderMinuteOfDay,
      bestSprintScore: bestSprintScore ?? this.bestSprintScore,
      checkpointQuizPageInterval: checkpointQuizPageInterval ?? this.checkpointQuizPageInterval,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      deviceId: deviceId ?? this.deviceId,
      lastSyncedPushId: lastSyncedPushId ?? this.lastSyncedPushId,
    );
  }

  Map<String, dynamic> toMap() => {
        'openRouterApiKey': openRouterApiKey,
        'questionModelId': questionModelId,
        'visionModelId': visionModelId,
        'crosscheckModelId': crosscheckModelId,
        'chunkGranularity': chunkGranularity.name,
        'rollingContextEnabled': rollingContextEnabled,
        'syncCode': syncCode,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'dailyReminderEnabled': dailyReminderEnabled,
        'dailyReminderMinuteOfDay': dailyReminderMinuteOfDay,
        'bestSprintScore': bestSprintScore,
        'checkpointQuizPageInterval': checkpointQuizPageInterval,
        'autoSyncEnabled': autoSyncEnabled,
        'deviceId': deviceId,
        'lastSyncedPushId': lastSyncedPushId,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        openRouterApiKey: map['openRouterApiKey'] as String?,
        questionModelId: map['questionModelId'] as String? ?? defaultQuestionModel,
        visionModelId: map['visionModelId'] as String? ?? defaultVisionModel,
        crosscheckModelId: map['crosscheckModelId'] as String? ?? defaultCrosscheckModel,
        chunkGranularity: ChunkGranularity.values.firstWhere(
          (g) => g.name == map['chunkGranularity'],
          orElse: () => ChunkGranularity.auto,
        ),
        rollingContextEnabled: map['rollingContextEnabled'] as bool? ?? true,
        syncCode: map['syncCode'] as String?,
        lastSyncAt: map['lastSyncAt'] == null
            ? null
            : DateTime.parse(map['lastSyncAt'] as String),
        dailyReminderEnabled: map['dailyReminderEnabled'] as bool? ?? false,
        dailyReminderMinuteOfDay: map['dailyReminderMinuteOfDay'] as int? ?? defaultReminderMinuteOfDay,
        bestSprintScore: map['bestSprintScore'] as int? ?? 0,
        checkpointQuizPageInterval:
            map['checkpointQuizPageInterval'] as int? ?? defaultCheckpointQuizPageInterval,
        autoSyncEnabled: map['autoSyncEnabled'] as bool? ?? false,
        deviceId: map['deviceId'] as String?,
        lastSyncedPushId: map['lastSyncedPushId'] as String?,
      );
}
