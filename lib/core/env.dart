// Choix de l'environnement Firebase : --dart-define=ENV=dev|prod (dev par défaut).
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options_dev.dart' as dev;
import '../firebase_options_prod.dart' as prod;

enum AppEnv { dev, prod }

/// ENV=prod → prod ; toute autre valeur (ou absente) → dev.
AppEnv parseEnv(String raw) =>
    raw.trim().toLowerCase() == 'prod' ? AppEnv.prod : AppEnv.dev;

const String _rawEnv = String.fromEnvironment('ENV', defaultValue: 'dev');
final AppEnv appEnv = parseEnv(_rawEnv);

FirebaseOptions firebaseOptionsFor(AppEnv env) => env == AppEnv.prod
    ? prod.DefaultFirebaseOptions.currentPlatform
    : dev.DefaultFirebaseOptions.currentPlatform;
