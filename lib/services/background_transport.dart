/// KI-Anfragen unter Android im Hintergrund (siehe background_transport_io.dart)
/// und die Absturz-Notiz dazu – im Web nur Platzhalter.
library;

export 'background_transport_base.dart';
export 'background_transport_stub.dart' if (dart.library.io) 'background_transport_io.dart';
