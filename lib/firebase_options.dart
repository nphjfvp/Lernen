import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase-Konfiguration für das Projekt "lernenwing".
///
/// Es ist bewusst nur eine Web-App im Firebase-Projekt registriert; dieselbe
/// Konfiguration wird für alle Plattformen (Android/iOS/Windows/Web)
/// wiederverwendet. Das genügt für den Sync-Code-Ansatz (Firestore-Zugriff
/// hängt nur an apiKey + projectId, nicht an der Plattform) – für separate
/// Analytics-Zuordnung pro Plattform könnte man später zusätzliche Apps im
/// Firebase-Projekt registrieren und hier pro Plattform verzweigen, wie es
/// `flutterfire configure` normalerweise generiert.
///
/// Kein Geheimnis: dieser API-Key ist für die clientseitige Nutzung gedacht,
/// abgesichert wird der Zugriff über die Firestore Security Rules
/// (siehe firestore.rules), nicht über Geheimhaltung dieses Keys.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD984fTuOiD31SEe07UZaP4btGxNv1xU40',
    appId: '1:447278958302:web:71d17793ef2755ae8aa44f',
    messagingSenderId: '447278958302',
    projectId: 'lernenwing',
    authDomain: 'lernenwing.firebaseapp.com',
    storageBucket: 'lernenwing.firebasestorage.app',
    measurementId: 'G-9GPF4PL5TX',
  );
}
