import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptionsFor(appEnv));
  runApp(UlmGapApp(
    env: appEnv,
    home: const Scaffold(body: Center(child: Text('UlmGap'))),
  ));
}
