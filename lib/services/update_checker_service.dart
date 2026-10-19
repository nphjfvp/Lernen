import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Ergebnis eines gefundenen Updates: die neue Build-Nummer + wo man sie
/// herunterladen kann (direkter Download-Link zur APK bzw. zum Windows-Setup).
class UpdateInfo {
  const UpdateInfo({
    required this.buildNumber,
    required this.sha,
    required this.downloadUrl,
    this.signer = 'debug',
    this.needsReinstall = false,
  });

  final int buildNumber;
  final String sha;
  final String downloadUrl;

  /// Mit welchem Schlüssel die neue APK signiert ist (`debug` = der
  /// eingecheckte Debug-Keystore, `release` = eigener Schlüssel aus den
  /// GitHub-Secrets).
  final String signer;

  /// Anderer Schlüssel als die laufende App: Android installiert das nicht
  /// als Update – einmal deinstallieren und neu installieren nötig.
  final bool needsReinstall;
}

/// Mit welchem Schlüssel diese App signiert ist (beim Build per
/// `--dart-define=LERNEN_SIGNER=…` gesetzt, siehe android-apk.yml).
const appSigner = String.fromEnvironment('LERNEN_SIGNER', defaultValue: 'debug');

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
  /// Das Setup statt des ZIPs: installiert (bzw. aktualisiert) die App als
  /// eine Datei, siehe windows/installer/lernen.iss.
  static const _windowsSetupUrl =
      'https://github.com/nphjfvp/Lernen/releases/download/windows-latest/Lernen-Setup.exe';

  /// Reine Vergleichslogik ohne Netzwerk-/Plattform-Zugriff (daher direkt
  /// testbar): liefert [UpdateInfo], wenn [remoteJson] eine höhere
  /// "buildNumber" trägt als [localBuildNumber], sonst `null`.
  static UpdateInfo? compare({
    required Map<String, dynamic> remoteJson,
    required int localBuildNumber,
    required String downloadUrl,
    String localSigner = appSigner,
  }) {
    final remoteBuild = remoteJson['buildNumber'];
    if (remoteBuild is! int || remoteBuild <= localBuildNumber) return null;
    final signer = (remoteJson['signer'] as String?)?.trim();
    final remoteSigner = signer == null || signer.isEmpty ? 'debug' : signer;
    return UpdateInfo(
      buildNumber: remoteBuild,
      sha: (remoteJson['sha'] ?? '').toString(),
      downloadUrl: downloadUrl,
      signer: remoteSigner,
      needsReinstall: remoteSigner != localSigner,
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
        downloadUrl = _windowsSetupUrl;
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
