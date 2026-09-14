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
