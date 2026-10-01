import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/image_crop.dart';

/// Ein PNG mit Rauschen (schlecht komprimierbar, wie ein Foto).
Future<Uint8List> _noisyPng(int width, int height) async {
  final pixels = Uint8List(width * height * 4);
  var seed = 7;
  for (var i = 0; i < pixels.length; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    pixels[i] = (i % 4 == 3) ? 255 : (seed >> 16) & 0xff;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ein kleines JPEG geht unverändert mit (Neu-Kodieren als PNG machte es nur größer)', () async {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 1)]);
    expect(identical(await prepareImageForAi(jpeg), jpeg), isTrue);
  });

  test('ein großes PNG wird verkleinert, bis es unter die Grenze passt', () async {
    final png = await _noisyPng(1800, 1200);
    final limit = png.length ~/ 3;
    final prepared = await prepareImageForAi(png, maxBytes: limit);
    expect(prepared.length, lessThanOrEqualTo(limit));
    final size = await imageSizeOf(prepared);
    expect(size!.width, lessThan(1800));
  });

  test('ein kleines PNG bleibt, wie es ist', () async {
    final png = await _noisyPng(40, 30);
    expect(identical(await prepareImageForAi(png), png), isTrue);
  });
}
