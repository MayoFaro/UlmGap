import 'package:flutter/material.dart';

import '../../data/auth_service.dart';
import '../../data/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('UlmGap', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                ),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mot de passe'),
                ),
                const SizedBox(height: 16),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_message!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => auth.signIn(_email.text.trim(), _password.text)),
                  child: const Text('Se connecter'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final email = _email.text.trim();
                          if (email.isEmpty) {
                            setState(() => _message = 'Saisissez d\'abord votre e-mail.');
                            return;
                          }
                          _run(() async {
                            await auth.sendPasswordReset(email);
                            if (mounted) {
                              setState(() => _message = 'Lien envoyé à $email.');
                            }
                          });
                        },
                  child: const Text('Mot de passe oublié ?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
