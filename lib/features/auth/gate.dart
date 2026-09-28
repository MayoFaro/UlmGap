import 'package:flutter/material.dart';

import '../../data/app_user.dart';
import '../../data/auth_service.dart';
import '../../data/services.dart';
import '../home/home_shell.dart';
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

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    return StreamBuilder<AuthSnapshot?>(
      stream: s.auth.changes(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final auth = authSnap.data;
        if (auth == null) return const LoginScreen();
        if (!auth.emailVerified) return VerifyEmailScreen(email: auth.email);
        return StreamBuilder<AppUser?>(
          stream: s.users.watchUser(auth.uid),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final user = userSnap.data;
            return gateFor(auth, user) == GateState.ready
                ? HomeShell(user: user!)
                : const NoAccessScreen();
          },
        );
      },
    );
  }
}
