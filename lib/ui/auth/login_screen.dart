import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repositories/auth_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

/// E-Mail/Passwort- und Google-Anmeldung. Wird aus den Einstellungen
/// aufgerufen, nie erzwungen – die App bleibt ohne Account voll nutzbar.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Bitte E-Mail und Passwort eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<AuthRepository>();
      if (_isRegister) {
        await repo.signUpWithEmail(email, password);
      } else {
        await repo.signInWithEmail(email, password);
      }
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthRepository>().signInWithGoogle();
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? 'Konto erstellen' : 'Anmelden')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-Mail', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Passwort', border: OutlineInputBorder()),
            onSubmitted: (_) => _submitEmail(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submitEmail,
            child: Text(_isRegister ? 'Konto erstellen' : 'Anmelden'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _isRegister = !_isRegister),
            child: Text(_isRegister ? 'Schon ein Konto? Anmelden' : 'Noch kein Konto? Registrieren'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Divider(color: c.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('oder', style: TextStyle(color: c.inkMuted, fontSize: 12)),
              ),
              Expanded(child: Divider(color: c.border)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _submitGoogle,
            icon: const Icon(Icons.login),
            label: const Text('Mit Google anmelden'),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: c.danger), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
