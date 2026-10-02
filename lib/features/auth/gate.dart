import 'package:flutter/material.dart';

import '../../data/app_user.dart';
import '../../data/auth_service.dart';
import '../../data/services.dart';
import '../home/home_shell.dart';
import '../home/push_registration.dart';
import 'login_screen.dart';
import 'no_access_screen.dart';
import 'verify_email_screen.dart';

enum GateState { signedOut, emailUnverified, noAccess, ready }

GateState gateFor(AuthSnapshot? auth, AppUser? user) {
  if (auth == null) return GateState.signedOut;
  if (!auth.emailVerified) return GateState.emailUnverified;
  if (user == null || !user.active) return GateState.noAccess;
  return GateState.ready;
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  Stream<AuthSnapshot?>? _authStream;
  // Écoute du document users mise en cache par uid : un événement Auth pour le
  // même utilisateur (rafraîchissement horaire du jeton…) ne la recrée pas, sinon
  // l'accueil repasserait par l'attente et perdrait son état.
  String? _uid;
  Stream<AppUser?>? _userStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authStream ??= AppServices.of(context).auth.changes();
  }

  Stream<AppUser?> _userStreamFor(String uid) {
    if (uid != _uid || _userStream == null) {
      _uid = uid;
      _userStream = AppServices.of(context).users.watchUser(uid);
    }
    return _userStream!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthSnapshot?>(
      stream: _authStream,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final auth = authSnap.data;
        if (auth == null) return const LoginScreen();
        if (!auth.emailVerified) return VerifyEmailScreen(email: auth.email);
        return StreamBuilder<AppUser?>(
          stream: _userStreamFor(auth.uid),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final user = userSnap.hasError ? null : userSnap.data;
            return gateFor(auth, user) == GateState.ready
                ? PushRegistration(uid: user!.uid, child: HomeShell(user: user))
                : const NoAccessScreen();
          },
        );
      },
    );
  }
}
