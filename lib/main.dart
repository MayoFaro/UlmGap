import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/env.dart';
import 'data/auth_service.dart';
import 'data/services.dart';
import 'data/user_repository.dart';
import 'features/auth/gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptionsFor(appEnv));
  runApp(AppServices(
    auth: FirebaseAuthService(),
    users: FirestoreUserRepository(),
    child: UlmGapApp(env: appEnv, home: const AppGate()),
  ));
}
