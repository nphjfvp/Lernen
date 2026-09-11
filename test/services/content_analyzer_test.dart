import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/services/content_analyzer.dart';

void main() {
  group('ContentAnalyzer.analyze', () {
    test('kurzer Text empfiehlt kein Chunking', () {
      final analysis = ContentAnalyzer.analyze('x' * 1000);
      expect(analysis.recommendedGranularity, ChunkGranularity.off);
      expect(analysis.recommendedRollingContext, isFalse);
    });

    test('mittellanger Text empfiehlt grobes Chunking mit Rolling Context', () {
      final analysis = ContentAnalyzer.analyze('x' * 30000);
      expect(analysis.recommendedGranularity, ChunkGranularity.coarse);
      expect(analysis.recommendedRollingContext, isTrue);
    });

    test('sehr langer Text empfiehlt feines Chunking', () {
      final analysis = ContentAnalyzer.analyze('x' * 300000);
      expect(analysis.recommendedGranularity, ChunkGranularity.fine);
      expect(analysis.recommendedRollingContext, isTrue);
    });

    test('totalChars entspricht der Textlänge', () {
      expect(ContentAnalyzer.analyze('x' * 4242).totalChars, 4242);
    });
  });
}
