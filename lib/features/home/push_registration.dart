// Inscription aux notifications push (plan 5) : une fois par compte, à
// l'arrivée sur l'accueil ; jeton renouvelé enregistré ; message reçu app
// ouverte affiché en SnackBar. Sans service (tests) ou en cas d'erreur :
// rien, l'accueil fonctionne normalement.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services.dart';

class PushRegistration extends StatefulWidget {
  const PushRegistration({super.key, required this.uid, required this.child});
  final String uid;
  final Widget child;

  @override
  State<PushRegistration> createState() => _PushRegistrationState();
}

class _PushRegistrationState extends State<PushRegistration> {
  final _subs = <StreamSubscription<Object?>>[];
  String? _registeredUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registeredUid != widget.uid) _register();
  }

  @override
  void didUpdateWidget(PushRegistration old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _register();
  }

  void _register() {
    final services = AppServices.of(context);
    final push = services.push;
    _registeredUid = widget.uid;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (push == null) return;
    final uid = widget.uid;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Future<void> save(String? token) async {
      if (token == null || token.isEmpty) return;
      try {
        await services.users.saveFcmToken(uid, token);
      } catch (_) {
        // Hors ligne : nouvel essai au prochain démarrage.
      }
    }

    push.token().then(save, onError: (Object _) {});
    _subs.add(push.onTokenRefresh.listen(save, onError: (Object _) {}));
    _subs.add(push.onForegroundMessage.listen(
      (m) => messenger?.showSnackBar(SnackBar(content: Text('${m.title} : ${m.body}'))),
      onError: (Object _) {},
    ));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
