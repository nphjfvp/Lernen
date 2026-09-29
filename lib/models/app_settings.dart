import 'flashcard.dart';
import 'pdf_storage_config.dart';

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

  /// Eigener Speicher für die Original-PDFs (siehe PdfStorageConfig) – ohne
  /// Zugangsdaten bleibt der PDF-Sync aus.
  final PdfStorageConfig pdfStorage;

  /// Gewählte Farbpalette in den Einstellungen, als `name` von
  /// `AppThemeSkin` (siehe theme/app_colors.dart) – als reiner String
  /// statt des Enums selbst, damit dieses Modell ohne Flutter-Import
  /// testbar bleibt (wie [dailyReminderMinuteOfDay]). Ein unbekannter Wert
  /// (älterer Datensatz, kaputter Sync) fällt beim Lesen über
  /// `themeSkinFromName` auf den Standard zurück, nie auf einen Absturz.
  final String themeSkin;

  /// Hell/Dunkel-Vorgabe in den Einstellungen, als `name` von
  /// `AppThemeModePreference` (siehe theme/app_theme.dart) – wie [themeSkin]
  /// als reiner String, damit dieses Modell ohne Flutter-Import testbar
  /// bleibt. "system" (Standard) folgt weiterhin der Systemeinstellung, ein
  /// unbekannter Wert fällt beim Lesen ebenfalls darauf zurück.
  final String themeModePreference;

  /// Voreingestellter Fragetyp je Schwierigkeitsstufe beim "Frage erstellen"
  /// (Schlüssel `leicht`/`mittel`/`schwer`, Wert = `QuestionType.name`). Eine
  /// fehlende Stufe heißt "KI entscheidet". Im Fenster lässt sich jede Stufe
  /// vor dem Erstellen trotzdem von Hand ändern.
  final Map<String, String> pageQuestionTierTypes;

  /// Als Favorit markierte KI-Modelle (OpenRouter-IDs, in der Reihenfolge des
  /// Markierens). Sie stehen im Modellwähler ganz oben und sind beim "Frage
  /// erstellen" mit einem Tipp wählbar, ohne sie jedes Mal zu suchen.
  final List<String> favoriteModelIds;

  static const defaultQuestionModel = 'deepseek/deepseek-chat';
  static const defaultVisionModel = 'google/gemini-2.5-flash';
  static const defaultCrosscheckModel = 'anthropic/claude-3.5-haiku';
  static const defaultReminderMinuteOfDay = 18 * 60;
  static const defaultCheckpointQuizPageInterval = 5;
  static const defaultThemeSkin = 'klar';
  static const defaultThemeModePreference = 'system';

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
    this.pdfStorage = const PdfStorageConfig(),
    this.themeSkin = defaultThemeSkin,
    this.themeModePreference = defaultThemeModePreference,
    this.pageQuestionTierTypes = const {},
    this.favoriteModelIds = const [],
  });

  bool get hasApiKey =>
      openRouterApiKey != null && openRouterApiKey!.trim().isNotEmpty;

  /// Schlüssel einer Stufe in [pageQuestionTierTypes] ("Leicht" → `leicht`).
  static String tierKey(String level) => level.trim().toLowerCase();

  /// Voreingestellter Typ der Stufe [level] oder null ("KI entscheidet").
  QuestionType? pageTierType(String level) {
    final name = pageQuestionTierTypes[tierKey(level)];
    for (final t in QuestionType.values) {
      if (t.name == name) return t;
    }
    return null;
  }

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
    PdfStorageConfig? pdfStorage,
    String? themeSkin,
    String? themeModePreference,
    Map<String, String>? pageQuestionTierTypes,
    List<String>? favoriteModelIds,
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
      pdfStorage: pdfStorage ?? this.pdfStorage,
      themeSkin: themeSkin ?? this.themeSkin,
      themeModePreference: themeModePreference ?? this.themeModePreference,
      pageQuestionTierTypes: pageQuestionTierTypes ?? this.pageQuestionTierTypes,
      favoriteModelIds: favoriteModelIds ?? this.favoriteModelIds,
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
        'pdfStorage': pdfStorage.toMap(),
        'themeSkin': themeSkin,
        'themeModePreference': themeModePreference,
        'pageQuestionTierTypes': pageQuestionTierTypes,
        'favoriteModelIds': favoriteModelIds,
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
        // Tolerant gelesen: ein unerwarteter Wert darf den App-Start nicht
        // verhindern (die Einstellungen werden beim Start geladen).
        lastSyncAt: DateTime.tryParse(map['lastSyncAt']?.toString() ?? ''),
        dailyReminderEnabled: map['dailyReminderEnabled'] as bool? ?? false,
        dailyReminderMinuteOfDay:
            (map['dailyReminderMinuteOfDay'] as num?)?.toInt() ?? defaultReminderMinuteOfDay,
        bestSprintScore: (map['bestSprintScore'] as num?)?.toInt() ?? 0,
        checkpointQuizPageInterval:
            (map['checkpointQuizPageInterval'] as num?)?.toInt() ?? defaultCheckpointQuizPageInterval,
        autoSyncEnabled: map['autoSyncEnabled'] as bool? ?? false,
        deviceId: map['deviceId'] as String?,
        lastSyncedPushId: map['lastSyncedPushId'] as String?,
        pdfStorage: map['pdfStorage'] is Map
            ? PdfStorageConfig.fromMap(Map<String, dynamic>.from(map['pdfStorage'] as Map))
            : const PdfStorageConfig(),
        themeSkin: map['themeSkin'] as String? ?? defaultThemeSkin,
        themeModePreference: map['themeModePreference'] as String? ?? defaultThemeModePreference,
        pageQuestionTierTypes: parseTierTypes(map['pageQuestionTierTypes']) ?? const {},
        favoriteModelIds: parseModelIds(map['favoriteModelIds']) ?? const [],
      );

  bool isFavoriteModel(String id) => favoriteModelIds.contains(id);

  /// Die Favoritenliste mit [id] hinzugefügt bzw. – wenn schon Favorit –
  /// entfernt.
  List<String> favoritesToggled(String id) =>
      isFavoriteModel(id) ? [for (final f in favoriteModelIds) if (f != id) f] : [...favoriteModelIds, id];

  /// Liest eine Liste von Modell-IDs tolerant (ohne Doppelte und Leeres);
  /// `null`, wenn gar keine Liste da ist.
  static List<String>? parseModelIds(Object? raw) {
    if (raw is! List) return null;
    final ids = <String>[];
    for (final e in raw) {
      if (e is String && e.trim().isNotEmpty && !ids.contains(e.trim())) ids.add(e.trim());
    }
    return ids;
  }

  /// Liest die Typ-Vorgaben je Stufe tolerant (ein kaputter Eintrag darf den
  /// App-Start nicht verhindern); `null`, wenn gar keine Angabe da ist.
  static Map<String, String>? parseTierTypes(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is String && (e.value as String).trim().isNotEmpty)
          tierKey(e.key as String): e.value as String,
    };
  }
}
