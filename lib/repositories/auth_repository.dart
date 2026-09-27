import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

/// Hält den aktuellen Anmelde-Status nach – ohne konfiguriertes Firebase
/// bleibt [currentUser] einfach dauerhaft null (App läuft ohne Account).
class AuthRepository extends ChangeNotifier {
  AuthRepository({AuthService? authService}) : _authService = authService ?? AuthService() {
    _subscription = _authService.authStateChanges.listen(
      (user) {
        _currentUser = user;
        notifyListeners();
      },
      onError: (_) {
        // Firebase nicht konfiguriert o.ä. – Account-Feature bleibt einfach inaktiv.
      },
    );
  }

  final AuthService _authService;
  StreamSubscription<User?>? _subscription;
  User? _currentUser;

  /// Direkt nach einer Anmeldung kann das Stream-Ereignis noch ausstehen –
  /// Firebase kennt den Nutzer aber schon (z.B. für das Cloud-Angebot gleich
  /// nach dem Login).
  User? get currentUser => _currentUser ?? _authService.currentUser;
  bool get isSignedIn => currentUser != null;
  bool get isAvailable => _authService.isAvailable;

  Future<void> signUpWithEmail(String email, String password) =>
      _authService.signUpWithEmail(email, password);

  Future<void> signInWithEmail(String email, String password) =>
      _authService.signInWithEmail(email, password);

  Future<void> signInWithGoogle() => _authService.signInWithGoogle();

  Future<void> linkEmailPassword(String email, String password) =>
      _authService.linkEmailPassword(email, password);

  Future<void> sendPasswordReset(String email) => _authService.sendPasswordReset(email);

  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
