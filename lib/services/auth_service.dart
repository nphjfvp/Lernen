import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web-OAuth-Client-ID des Firebase-Projekts "lernenwing" (Firebase Console
/// → Authentication → Sign-in method → Google → "Web SDK configuration").
/// Auf Android braucht `google_sign_in` diese ID explizit – ohne
/// registrierte native Android-App im Firebase-Projekt (kein
/// google-services.json, siehe firebase_options.dart) kann das Package sie
/// nicht selbst auslesen. Kein Geheimnis, genau wie der API-Key in
/// firebase_options.dart: für clientseitige Nutzung gedacht.
const _googleServerClientId = '447278958302-vtordjpqk6j4keetbqa3l6bae244ejqf.apps.googleusercontent.com';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// E-Mail/Passwort- und Google-Anmeldung über Firebase Auth. Wie Cloud-Sync
/// komplett optional – ohne konfiguriertes Firebase-Projekt wirft jeder
/// Aufruf hier, die UI fängt das ab und die App bleibt ohne Account nutzbar.
///
/// Google-Sign-In läuft im Web über Firebases eigenen Popup-Flow (braucht
/// nur den in der Firebase-Console aktivierten Google-Provider). Auf
/// Android/iOS läuft es über das `google_sign_in`-Package, das dafür aber
/// eine echte, in der Firebase-Console registrierte Android-/iOS-App
/// (Package-Name + SHA-1 bzw. Bundle-ID) braucht – ohne das schlägt
/// [signInWithGoogle] dort mit einer verständlichen Fehlermeldung fehl.
class AuthService {
  /// Ob überhaupt ein Firebase-Projekt verbunden ist. Erst NACH diesem Check
  /// darf [FirebaseAuth.instance] angefasst werden – ohne registrierte App
  /// wirft schon der Getter, nicht erst ein Aufruf darauf.
  bool get isAvailable => Firebase.apps.isNotEmpty;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  bool _googleSignInInitialized = false;

  /// Leerer Strom (nie ein Event) statt eines echten Firebase-Streams, wenn
  /// kein Projekt verbunden ist – so bleibt [currentUser] dauerhaft null,
  /// ohne dass irgendwo [FirebaseAuth.instance] angefasst wird.
  Stream<User?> get authStateChanges => isAvailable ? _auth.authStateChanges() : const Stream.empty();
  User? get currentUser => isAvailable ? _auth.currentUser : null;

  void _requireAvailable() {
    if (!isAvailable) {
      throw AuthException('Kein Firebase-Projekt verbunden – Konten sind in diesem Build nicht verfügbar.');
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    _requireAvailable();
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    _requireAvailable();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<void> signInWithGoogle() async {
    _requireAvailable();
    try {
      if (kIsWeb) {
        await _auth.signInWithPopup(GoogleAuthProvider());
        return;
      }

      if (!_googleSignInInitialized) {
        await GoogleSignIn.instance.initialize(serverClientId: _googleServerClientId);
        _googleSignInInitialized = true;
      }
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw AuthException('Google-Anmeldung wird auf dieser Plattform nicht unterstützt.');
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw AuthException('Google hat keinen Anmelde-Token geliefert.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      throw AuthException('Google-Anmeldung fehlgeschlagen: ${e.description ?? e.code}');
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } on AuthException {
      rethrow;
    } catch (e) {
      // Auf Plattformen ohne google_sign_in-Implementierung (z.B. Windows)
      // wirft der Platform-Channel selbst statt eines GoogleSignInException –
      // ohne diesen Fang würde das als unbehandelte Exception durchschlagen.
      throw AuthException('Google-Anmeldung ist auf dieser Plattform nicht eingerichtet ($e).');
    }
  }

  Future<void> signOut() async {
    if (!isAvailable) return;
    await _auth.signOut();
    if (!kIsWeb && _googleSignInInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Bestenfalls aufräumen – der Firebase-Sign-out oben ist der, der zählt.
      }
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Für diese E-Mail existiert bereits ein Konto.';
      case 'invalid-email':
        return 'Ungültige E-Mail-Adresse.';
      case 'weak-password':
        return 'Passwort ist zu schwach (mind. 6 Zeichen).';
      case 'user-not-found':
      case 'invalid-credential':
        return 'Kein Konto mit diesen Zugangsdaten gefunden.';
      case 'wrong-password':
        return 'Falsches Passwort.';
      default:
        return e.message ?? 'Anmeldung fehlgeschlagen (${e.code}).';
    }
  }
}
