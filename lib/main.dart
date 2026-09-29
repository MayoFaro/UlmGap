import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/env.dart';
import 'data/admin_api.dart';
import 'data/auth_service.dart';
import 'data/finance_api.dart';
import 'data/flight_api.dart';
import 'data/services.dart';
import 'data/user_repository.dart';
import 'features/auth/gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // M9 : ne jamais laisser l'app d'un environnement parler à la base de l'autre.
  final mismatch = flavorMismatch(appEnv, appFlavor);
  if (mismatch != null) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text(mismatch)),
        ),
      ),
    ));
    return;
  }
  await Firebase.initializeApp(options: firebaseOptionsFor(appEnv));
  runApp(AppServices(
    auth: FirebaseAuthService(),
    users: FirestoreUserRepository(),
    admin: FirebaseAdminApi(),
    flights: FirebaseFlightApi(),
    finance: FirebaseFinanceApi(),
    child: UlmGapApp(env: appEnv, home: const AppGate()),
  ));
}
