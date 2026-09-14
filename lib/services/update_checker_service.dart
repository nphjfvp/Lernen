import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Ergebnis eines gefundenen Updates: die neue Build-Nummer + wo man sie
/// herunterladen kann (direkter Download-Link zur APK bzw. zum ZIP).
class UpdateInfo {
  const UpdateInfo({required this.buildNumber, required this.sha, required this.downloadUrl});

  final int buildNumber;
  final String sha;
  final String downloadUrl;
}

/// Prüft, ob unter der festen "*-latest"-GitHub-Release-URL (siehe
/// .github/workflows/android-apk.yml / windows-app.yml, die dort bei jedem
/// Push ein "version.json" mit der fortlaufenden Actions-Run-Nummer als
/// buildNumber veröffentlichen) ein neuerer Build liegt als der gerade
/// laufende – Ersatz dafür, von Hand auf GitHub nachschauen zu müssen, ob es
/// eine neue APK/ZIP gibt.
///
/// Bewusst fehlertolerant wie alle anderen optionalen Services der App (kein
/// Internet, GitHub nicht erreichbar o.ä. wirft nirgends, sondern liefert
/// einfach `null` zurück statt die App zu stören).
class UpdateCheckerService {
  UpdateCheckerService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _androidVersionUrl =
      'https://github.com/nphjfvp/Lernen/releases/download/android-latest/version.json';
  static const _androidApkUrl =
      'https://github.com/nphjfvp/Lernen/releases/download/android-latest/app-release.apk';
  static const _windowsVersionUrl =
      'https://github.com/nphjfvp/Lernen/releases/download/windows-latest/version.json';
  static const _windowsZipUrl =
      'https://github.com/nphjfvp/Lernen/releases/download/windows-latest/lernen-windows.zip';

  /// Reine Vergleichslogik ohne Netzwerk-/Plattform-Zugriff (daher direkt
  /// testbar): liefert [UpdateInfo], wenn [remoteJson] eine höhere
  /// "buildNumber" trägt als [localBuildNumber], sonst `null`.
  static UpdateInfo? compare({
    required Map<String, dynamic> remoteJson,
    required int localBuildNumber,
    required String downloadUrl,
  }) {
    final remoteBuild = remoteJson['buildNumber'];
    if (remoteBuild is! int || remoteBuild <= localBuildNumber) return null;
    return UpdateInfo(
      buildNumber: remoteBuild,
      sha: (remoteJson['sha'] ?? '').toString(),
      downloadUrl: downloadUrl,
    );
  }

  /// Nur auf Android/Windows sinnvoll (dort gibt es die APK/ZIP-Verteilung
  /// über GitHub Releases) – auf Web/iOS/macOS/Linux liefert dies immer
  /// `null`, ohne einen Netzwerk-Aufruf zu versuchen.
  Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;

    final String versionUrl;
    final String downloadUrl;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        versionUrl = _androidVersionUrl;
        downloadUrl = _androidApkUrl;
      case TargetPlatform.windows:
        versionUrl = _windowsVersionUrl;
        downloadUrl = _windowsZipUrl;
      default:
        return null;
    }

    try {
      final response = await _client.get(Uri.parse(versionUrl)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;
      return compare(remoteJson: json, localBuildNumber: localBuild, downloadUrl: downloadUrl);
    } catch (_) {
      return null;
    }
  }
}
