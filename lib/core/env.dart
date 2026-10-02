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

/// Clé VAPID des notifications web (console Firebase → Paramètres du projet
/// → Cloud Messaging → Certificats Web Push). Vide : pas de notifications sur
/// le web, sans erreur (plan 5).
const _webVapidKeyDev = '';
const _webVapidKeyProd = '';

String webVapidKeyFor(AppEnv env) => env == AppEnv.prod ? _webVapidKeyProd : _webVapidKeyDev;

/// Message d'erreur si le flavor de compilation (Android/iOS) ne correspond pas
/// à ENV ; null si tout concorde ou sans flavor (web).
String? flavorMismatch(AppEnv env, String? flavor) {
  if (flavor == null || flavor == env.name) return null;
  return 'Build incohérent : flavor « $flavor » mais ENV=${env.name}. '
      'Recompiler avec --flavor $flavor --dart-define=ENV=$flavor.';
}
