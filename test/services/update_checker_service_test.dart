import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/update_checker_service.dart';

void main() {
  group('UpdateCheckerService.compare', () {
    test('liefert UpdateInfo, wenn die Remote-buildNumber größer ist', () {
      final result = UpdateCheckerService.compare(
        remoteJson: const {'buildNumber': 42, 'sha': 'abc123'},
        localBuildNumber: 10,
        downloadUrl: 'https://example.com/app.apk',
      );
      expect(result, isNotNull);
      expect(result!.buildNumber, 42);
      expect(result.sha, 'abc123');
      expect(result.downloadUrl, 'https://example.com/app.apk');
    });

    test('Signierschlüssel: gleicher Schlüssel = Update, anderer = einmal neu installieren', () {
      UpdateInfo? check(Map<String, dynamic> json, String local) => UpdateCheckerService.compare(
            remoteJson: json,
            localBuildNumber: 1,
            downloadUrl: 'u',
            localSigner: local,
          );
      expect(check(const {'buildNumber': 2}, 'debug')!.needsReinstall, isFalse, reason: 'ältere version.json ohne signer');
      expect(check(const {'buildNumber': 2, 'signer': 'debug'}, 'debug')!.needsReinstall, isFalse);
      final switched = check(const {'buildNumber': 2, 'signer': 'release'}, 'debug')!;
      expect(switched.needsReinstall, isTrue);
      expect(switched.signer, 'release');
      expect(check(const {'buildNumber': 2, 'signer': 'release'}, 'release')!.needsReinstall, isFalse);
      expect(check(const {'buildNumber': 2, 'signer': ''}, 'debug')!.needsReinstall, isFalse);
      expect(appSigner, 'debug', reason: 'ohne --dart-define');
    });

    test('gibt null zurück, wenn die Remote-buildNumber gleich ist', () {
      final result = UpdateCheckerService.compare(
        remoteJson: const {'buildNumber': 10},
        localBuildNumber: 10,
        downloadUrl: 'https://example.com/app.apk',
      );
      expect(result, isNull);
    });

    test('gibt null zurück, wenn die Remote-buildNumber kleiner ist', () {
      final result = UpdateCheckerService.compare(
        remoteJson: const {'buildNumber': 5},
        localBuildNumber: 10,
        downloadUrl: 'https://example.com/app.apk',
      );
      expect(result, isNull);
    });

    test('gibt null zurück, wenn buildNumber fehlt oder falschen Typ hat', () {
      expect(
        UpdateCheckerService.compare(
          remoteJson: const {},
          localBuildNumber: 10,
          downloadUrl: 'https://example.com/app.apk',
        ),
        isNull,
      );
      expect(
        UpdateCheckerService.compare(
          remoteJson: const {'buildNumber': '42'},
          localBuildNumber: 10,
          downloadUrl: 'https://example.com/app.apk',
        ),
        isNull,
      );
    });

    test('sha ist leerer String, wenn im JSON nicht vorhanden', () {
      final result = UpdateCheckerService.compare(
        remoteJson: const {'buildNumber': 42},
        localBuildNumber: 10,
        downloadUrl: 'https://example.com/app.apk',
      );
      expect(result!.sha, '');
    });
  });
}
