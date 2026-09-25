# UlmGap, plan 1 : le socle (repo, dev/prod, connexion, comptes, appareils)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** poser le socle d'UlmGap. On obtient une app Flutter (Android, iOS,
web) branchée sur `ulmgap-dev` ou `ulmgap-prod`, avec connexion, vérification
d'e-mail et contrôle d'accès, des Cloud Functions d'administration (comptes,
appareils), des règles Firestore définitives et testées, et les écrans
d'administration des comptes et des appareils.

**Architecture :**
- Toute écriture métier passe par des **callables** (région `europe-west1`),
  et les règles Firestore interdisent les écritures directes.
- Côté serveur, chaque action est une fonction `handler(caller, data)`
  testable, enveloppée par `onCall`. La validation des entrées est un module
  pur.
- Côté client, l'app accède aux services derrière des interfaces
  (`AuthService`, `UserRepository`, `AdminApi`) fournies par un
  `InheritedWidget`. Les tests de widgets utilisent des doublures écrites à
  la main.

**Tech Stack :**
- Flutter 3.32.8 (**fvm**), firebase_core, firebase_auth, cloud_firestore,
  cloud_functions, flutter_localizations ;
- Cloud Functions v2 (Node 20, TypeScript), firebase-admin 12 ;
- tests `node:test`, émulateurs Firebase (Auth, Firestore),
  `@firebase/rules-unit-testing`.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md` (copiée
dans ce repo à la Task 1). Ce plan couvre les §1, §2.1 à §2.3, §5 (Accès,
Administration : utilisateurs et appareils) et §7. Les vols, les finances,
les compteurs et les notifications viendront dans les plans 2 à 5.

## Global Constraints

- Repo : `~/StudioProjects/UlmGAP`. Toujours `fvm flutter` et `fvm dart`,
  jamais `flutter` nu.
- Projets Firebase : `ulmgap-dev` (alias `dev`, **par défaut**) et
  `ulmgap-prod` (alias `prod`). Tout déploiement en prod est explicite
  (`--project prod`) et **fait par l'utilisateur**, jamais par l'agent.
- Environnement de l'app : `--dart-define=ENV=dev|prod`, **dev par défaut**.
  Android : `--flavor dev|prod` (`com.ulmgap.app.dev` / `com.ulmgap.app`).
- Région des Functions : `europe-west1`, identique côté serveur et client.
- Les clients n'écrivent jamais `users` (sauf `fcmToken` sur leur propre
  document), `profiles`, `aircraft`, `settings`, `flights`, `transactions`.
- « Connecté » = authentifié **et** e-mail vérifié **et**
  `users/{uid}.active == true`.
- Codes de profil : `instructeur`, `lache_toute_mission`, `lache_solo`,
  `eleve`. Appartenances : `GAP`, `GR`, `MIL`, `EXT`. Ils sont identiques en Dart et en
  TypeScript, vérifiés par `test/fixtures/referentials.json`.
- Libellés, couleurs et icônes des profils : **un seul fichier**,
  `lib/core/profiles.dart`.
- Textes de l'interface en français.
- Les règles Firestore déployées en prod sont celles du **mode test (ouvertes
  à tous jusqu'au 25/10/2026)**. L'utilisateur doit déployer les règles de la
  Task 6 en prod avant cette date (Task 9, étape finale).

## Review Focus

1. **Compte désactivé pendant une session** : l'accès doit être coupé
   aussitôt, à l'écran comme dans Firestore. → test `gateFor` (Task 7) et
   test de règles « inactif refusé » (Task 6).
2. **Connecté mais e-mail non vérifié** : aucun accès aux données, et un écran
   d'attente avec renvoi du lien. → test de règles (Task 6) et test
   `gateFor` (Task 7).
3. **Création d'un compte avec un e-mail déjà utilisé** : erreur claire, et
   aucun document `users` ou `profiles` orphelin. → test d'intégration
   (Task 5).
4. **Appel direct d'une fonction admin par un non-admin**, sans passer par
   l'UI : `permission-denied`. → test d'intégration (Task 5).
5. **Un admin qui se retire ses droits ou se désactive lui-même** : refusé,
   pour ne jamais se retrouver sans admin. → test d'intégration (Task 5).

---

## Carte des fichiers

| Fichier | Rôle |
|---|---|
| `.gitignore`, `README.md`, `docs/superpowers/specs/…` | Repo, rappel du contrat `flights` |
| `firebase.json`, `firestore.rules` | Émulateurs, Functions, règles définitives |
| `lib/core/env.dart` | Choix dev/prod |
| `lib/firebase_options_dev.dart`, `lib/firebase_options_prod.dart` | Générés par flutterfire |
| `lib/app.dart`, `lib/main.dart` | App racine, bandeau DEV, locale fr |
| `lib/core/profiles.dart`, `lib/core/profile_badge.dart` | Profils, catégories, badges |
| `lib/data/app_user.dart`, `lib/data/aircraft.dart` | Modèles |
| `lib/data/auth_service.dart`, `lib/data/user_repository.dart`, `lib/data/admin_api.dart` | Interfaces et implémentations Firebase |
| `lib/data/services.dart` | `AppServices` (InheritedWidget) |
| `lib/features/auth/…` | Gate, connexion, e-mail à vérifier, sans accès |
| `lib/features/home/home_shell.dart` | Accueil (planning à venir) et menu admin |
| `lib/features/admin/…` | Comptes et appareils |
| `functions/…` | Validation, gardes, callables admin, tests |
| `functions/scripts/bootstrap-admin.js` | Création du premier admin |
| `test/…`, `test/fixtures/referentials.json` | Tests Dart, référentiels partagés |

---

### Task 1 : initialisation du repo et support web

**Files :**
- Modify: `.gitignore`
- Create: `README.md` (remplace le fichier généré), `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md` (copie)
- Create (généré): `web/`

- [ ] **Step 1 : compléter `.gitignore`**

Le fichier actuel ne contient que le modèle Firebase. Ajouter à la fin :

```
# Flutter / Dart
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
*.iml
.idea/
.fvm/flutter_sdk
coverage/

# Functions
functions/node_modules/
functions/lib/

# Secrets locaux
functions/.env
*.jks
*.keystore
```

- [ ] **Step 2 : activer le web**

Run : `cd ~/StudioProjects/UlmGAP && fvm flutter create --platforms web .`
Expected : le dossier `web/` est créé. Si la commande crée
`test/widget_test.dart`, le supprimer (il référence une classe qui
n'existe pas) : `rm -f test/widget_test.dart`.

- [ ] **Step 3 : copier la spec et écrire le README**

Run : `mkdir -p docs/superpowers/specs && cp ~/StudioProjects/app_gap/docs/superpowers/specs/2026-09-25-ulmgap-app-design.md docs/superpowers/specs/`

`README.md` :

```markdown
# UlmGap

Gestion des vols ULM (Android, iOS, web). Spec :
`docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`.

## Environnements

| Env | Projet Firebase | Lancer |
|---|---|---|
| dev (défaut) | `ulmgap-dev` | `fvm flutter run --flavor dev --dart-define=ENV=dev` (web : sans `--flavor`) |
| prod | `ulmgap-prod` | `fvm flutter run --flavor prod --dart-define=ENV=prod` |

Déploiement : `firebase deploy --project dev ...`. La prod se déploie
**toujours explicitement** avec `--project prod`.

## Contrat avec AppGAP (NE PAS CASSER)

Le pont AppGAP (`syncUlmFlights`) lit la collection `flights` de
`ulmgap-prod`. Ces champs ne doivent ni changer de nom ni de sens :
`start`, `end`, `destination`, `aircraft` (immatriculation), `crew` (uid),
`passengers` (noms), `status` (`demande`/`valide`/`refuse`), `isClosed`,
`actualFlightMinutes`, `deleted` (suppression logique uniquement),
`updatedAt` (horodatage serveur à chaque écriture). Voir la spec §2.5 et §8.
```

- [ ] **Step 4 : vérifier**

Run : `fvm flutter analyze && fvm flutter build web --debug`
Expected : aucune erreur d'analyse, build web réussi.

- [ ] **Step 5 : premier commit**

```bash
cd ~/StudioProjects/UlmGAP
git init -b main
git add -A
git commit -m "chore: bootstrap UlmGap repo (Flutter, web, Firebase dev/prod aliases, spec)"
```

---

### Task 2 : Firebase dev/prod dans l'app

**Files :**
- Modify: `pubspec.yaml`, `lib/main.dart`
- Create: `lib/core/env.dart`, `lib/app.dart`, `lib/firebase_options_dev.dart`, `lib/firebase_options_prod.dart` (générés)
- Test: `test/core/env_test.dart`, `test/app_test.dart`

**Interfaces :**
- Produces : `enum AppEnv { dev, prod }`, `AppEnv parseEnv(String raw)`,
  `final AppEnv appEnv`, `FirebaseOptions firebaseOptionsFor(AppEnv env)`,
  `class UlmGapApp extends StatelessWidget { UlmGapApp({required AppEnv env, required Widget home}) }`.

- [ ] **Step 1 : dépendances**

Run : `fvm flutter pub add firebase_core firebase_auth cloud_firestore cloud_functions intl && fvm flutter pub add flutter_localizations --sdk=flutter`
Expected : dépendances résolues.

- [ ] **Step 2 : générer les configurations Firebase**

Ces commandes **créent des applications** dans les projets Firebase (iOS et
web). Les applications Android `com.ulmgap.app.dev` et `com.ulmgap.app`
existent déjà : flutterfire les **réutilise**, et réécrit
`google-services.json` au même endroit, avec le même contenu. Le plugin Gradle
Google Services est déjà en place. iOS utilise pour l'instant le même bundle
ID en dev et en prod : c'est le `--dart-define` qui choisit le projet. Si
l'agent n'a pas le droit de lancer ces commandes, les faire exécuter par
l'utilisateur.

```bash
cd ~/StudioProjects/UlmGAP
flutterfire configure --project=ulmgap-dev --out=lib/firebase_options_dev.dart \
  --platforms=android,ios,web --android-package-name=com.ulmgap.app.dev \
  --ios-bundle-id=com.ulmgap.ulmgap --android-out=android/app/src/dev/google-services.json --yes
flutterfire configure --project=ulmgap-prod --out=lib/firebase_options_prod.dart \
  --platforms=android,ios,web --android-package-name=com.ulmgap.app \
  --ios-bundle-id=com.ulmgap.ulmgap --android-out=android/app/src/prod/google-services.json --yes
```

Expected : les deux fichiers `lib/firebase_options_*.dart` existent.

- [ ] **Step 3 : écrire les tests qui doivent échouer**

`test/core/env_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/env.dart';

void main() {
  test('prod seulement si ENV=prod (casse et espaces ignorés)', () {
    expect(parseEnv('prod'), AppEnv.prod);
    expect(parseEnv(' PROD '), AppEnv.prod);
  });
  test('tout le reste → dev (défaut sûr)', () {
    expect(parseEnv('dev'), AppEnv.dev);
    expect(parseEnv(''), AppEnv.dev);
    expect(parseEnv('production'), AppEnv.dev);
  });
}
```

`test/app_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/app.dart';
import 'package:ulmgap/core/env.dart';

void main() {
  testWidgets('bandeau DEV visible en dev', (tester) async {
    await tester.pumpWidget(const UlmGapApp(env: AppEnv.dev, home: Text('x')));
    expect(find.text('DEV'), findsOneWidget);
  });
  testWidgets('pas de bandeau en prod', (tester) async {
    await tester.pumpWidget(const UlmGapApp(env: AppEnv.prod, home: Text('x')));
    expect(find.text('DEV'), findsNothing);
  });
}
```

- [ ] **Step 4 : lancer les tests pour vérifier qu'ils échouent**

Run : `fvm flutter test test/core/env_test.dart test/app_test.dart`
Expected : FAIL, car `env.dart` et `app.dart` n'existent pas.

- [ ] **Step 5 : implémenter**

`lib/core/env.dart` :

```dart
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
```

`lib/app.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/env.dart';

/// Couleur de marque UlmGap (orange ULM).
const Color kBrandColor = Color(0xFFEF6C00);

class UlmGapApp extends StatelessWidget {
  const UlmGapApp({super.key, required this.env, required this.home});

  final AppEnv env;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UlmGap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: kBrandColor, useMaterial3: true),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => env == AppEnv.dev
          ? Banner(
              message: 'DEV',
              location: BannerLocation.topEnd,
              child: child ?? const SizedBox.shrink(),
            )
          : child ?? const SizedBox.shrink(),
      home: home,
    );
  }
}
```

`lib/main.dart` (provisoire ; la Task 7 remplacera `home`) :

```dart
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
```

- [ ] **Step 6 : lancer les tests**

Run : `fvm flutter test test/core/env_test.dart test/app_test.dart && fvm flutter analyze`
Expected : PASS (4 tests), aucune erreur d'analyse.

- [ ] **Step 7 : commit**

```bash
git add pubspec.yaml pubspec.lock lib test android ios web
git commit -m "feat: dev/prod Firebase configuration with DEV banner"
```

---

### Task 3 : profils, catégories et badges

**Files :**
- Create: `lib/core/profiles.dart`, `lib/core/profile_badge.dart`, `test/fixtures/referentials.json`
- Test: `test/core/profiles_test.dart`

**Interfaces :**
- Produces : `enum PilotProfile { instructeur, lacheToutesMissions, lacheSolo, eleve }`
  avec `code`, `label`, `color`, `icon` et `static PilotProfile? fromCode(String?)` ;
  `enum UserCategory { gap, gr, mil, ext }` avec `code` et
  `static UserCategory fromCode(String?)` (inconnu → `ext`) ;
  `class ProfileBadge extends StatelessWidget { ProfileBadge({required PilotProfile? profile, bool compact = false}) }`.

- [ ] **Step 1 : référentiels partagés**

`test/fixtures/referentials.json` :

```json
{
  "profiles": ["instructeur", "lache_toute_mission", "lache_solo", "eleve"],
  "categories": ["GAP", "GR", "MIL", "EXT"]
}
```

- [ ] **Step 2 : écrire les tests qui doivent échouer**

`test/core/profiles_test.dart` :

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/profile_badge.dart';
import 'package:ulmgap/core/profiles.dart';

void main() {
  final ref = jsonDecode(File('test/fixtures/referentials.json').readAsStringSync())
      as Map<String, dynamic>;

  test('codes de profil = référentiel partagé', () {
    expect(PilotProfile.values.map((p) => p.code).toList(), ref['profiles']);
  });

  test('codes de catégorie = référentiel partagé', () {
    expect(UserCategory.values.map((c) => c.code).toList(), ref['categories']);
  });

  test('fromCode', () {
    expect(PilotProfile.fromCode('lache_solo'), PilotProfile.lacheSolo);
    expect(PilotProfile.fromCode(null), isNull);
    expect(PilotProfile.fromCode('inconnu'), isNull);
    expect(UserCategory.fromCode('GR'), UserCategory.gr);
    expect(UserCategory.fromCode('MIL'), UserCategory.mil);
    expect(UserCategory.fromCode('???'), UserCategory.ext);
  });

  testWidgets('badge complet : icône et libellé', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileBadge(profile: PilotProfile.eleve)),
    ));
    expect(find.text('Élève'), findsOneWidget);
    expect(find.byIcon(PilotProfile.eleve.icon), findsOneWidget);
  });

  testWidgets('badge compact : icône seule, libellé en infobulle', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileBadge(profile: PilotProfile.instructeur, compact: true)),
    ));
    expect(find.text('Instructeur'), findsNothing);
    expect(find.byTooltip('Instructeur'), findsOneWidget);
  });

  testWidgets('pas de profil : rien', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileBadge(profile: null)),
    ));
    expect(find.byType(Icon), findsNothing);
  });
}
```

- [ ] **Step 3 : lancer les tests pour vérifier qu'ils échouent**

Run : `fvm flutter test test/core/profiles_test.dart`
Expected : FAIL, car les fichiers n'existent pas.

- [ ] **Step 4 : implémenter**

`lib/core/profiles.dart` :

```dart
// Profils pilote et catégories. SEUL endroit où vivent libellés, couleurs et
// icônes : les renommer ne touche pas aux données (seuls les codes sont stockés).
import 'package:flutter/material.dart';

enum PilotProfile {
  instructeur('instructeur', 'Instructeur', Color(0xFF7B1FA2), Icons.workspace_premium),
  lacheToutesMissions(
      'lache_toute_mission', 'Lâché toute mission', Color(0xFF2E7D32), Icons.flight),
  lacheSolo('lache_solo', 'Lâché solo', Color(0xFF1565C0), Icons.flight_takeoff),
  eleve('eleve', 'Élève', Color(0xFFEF6C00), Icons.school);

  const PilotProfile(this.code, this.label, this.color, this.icon);

  final String code;
  final String label;
  final Color color;
  final IconData icon;

  static PilotProfile? fromCode(String? code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

enum UserCategory {
  gap('GAP'),
  gr('GR'),
  mil('MIL'),
  ext('EXT');

  const UserCategory(this.code);

  final String code;

  /// Code inconnu → EXT (forfait le plus élevé : choix sûr).
  static UserCategory fromCode(String? code) =>
      values.firstWhere((c) => c.code == code, orElse: () => UserCategory.ext);
}
```

`lib/core/profile_badge.dart` :

```dart
import 'package:flutter/material.dart';

import 'profiles.dart';

/// Badge visuel du profil pilote, affiché à côté du nom.
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({super.key, required this.profile, this.compact = false});

  final PilotProfile? profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) return const SizedBox.shrink();
    if (compact) {
      return Tooltip(
        message: p.label,
        child: CircleAvatar(
          radius: 11,
          backgroundColor: p.color.withValues(alpha: 0.15),
          child: Icon(p.icon, size: 14, color: p.color),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: p.color.withValues(alpha: 0.12),
        border: Border.all(color: p.color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(p.icon, size: 14, color: p.color),
          const SizedBox(width: 4),
          Text(p.label, style: TextStyle(color: p.color, fontSize: 12)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5 : lancer les tests**

Run : `fvm flutter test test/core/profiles_test.dart`
Expected : PASS (6 tests).

- [ ] **Step 6 : commit**

```bash
git add lib/core/profiles.dart lib/core/profile_badge.dart test/core/profiles_test.dart test/fixtures/referentials.json
git commit -m "feat: pilot profiles, categories and profile badges"
```

---

### Task 4 : projet Functions et validation des entrées admin

**Files :**
- Create: `functions/package.json`, `functions/tsconfig.json`, `functions/scripts/run-tests.js`, `functions/src/index.ts`, `functions/src/admin/validation.ts`
- Modify: `firebase.json`
- Test: `functions/src/admin/validation.test.ts`

**Interfaces :**
- Produces : `PROFILES`, `CATEGORIES` (tableaux `as const`), les types `Profile`
  et `Category`, `class ValidationError extends Error`,
  `interface UserInput { email; displayName; shortName; profile: Profile | null; category: Category; isAdmin: boolean; active: boolean }`,
  `validateNewUser(data: unknown): UserInput`,
  `validateUserPatch(data: unknown): { uid: string; patch: Partial<Omit<UserInput, "email">> }`,
  `validateAircraft(data: unknown): { id?: string; registration: string; label: string; active: boolean }`.

- [ ] **Step 1 : squelette du projet Functions**

`functions/package.json` :

```json
{
  "name": "functions",
  "private": true,
  "main": "lib/index.js",
  "engines": { "node": "20" },
  "scripts": {
    "build": "tsc",
    "test": "tsc && node scripts/run-tests.js unit",
    "test:int": "tsc && firebase emulators:exec --project demo-ulmgap --only auth,firestore \"node scripts/run-tests.js int\""
  },
  "dependencies": {
    "firebase-admin": "^12.7.0",
    "firebase-functions": "^6.4.0"
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^3.0.4",
    "@types/node": "^20.14.0",
    "firebase": "^10.14.0",
    "typescript": "^5.5.4"
  }
}
```

`functions/tsconfig.json` :

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"],
    "module": "commonjs",
    "moduleResolution": "node",
    "rootDir": "src",
    "outDir": "lib",
    "strict": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "sourceMap": true
  },
  "include": ["src"]
}
```

`functions/scripts/run-tests.js`. Node 20 n'accepte pas les globs, d'où ce
petit lanceur :

```js
// Lance node --test sur lib/**/*.test.js (unit) ou lib/**/*.int.test.js (int).
const { readdirSync, statSync } = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const kind = process.argv[2]; // "unit" | "int"
function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = path.join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}
const files = walk(path.join(__dirname, "..", "lib")).filter((f) =>
  kind === "int" ? f.endsWith(".int.test.js") :
    f.endsWith(".test.js") && !f.endsWith(".int.test.js"));
if (files.length === 0) {
  console.log(`Aucun test ${kind}.`);
  process.exit(0);
}
const r = spawnSync(process.execPath, ["--test", ...files], { stdio: "inherit" });
process.exit(r.status ?? 1);
```

`functions/src/index.ts` (les exports s'ajoutent à la Task 5) :

```ts
import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";

if (admin.apps.length === 0) admin.initializeApp();

// Même région côté client (FirebaseFunctions.instanceFor(region: 'europe-west1')).
setGlobalOptions({ region: "europe-west1" });
```

Dans `firebase.json`, ajouter au premier niveau, à côté de `firestore` et
`storage` :

```json
  "functions": [
    {
      "source": "functions",
      "codebase": "default",
      "ignore": ["node_modules", ".git", "firebase-debug.log", "*.local"],
      "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"]
    }
  ],
  "emulators": {
    "auth": { "port": 9099 },
    "firestore": { "port": 8080 },
    "functions": { "port": 5001 },
    "ui": { "enabled": false }
  }
```

Run : `cd functions && npm install`
Expected : installation sans erreur.

- [ ] **Step 2 : écrire les tests qui doivent échouer**

`functions/src/admin/validation.test.ts` :

```ts
import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  CATEGORIES, PROFILES, ValidationError,
  validateAircraft, validateNewUser, validateUserPatch,
} from "./validation";

const ref = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, "../../../test/fixtures/referentials.json"), "utf8"));

test("référentiels = fixture partagée avec Dart", () => {
  assert.deepEqual([...PROFILES], ref.profiles);
  assert.deepEqual([...CATEGORIES], ref.categories);
});

const ok = {
  email: " Pilote@Club.FR ", displayName: " Jean Dupont ", shortName: "jdu",
  profile: "eleve", category: "EXT",
};

test("validateNewUser : normalise et applique les défauts", () => {
  assert.deepEqual(validateNewUser(ok), {
    email: "pilote@club.fr", displayName: "Jean Dupont", shortName: "JDU",
    profile: "eleve", category: "EXT", isAdmin: false, active: true,
  });
});

test("validateNewUser : profil null accepté (gestionnaire non pilote)", () => {
  assert.equal(validateNewUser({ ...ok, profile: null }).profile, null);
});

test("validateNewUser : rejets", () => {
  for (const bad of [
    { ...ok, email: "pas-un-mail" },
    { ...ok, displayName: "  " },
    { ...ok, shortName: "J" },
    { ...ok, shortName: "JDUPO" },
    { ...ok, shortName: "J-D" },
    { ...ok, profile: "pilote" },
    { ...ok, category: "XX" },
    { ...ok, isAdmin: "oui" },
    null,
  ]) {
    assert.throws(() => validateNewUser(bad), ValidationError, JSON.stringify(bad));
  }
});

test("validateUserPatch : ne garde que les champs fournis, email interdit", () => {
  assert.deepEqual(validateUserPatch({ uid: "u1", category: "GR", active: false }),
    { uid: "u1", patch: { category: "GR", active: false } });
  assert.throws(() => validateUserPatch({ uid: "u1", email: "a@b.fr" }), ValidationError);
  assert.throws(() => validateUserPatch({ category: "GR" }), ValidationError);
  assert.throws(() => validateUserPatch({ uid: "u1" }), ValidationError);
});

test("validateAircraft : normalise, défauts, rejets", () => {
  assert.deepEqual(validateAircraft({ registration: " f-jabc ", label: " ULM 1 " }),
    { registration: "F-JABC", label: "ULM 1", active: true });
  assert.equal(validateAircraft({ id: "a1", registration: "F-JABC", label: "x", active: false }).id, "a1");
  assert.throws(() => validateAircraft({ registration: "", label: "x" }), ValidationError);
  assert.throws(() => validateAircraft({ registration: "F-JABC", label: "" }), ValidationError);
});
```

- [ ] **Step 3 : lancer les tests pour vérifier qu'ils échouent**

Run : `cd functions && npm test`
Expected : FAIL à la compilation, car `./validation` est introuvable.

- [ ] **Step 4 : implémenter**

`functions/src/admin/validation.ts` :

```ts
// Validation (pure) des entrées des fonctions d'administration.
// Codes identiques à lib/core/profiles.dart (fixture test/fixtures/referentials.json).
export const PROFILES = ["instructeur", "lache_toute_mission", "lache_solo", "eleve"] as const;
export const CATEGORIES = ["GAP", "GR", "MIL", "EXT"] as const;
export type Profile = typeof PROFILES[number];
export type Category = typeof CATEGORIES[number];

export class ValidationError extends Error {}

export interface UserInput {
  email: string;
  displayName: string;
  shortName: string;
  profile: Profile | null;
  category: Category;
  isAdmin: boolean;
  active: boolean;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SHORT_RE = /^[A-Z0-9]{2,4}$/;

function obj(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== "object") throw new ValidationError("Données manquantes.");
  return data as Record<string, unknown>;
}

function text(v: unknown, field: string, max: number): string {
  const s = typeof v === "string" ? v.trim() : "";
  if (!s || s.length > max) throw new ValidationError(`${field} invalide.`);
  return s;
}

function bool(v: unknown, field: string, dflt: boolean): boolean {
  if (v === undefined) return dflt;
  if (typeof v !== "boolean") throw new ValidationError(`${field} invalide.`);
  return v;
}

function shortName(v: unknown): string {
  const s = typeof v === "string" ? v.trim().toUpperCase() : "";
  if (!SHORT_RE.test(s)) throw new ValidationError("Code court invalide (2 à 4 lettres ou chiffres).");
  return s;
}

function profile(v: unknown): Profile | null {
  if (v === null || v === undefined) return null;
  if (!PROFILES.includes(v as Profile)) throw new ValidationError("Profil invalide.");
  return v as Profile;
}

function category(v: unknown): Category {
  if (!CATEGORIES.includes(v as Category)) throw new ValidationError("Catégorie invalide.");
  return v as Category;
}

export function validateNewUser(data: unknown): UserInput {
  const d = obj(data);
  const email = typeof d.email === "string" ? d.email.trim().toLowerCase() : "";
  if (!EMAIL_RE.test(email)) throw new ValidationError("E-mail invalide.");
  return {
    email,
    displayName: text(d.displayName, "Nom", 80),
    shortName: shortName(d.shortName),
    profile: profile(d.profile),
    category: category(d.category),
    isAdmin: bool(d.isAdmin, "Admin", false),
    active: bool(d.active, "Actif", true),
  };
}

export function validateUserPatch(data: unknown): {
  uid: string; patch: Partial<Omit<UserInput, "email">>;
} {
  const d = obj(data);
  const uid = typeof d.uid === "string" ? d.uid.trim() : "";
  if (!uid) throw new ValidationError("Utilisateur manquant.");
  if ("email" in d) throw new ValidationError("L'e-mail ne peut pas être modifié.");
  const patch: Partial<Omit<UserInput, "email">> = {};
  if ("displayName" in d) patch.displayName = text(d.displayName, "Nom", 80);
  if ("shortName" in d) patch.shortName = shortName(d.shortName);
  if ("profile" in d) patch.profile = profile(d.profile);
  if ("category" in d) patch.category = category(d.category);
  if ("isAdmin" in d) patch.isAdmin = bool(d.isAdmin, "Admin", false);
  if ("active" in d) patch.active = bool(d.active, "Actif", true);
  if (Object.keys(patch).length === 0) throw new ValidationError("Aucune modification.");
  return { uid, patch };
}

export function validateAircraft(data: unknown): {
  id?: string; registration: string; label: string; active: boolean;
} {
  const d = obj(data);
  const out: { id?: string; registration: string; label: string; active: boolean } = {
    registration: text(d.registration, "Immatriculation", 12).toUpperCase(),
    label: text(d.label, "Libellé", 40),
    active: bool(d.active, "Actif", true),
  };
  if (typeof d.id === "string" && d.id.trim()) out.id = d.id.trim();
  return out;
}
```

- [ ] **Step 5 : lancer les tests**

Run : `cd functions && npm test`
Expected : PASS (6 tests).

- [ ] **Step 6 : commit**

```bash
git add firebase.json functions/package.json functions/package-lock.json functions/tsconfig.json functions/scripts functions/src
git commit -m "feat(functions): project scaffold and admin input validation"
```

---

### Task 5 : fonctions d'administration (comptes, appareils) et tests d'intégration

**Files :**
- Create: `functions/src/auth/guards.ts`, `functions/src/admin/users.ts`, `functions/src/admin/aircraft.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/admin/admin.int.test.ts`

**Interfaces :**
- Consumes : `validateNewUser`, `validateUserPatch`, `validateAircraft`,
  `ValidationError` (Task 4).
- Produces :
  - `interface Caller { uid: string; token: { email_verified?: boolean } }` ;
  - `requireAdmin(db, caller)` ;
  - `createUser(caller, data): Promise<{ uid: string }>` ;
  - `updateUser(caller, data): Promise<void>` ;
  - `upsertAircraft(caller, data): Promise<{ id: string }>` ;
  - les callables `adminCreateUser`, `adminUpdateUser`, `adminUpsertAircraft`
    (région `europe-west1`).
- Données écrites :
  - `users/{uid}` = UserInput + `balance: 0`, `fcmToken: null`, `createdAt`, `updatedAt` ;
  - `profiles/{uid}` = `{ displayName, shortName, profile, active }` ;
  - `aircraft/{id}` = `{ registration, label, active, updatedAt }`.

- [ ] **Step 1 : écrire les tests d'intégration qui doivent échouer**

`functions/src/admin/admin.int.test.ts` :

```ts
// Lancé par `npm run test:int` (émulateurs Auth + Firestore, projet demo-ulmgap).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "demo-ulmgap" });
}
import { createUser, updateUser } from "./users";
import { upsertAircraft } from "./aircraft";
import type { Caller } from "../auth/guards";

const db = admin.firestore();
const uniq = () => Math.random().toString(36).slice(2, 8);
const code = (e: unknown) => (e as { code?: string }).code;

async function seedUser(uid: string, fields: Record<string, unknown>): Promise<Caller> {
  await db.collection("users").doc(uid).set({ active: true, isAdmin: false, ...fields });
  return { uid, token: { email_verified: true } };
}
const newUser = () => ({
  email: `p-${uniq()}@club.fr`, displayName: "Jean Dupont", shortName: "JDU",
  profile: "eleve", category: "EXT",
});

test("non-admin : permission-denied (appel direct, hors UI)", async () => {
  const me = await seedUser(`u-${uniq()}`, {});
  await assert.rejects(createUser(me, newUser()), (e) => code(e) === "permission-denied");
});

test("admin à e-mail non vérifié : permission-denied", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(createUser({ ...me, token: { email_verified: false } }, newUser()),
    (e) => code(e) === "permission-denied");
});

test("admin désactivé : permission-denied", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true, active: false });
  await assert.rejects(createUser(me, newUser()), (e) => code(e) === "permission-denied");
});

test("création : Auth, users et profiles cohérents", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const input = newUser();
  const { uid } = await createUser(me, input);
  const rec = await admin.auth().getUser(uid);
  assert.equal(rec.email, input.email);
  const u = (await db.collection("users").doc(uid).get()).data()!;
  assert.equal(u.shortName, "JDU");
  assert.equal(u.balance, 0);
  assert.equal(u.isAdmin, false);
  const p = (await db.collection("profiles").doc(uid).get()).data()!;
  assert.deepEqual(p, { displayName: "Jean Dupont", shortName: "JDU", profile: "eleve", active: true });
});

test("e-mail déjà utilisé : already-exists, aucun document orphelin", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const input = newUser();
  await createUser(me, input);
  const before = (await db.collection("users").where("email", "==", input.email).get()).size;
  await assert.rejects(createUser(me, input), (e) => code(e) === "already-exists");
  const after = (await db.collection("users").where("email", "==", input.email).get()).size;
  assert.equal(after, before);
});

test("entrée invalide : invalid-argument", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(createUser(me, { ...newUser(), category: "XX" }),
    (e) => code(e) === "invalid-argument");
});

test("désactivation : Auth disabled et profiles.active à false", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const { uid } = await createUser(me, newUser());
  await updateUser(me, { uid, active: false, category: "GR" });
  assert.equal((await admin.auth().getUser(uid)).disabled, true);
  assert.equal((await db.collection("profiles").doc(uid).get()).get("active"), false);
  assert.equal((await db.collection("users").doc(uid).get()).get("category"), "GR");
});

test("un admin ne peut ni se retirer ses droits ni se désactiver", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(updateUser(me, { uid: me.uid, isAdmin: false }),
    (e) => code(e) === "failed-precondition");
  await assert.rejects(updateUser(me, { uid: me.uid, active: false }),
    (e) => code(e) === "failed-precondition");
});

test("mise à jour d'un compte inexistant : not-found", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(updateUser(me, { uid: "nope", category: "GR" }),
    (e) => code(e) === "not-found");
});

test("appareils : création, modification, immatriculation en double refusée", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const reg = `F-${uniq().toUpperCase().slice(0, 4)}`;
  const { id } = await upsertAircraft(me, { registration: reg, label: "ULM 1" });
  await upsertAircraft(me, { id, registration: reg, label: "ULM 1 bis", active: false });
  const a = (await db.collection("aircraft").doc(id).get()).data()!;
  assert.equal(a.label, "ULM 1 bis");
  assert.equal(a.active, false);
  await assert.rejects(upsertAircraft(me, { registration: reg, label: "Autre" }),
    (e) => code(e) === "already-exists");
});
```

- [ ] **Step 2 : lancer les tests pour vérifier qu'ils échouent**

Run : `cd functions && npm run test:int`
Expected : FAIL à la compilation, car `./users`, `./aircraft` et
`../auth/guards` sont introuvables.

- [ ] **Step 3 : implémenter la garde**

`functions/src/auth/guards.ts` :

```ts
import { HttpsError } from "firebase-functions/v2/https";

export interface Caller { uid: string; token: { email_verified?: boolean } }

/** Connecté, e-mail vérifié, compte actif et admin, sinon HttpsError. */
export async function requireAdmin(
  db: FirebaseFirestore.Firestore,
  caller: Caller | undefined,
): Promise<void> {
  if (!caller) throw new HttpsError("unauthenticated", "Connexion requise.");
  if (caller.token.email_verified !== true) {
    throw new HttpsError("permission-denied", "E-mail non vérifié.");
  }
  const me = await db.collection("users").doc(caller.uid).get();
  if (!me.exists || me.get("active") !== true || me.get("isAdmin") !== true) {
    throw new HttpsError("permission-denied", "Réservé aux administrateurs.");
  }
}
```

- [ ] **Step 4 : implémenter les comptes**

`functions/src/admin/users.ts` :

```ts
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { ValidationError, validateNewUser, validateUserPatch } from "./validation";

function asInvalid<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof ValidationError) throw new HttpsError("invalid-argument", e.message);
    throw e;
  }
}

export async function createUser(caller: Caller | undefined, data: unknown): Promise<{ uid: string }> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const input = asInvalid(() => validateNewUser(data));

  let uid: string;
  try {
    const rec = await admin.auth().createUser({
      email: input.email, displayName: input.displayName, disabled: !input.active,
    });
    uid = rec.uid;
  } catch (e) {
    if ((e as { code?: string }).code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Un compte existe déjà pour cet e-mail.");
    }
    throw e;
  }

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    batch.set(db.collection("users").doc(uid), {
      ...input, balance: 0, fcmToken: null, createdAt: now, updatedAt: now,
    });
    batch.set(db.collection("profiles").doc(uid), {
      displayName: input.displayName, shortName: input.shortName,
      profile: input.profile, active: input.active,
    });
    await batch.commit();
  } catch (e) {
    await admin.auth().deleteUser(uid); // pas de compte Auth sans document
    throw e;
  }
  return { uid };
}

export async function updateUser(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const { uid, patch } = asInvalid(() => validateUserPatch(data));
  if (uid === caller!.uid && (patch.isAdmin === false || patch.active === false)) {
    throw new HttpsError("failed-precondition",
      "Vous ne pouvez pas retirer vos propres droits d'admin ni désactiver votre compte.");
  }
  const ref = db.collection("users").doc(uid);
  if (!(await ref.get()).exists) throw new HttpsError("not-found", "Compte introuvable.");

  const batch = db.batch();
  batch.update(ref, { ...patch, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  const pub: Record<string, unknown> = {};
  for (const k of ["displayName", "shortName", "profile", "active"] as const) {
    if (k in patch) pub[k] = patch[k];
  }
  if (Object.keys(pub).length > 0) batch.set(db.collection("profiles").doc(uid), pub, { merge: true });
  await batch.commit();

  const authPatch: admin.auth.UpdateRequest = {};
  if (patch.active !== undefined) authPatch.disabled = !patch.active;
  if (patch.displayName !== undefined) authPatch.displayName = patch.displayName;
  if (Object.keys(authPatch).length > 0) await admin.auth().updateUser(uid, authPatch);
}

export const adminCreateUser = onCall((req) =>
  createUser(req.auth as Caller | undefined, req.data));
export const adminUpdateUser = onCall((req) =>
  updateUser(req.auth as Caller | undefined, req.data));
```

- [ ] **Step 5 : implémenter les appareils**

`functions/src/admin/aircraft.ts` :

```ts
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { ValidationError, validateAircraft } from "./validation";

export async function upsertAircraft(caller: Caller | undefined, data: unknown): Promise<{ id: string }> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  let a: ReturnType<typeof validateAircraft>;
  try {
    a = validateAircraft(data);
  } catch (e) {
    if (e instanceof ValidationError) throw new HttpsError("invalid-argument", e.message);
    throw e;
  }
  const col = db.collection("aircraft");
  const ref = a.id ? col.doc(a.id) : col.doc();
  if (a.id && !(await ref.get()).exists) throw new HttpsError("not-found", "Appareil introuvable.");

  const same = await col.where("registration", "==", a.registration).get();
  if (same.docs.some((d) => d.id !== ref.id)) {
    throw new HttpsError("already-exists", "Cette immatriculation existe déjà.");
  }
  await ref.set({
    registration: a.registration, label: a.label, active: a.active,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { id: ref.id };
}

export const adminUpsertAircraft = onCall((req) =>
  upsertAircraft(req.auth as Caller | undefined, req.data));
```

- [ ] **Step 6 : exporter**

À la fin de `functions/src/index.ts`, ajouter :

```ts
export { adminCreateUser, adminUpdateUser } from "./admin/users";
export { adminUpsertAircraft } from "./admin/aircraft";
```

- [ ] **Step 7 : lancer les tests**

Run : `cd functions && npm test && npm run test:int`
Expected : les tests unitaires restent verts, et les tests d'intégration
passent (10 tests). Les fichiers d'intégration tournent en parallèle, d'où
des identifiants de projet distincts : `demo-ulmgap` ici, `demo-ulmgap-rules`
pour les règles (Task 6), sans `singleProjectMode`. Si l'émulateur ne démarre pas, vérifier que Java 17 est
disponible (`java -version`).

- [ ] **Step 8 : commit**

```bash
git add functions/src
git commit -m "feat(functions): admin callables for accounts and aircraft"
```

---

### Task 6 : règles Firestore définitives et leurs tests

**Files :**
- Modify: `firestore.rules` (remplacement complet des règles du mode test)
- Test: `functions/src/security/firestore-rules.int.test.ts`

**Interfaces :**
- Consumes : le modèle de données (Task 5).
- Produces : les règles de la spec §7.2.

- [ ] **Step 1 : écrire les tests de règles qui doivent échouer**

`functions/src/security/firestore-rules.int.test.ts` :

```ts
// Lancé par `npm run test:int` (émulateur Firestore).
import { after, before, beforeEach, test } from "node:test";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  RulesTestEnvironment, assertFails, assertSucceeds, initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";

let env: RulesTestEnvironment;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-ulmgap-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/eleve"), { active: true, isAdmin: false, profile: "eleve", balance: 0 });
    await setDoc(doc(db, "users/instr"), { active: true, isAdmin: false, profile: "instructeur" });
    await setDoc(doc(db, "users/off"), { active: false, isAdmin: false, profile: "eleve" });
    await setDoc(doc(db, "profiles/eleve"), { displayName: "E", shortName: "ELE" });
    await setDoc(doc(db, "aircraft/a1"), { registration: "F-JABC" });
    await setDoc(doc(db, "flights/f1"), { status: "valide" });
    await setDoc(doc(db, "transactions/t1"), { userUid: "eleve", amount: 100 });
    await setDoc(doc(db, "transactions/t2"), { userUid: "instr", amount: 100 });
  });
});

const as = (uid: string, verified = true) =>
  env.authenticatedContext(uid, { email_verified: verified }).firestore();

test("e-mail non vérifié : aucune lecture", async () => {
  await assertFails(getDoc(doc(as("eleve", false), "flights/f1")));
  await assertFails(getDoc(doc(as("eleve", false), "users/eleve")));
});

test("compte inactif : aucune lecture", async () => {
  await assertFails(getDoc(doc(as("off"), "flights/f1")));
  await assertFails(getDoc(doc(as("off"), "profiles/eleve")));
});

test("anonyme : aucune lecture", async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "flights/f1")));
});

test("connecté : lit flights, aircraft, profiles, settings", async () => {
  const db = as("eleve");
  await assertSucceeds(getDoc(doc(db, "flights/f1")));
  await assertSucceeds(getDoc(doc(db, "aircraft/a1")));
  await assertSucceeds(getDoc(doc(db, "profiles/eleve")));
  await assertSucceeds(getDoc(doc(db, "settings/pricing")));
});

test("users : soi-même oui, les autres non ; instructeur : tous", async () => {
  await assertSucceeds(getDoc(doc(as("eleve"), "users/eleve")));
  await assertFails(getDoc(doc(as("eleve"), "users/instr")));
  await assertSucceeds(getDoc(doc(as("instr"), "users/eleve")));
});

test("users : seul fcmToken est modifiable, et seulement le sien", async () => {
  await assertSucceeds(updateDoc(doc(as("eleve"), "users/eleve"), { fcmToken: "t" }));
  await assertFails(updateDoc(doc(as("eleve"), "users/eleve"), { balance: 999999 }));
  await assertFails(updateDoc(doc(as("eleve"), "users/eleve"), { isAdmin: true }));
  await assertFails(updateDoc(doc(as("instr"), "users/eleve"), { fcmToken: "t" }));
});

test("transactions : les siennes ; instructeur : toutes", async () => {
  await assertSucceeds(getDoc(doc(as("eleve"), "transactions/t1")));
  await assertFails(getDoc(doc(as("eleve"), "transactions/t2")));
  await assertSucceeds(getDoc(doc(as("instr"), "transactions/t2")));
});

test("aucune écriture client sur les collections métier", async () => {
  const db = as("instr");
  await assertFails(setDoc(doc(db, "flights/new"), { status: "valide" }));
  await assertFails(setDoc(doc(db, "aircraft/new"), { registration: "X" }));
  await assertFails(setDoc(doc(db, "profiles/instr"), { shortName: "X" }));
  await assertFails(setDoc(doc(db, "transactions/new"), { amount: 1 }));
  await assertFails(setDoc(doc(db, "settings/pricing"), { hourlyRate: 1 }));
  await assertFails(setDoc(doc(db, "autre/x"), { a: 1 }));
});
```

- [ ] **Step 2 : lancer les tests pour vérifier qu'ils échouent**

Run : `cd functions && npm run test:int`
Expected : FAIL. Les règles actuelles (mode test) autorisent tout, donc les
`assertFails` échouent.

- [ ] **Step 3 : écrire les règles**

`firestore.rules` (remplacement complet) :

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function userDoc() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
    }
    // Connecté = authentifié + e-mail vérifié + compte existant et actif.
    function signedIn() {
      return request.auth != null
        && request.auth.token.email_verified == true
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && userDoc().active == true;
    }
    function isStaff() {
      return signedIn() && (userDoc().isAdmin == true || userDoc().profile == 'instructeur');
    }

    match /users/{uid} {
      allow read: if signedIn() && (request.auth.uid == uid || isStaff());
      allow update: if signedIn() && request.auth.uid == uid
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['fcmToken']);
    }

    match /profiles/{uid} { allow read: if signedIn(); }
    match /aircraft/{id} { allow read: if signedIn(); }
    match /settings/{id} { allow read: if signedIn(); }
    match /flights/{id} { allow read: if signedIn(); }

    match /transactions/{id} {
      allow read: if signedIn() && (resource.data.userUid == request.auth.uid || isStaff());
    }

    // Tout le reste : refusé. Les écritures métier passent par les Functions.
    match /{document=**} { allow read, write: if false; }
  }
}
```

- [ ] **Step 4 : lancer les tests**

Run : `cd functions && npm run test:int`
Expected : PASS (les 10 tests de la Task 5 et les 8 tests de règles).

- [ ] **Step 5 : commit**

```bash
git add firestore.rules functions/src/security
git commit -m "feat: definitive Firestore rules with emulator tests"
```

---

### Task 7 : connexion, vérification d'e-mail et contrôle d'accès (app)

**Files :**
- Create: `lib/data/app_user.dart`, `lib/data/auth_service.dart`, `lib/data/user_repository.dart`, `lib/data/services.dart`
- Create: `lib/features/auth/gate.dart`, `lib/features/auth/login_screen.dart`, `lib/features/auth/verify_email_screen.dart`, `lib/features/auth/no_access_screen.dart`, `lib/features/home/home_shell.dart`
- Modify: `lib/main.dart`
- Test: `test/features/auth/gate_test.dart`, `test/features/auth/login_screen_test.dart`, `test/support/fakes.dart`

**Interfaces :**
- Consumes : `PilotProfile`, `UserCategory` (Task 3) ; `UlmGapApp` (Task 2).
- Produces :
  - `class AppUser { uid, displayName, shortName, email, PilotProfile? profile, UserCategory category, bool isAdmin, bool active, int balance; factory AppUser.fromMap(String uid, Map<String, dynamic> m) }` ;
  - `class AuthSnapshot { uid, email, emailVerified }` ;
  - `abstract class AuthService { Stream<AuthSnapshot?> changes(); Future<void> signIn(String email, String password); Future<void> signOut(); Future<void> sendPasswordReset(String email); Future<void> sendEmailVerification(); Future<void> reload(); }`, qui lève `AuthFailure(message)` ;
  - `String authErrorMessage(String code)` ;
  - `abstract class UserRepository { Stream<AppUser?> watchUser(String uid); }` ;
  - `class AppServices extends InheritedWidget { AuthService auth; UserRepository users; AdminApi? admin; static AppServices of(BuildContext) }` (`AdminApi` vient de la Task 8 : le champ est nullable ici) ;
  - `enum GateState { signedOut, emailUnverified, noAccess, ready }` ;
  - `GateState gateFor(AuthSnapshot? auth, AppUser? user)` ;
  - `class AppGate extends StatelessWidget`.

- [ ] **Step 1 : écrire les tests qui doivent échouer**

`test/support/fakes.dart` :

```dart
import 'dart:async';

import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/auth_service.dart';
import 'package:ulmgap/data/user_repository.dart';

class FakeAuthService implements AuthService {
  final _ctrl = StreamController<AuthSnapshot?>.broadcast();
  AuthSnapshot? current;
  final calls = <String>[];
  String? failWith; // message d'AuthFailure à lever sur signIn

  void emit(AuthSnapshot? s) {
    current = s;
    _ctrl.add(s);
  }

  @override
  Stream<AuthSnapshot?> changes() async* {
    yield current;
    yield* _ctrl.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn:$email');
    if (failWith != null) throw AuthFailure(failWith!);
  }

  @override
  Future<void> signOut() async => calls.add('signOut');
  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset:$email');
  @override
  Future<void> sendEmailVerification() async => calls.add('verify');
  @override
  Future<void> reload() async => calls.add('reload');
}

class FakeUserRepository implements UserRepository {
  final users = <String, AppUser>{};
  @override
  Stream<AppUser?> watchUser(String uid) => Stream.value(users[uid]);
}

AppUser testUser({
  String uid = 'u1',
  bool active = true,
  bool isAdmin = false,
  String? profile = 'eleve',
}) =>
    AppUser.fromMap(uid, {
      'displayName': 'Jean Dupont',
      'shortName': 'JDU',
      'email': 'jean@club.fr',
      'profile': profile,
      'category': 'EXT',
      'isAdmin': isAdmin,
      'active': active,
      'balance': 0,
    });
```

`test/features/auth/gate_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/auth_service.dart';
import 'package:ulmgap/features/auth/gate.dart';

import '../../support/fakes.dart';

void main() {
  const verified = AuthSnapshot(uid: 'u1', email: 'a@b.fr', emailVerified: true);
  const unverified = AuthSnapshot(uid: 'u1', email: 'a@b.fr', emailVerified: false);

  test('non connecté', () => expect(gateFor(null, null), GateState.signedOut));
  test('e-mail non vérifié, même avec un compte actif', () {
    expect(gateFor(unverified, testUser()), GateState.emailUnverified);
  });
  test('pas de document users', () => expect(gateFor(verified, null), GateState.noAccess));
  test('compte désactivé', () {
    expect(gateFor(verified, testUser(active: false)), GateState.noAccess);
  });
  test('compte actif et vérifié', () => expect(gateFor(verified, testUser()), GateState.ready));
  test('authErrorMessage : codes connus et inconnus', () {
    expect(authErrorMessage('wrong-password'), 'E-mail ou mot de passe incorrect.');
    expect(authErrorMessage('invalid-credential'), 'E-mail ou mot de passe incorrect.');
    expect(authErrorMessage('user-disabled'), 'Ce compte est désactivé.');
    expect(authErrorMessage('xyz'), 'Connexion impossible (xyz).');
  });
}
```

`test/features/auth/login_screen_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/auth/login_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeAuthService auth) => AppServices(
      auth: auth,
      users: FakeUserRepository(),
      child: const MaterialApp(home: LoginScreen()),
    );

void main() {
  testWidgets('connexion : appelle signIn avec l\'e-mail nettoyé', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(host(auth));
    await tester.enterText(find.byKey(const Key('email')), ' jean@club.fr ');
    await tester.enterText(find.byKey(const Key('password')), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(auth.calls, ['signIn:jean@club.fr']);
  });

  testWidgets('échec : message affiché', (tester) async {
    final auth = FakeAuthService()..failWith = 'E-mail ou mot de passe incorrect.';
    await tester.pumpWidget(host(auth));
    await tester.enterText(find.byKey(const Key('email')), 'jean@club.fr');
    await tester.enterText(find.byKey(const Key('password')), 'x');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(find.text('E-mail ou mot de passe incorrect.'), findsOneWidget);
  });

  testWidgets('mot de passe oublié sans e-mail : invite à le saisir', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(host(auth));
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pump();
    expect(find.text('Saisissez d\'abord votre e-mail.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('mot de passe oublié : envoie le lien', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(host(auth));
    await tester.enterText(find.byKey(const Key('email')), 'jean@club.fr');
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pump();
    expect(auth.calls, ['reset:jean@club.fr']);
    expect(find.textContaining('Lien envoyé'), findsOneWidget);
  });
}
```

- [ ] **Step 2 : lancer les tests pour vérifier qu'ils échouent**

Run : `fvm flutter test test/features/auth`
Expected : FAIL, car les fichiers n'existent pas.

- [ ] **Step 3 : modèles et services**

`lib/data/app_user.dart` :

```dart
import '../core/profiles.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.shortName,
    required this.email,
    required this.profile,
    required this.category,
    required this.isAdmin,
    required this.active,
    required this.balance,
  });

  final String uid;
  final String displayName;
  final String shortName;
  final String email;
  final PilotProfile? profile;
  final UserCategory category;
  final bool isAdmin;
  final bool active;
  final int balance;

  bool get isInstructor => profile == PilotProfile.instructeur;

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
        uid: uid,
        displayName: (m['displayName'] as String?) ?? '',
        shortName: (m['shortName'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        profile: PilotProfile.fromCode(m['profile'] as String?),
        category: UserCategory.fromCode(m['category'] as String?),
        isAdmin: m['isAdmin'] == true,
        active: m['active'] == true,
        balance: (m['balance'] as num?)?.toInt() ?? 0,
      );
}
```

`lib/data/auth_service.dart` :

```dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthSnapshot {
  const AuthSnapshot({required this.uid, required this.email, required this.emailVerified});
  final String uid;
  final String email;
  final bool emailVerified;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String authErrorMessage(String code) {
  switch (code) {
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-credential':
    case 'invalid-email':
      return 'E-mail ou mot de passe incorrect.';
    case 'user-disabled':
      return 'Ce compte est désactivé.';
    case 'too-many-requests':
      return 'Trop de tentatives. Réessayez plus tard.';
    case 'network-request-failed':
      return 'Pas de connexion réseau.';
    default:
      return 'Connexion impossible ($code).';
  }
}

abstract class AuthService {
  /// Émet à chaque changement de session ET après reload() (e-mail vérifié).
  Stream<AuthSnapshot?> changes();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> sendEmailVerification();
  Future<void> reload();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  @override
  Stream<AuthSnapshot?> changes() => _auth.userChanges().map((u) => u == null
      ? null
      : AuthSnapshot(uid: u.uid, email: u.email ?? '', emailVerified: u.emailVerified));

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> sendEmailVerification() async =>
      _auth.currentUser?.sendEmailVerification();

  @override
  Future<void> reload() async {
    await _auth.currentUser?.reload();
    // Rafraîchit le jeton : email_verified doit y figurer pour les règles.
    await _auth.currentUser?.getIdToken(true);
  }
}
```

`lib/data/user_repository.dart` :

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

abstract class UserRepository {
  Stream<AppUser?> watchUser(String uid);
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  @override
  Stream<AppUser?> watchUser(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromMap(s.id, s.data()!) : null)
      // Lecture refusée (inactif / non vérifié) → pas d'accès.
      .handleError((Object _) {}, test: (e) => e is FirebaseException);
}
```

`lib/data/services.dart` :

```dart
import 'package:flutter/widgets.dart';

import 'admin_api.dart';
import 'auth_service.dart';
import 'user_repository.dart';

/// Services de l'app, injectés à la racine (doublures en test).
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.auth,
    required this.users,
    this.admin,
    required super.child,
  });

  final AuthService auth;
  final UserRepository users;
  final AdminApi? admin;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppServices>()!;

  @override
  bool updateShouldNotify(AppServices old) =>
      auth != old.auth || users != old.users || admin != old.admin;
}
```

Comme `services.dart` importe `admin_api.dart`, créer dès maintenant son
interface. La Task 8 la complétera :

`lib/data/admin_api.dart` (première version) :

```dart
/// Fonctions d'administration (callables). Complété à la Task 8.
abstract class AdminApi {}
```

- [ ] **Step 4 : écrans et gate**

`lib/features/auth/gate.dart` :

```dart
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
```

`lib/features/auth/login_screen.dart` :

```dart
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
```

`lib/features/auth/verify_email_screen.dart` :

```dart
import 'package:flutter/material.dart';

import '../../data/services.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key, required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_unread, size: 48),
              const SizedBox(height: 12),
              Text('Vérifiez votre adresse e-mail ($email) pour accéder à UlmGap.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: auth.reload,
                child: const Text('J\'ai vérifié mon e-mail'),
              ),
              TextButton(
                onPressed: () async {
                  await auth.sendEmailVerification();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('E-mail de vérification envoyé.')));
                  }
                },
                child: const Text('Renvoyer le lien'),
              ),
              TextButton(onPressed: auth.signOut, child: const Text('Se déconnecter')),
            ],
          ),
        ),
      ),
    );
  }
}
```

`lib/features/auth/no_access_screen.dart` :

```dart
import 'package:flutter/material.dart';

import '../../data/services.dart';

class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 48),
              const SizedBox(height: 12),
              const Text('Ce compte n\'a pas accès à UlmGap. Contactez un administrateur.',
                  textAlign: TextAlign.center),
              TextButton(
                onPressed: AppServices.of(context).auth.signOut,
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`lib/features/home/home_shell.dart` (le menu admin ouvrira les écrans de la
Task 8, ajoutés à ce moment-là) :

```dart
import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UlmGap'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Text(user.shortName),
              const SizedBox(width: 6),
              ProfileBadge(profile: user.profile, compact: true),
            ]),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: AppServices.of(context).auth.signOut,
          ),
        ],
      ),
      body: const Center(child: Text('Planning : disponible au plan 2.')),
    );
  }
}
```

`lib/main.dart` :

```dart
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
```

- [ ] **Step 5 : lancer les tests**

Run : `fvm flutter test && fvm flutter analyze`
Expected : PASS (tous les tests, dont les 6 de `gate_test` et les 4 de
`login_screen_test`), aucune erreur d'analyse.

- [ ] **Step 6 : commit**

```bash
git add lib test
git commit -m "feat: sign-in, email verification and access gate"
```

---

### Task 8 : administration des comptes et des appareils (app)

**Files :**
- Create: `lib/data/aircraft.dart`, `lib/features/admin/validators.dart`, `lib/features/admin/user_form_dialog.dart`, `lib/features/admin/users_admin_screen.dart`, `lib/features/admin/aircraft_form_dialog.dart`, `lib/features/admin/aircraft_admin_screen.dart`
- Modify: `lib/data/admin_api.dart` (version complète), `lib/features/home/home_shell.dart`, `lib/main.dart`, `test/support/fakes.dart`
- Test: `test/features/admin/validators_test.dart`, `test/features/admin/users_admin_screen_test.dart`, `test/features/admin/aircraft_admin_screen_test.dart`

**Interfaces :**
- Consumes : `AppUser`, `AppServices`, `ProfileBadge`, `PilotProfile`,
  `UserCategory` ; les callables `adminCreateUser`, `adminUpdateUser`,
  `adminUpsertAircraft` (Task 5).
- Produces :
  - `class Aircraft { id, registration, label, active; factory Aircraft.fromMap(String id, Map<String, dynamic> m) }` ;
  - `String? validateEmail(String)`, `String? validateShortName(String)`,
    `String? validateRequired(String, String field)` ;
  - `abstract class AdminApi { Stream<List<AppUser>> watchAllUsers(); Future<String> createUser(Map<String, dynamic> input); Future<void> updateUser(String uid, Map<String, dynamic> patch); Stream<List<Aircraft>> watchAircraft(); Future<String> upsertAircraft(Map<String, dynamic> input); }` ;
  - `class FirebaseAdminApi implements AdminApi`, qui appelle
    `sendPasswordResetEmail` après la création d'un compte.

- [ ] **Step 1 : écrire les tests qui doivent échouer**

Ajouter à `test/support/fakes.dart` :

```dart
// --- ajouts Task 8 ---
class FakeAdminApi implements AdminApi {
  final usersCtrl = StreamController<List<AppUser>>.broadcast();
  final aircraftCtrl = StreamController<List<Aircraft>>.broadcast();
  List<AppUser> users = [];
  List<Aircraft> aircraft = [];
  final created = <Map<String, dynamic>>[];
  final updated = <String, Map<String, dynamic>>{};
  final upserted = <Map<String, dynamic>>[];

  @override
  Stream<List<AppUser>> watchAllUsers() async* {
    yield users;
    yield* usersCtrl.stream;
  }

  @override
  Future<String> createUser(Map<String, dynamic> input) async {
    created.add(input);
    return 'new-uid';
  }

  @override
  Future<void> updateUser(String uid, Map<String, dynamic> patch) async => updated[uid] = patch;

  @override
  Stream<List<Aircraft>> watchAircraft() async* {
    yield aircraft;
    yield* aircraftCtrl.stream;
  }

  @override
  Future<String> upsertAircraft(Map<String, dynamic> input) async {
    upserted.add(input);
    return 'a-new';
  }
}
```

Ajouter aussi en tête du même fichier :

```dart
import 'package:ulmgap/data/admin_api.dart';
import 'package:ulmgap/data/aircraft.dart';
```

`test/features/admin/validators_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/admin/validators.dart';

void main() {
  test('validateEmail', () {
    expect(validateEmail('jean@club.fr'), isNull);
    expect(validateEmail(' jean@club.fr '), isNull);
    expect(validateEmail('jean'), 'E-mail invalide.');
  });
  test('validateShortName : 2 à 4 lettres ou chiffres', () {
    expect(validateShortName('jdu'), isNull);
    expect(validateShortName('J'), isNotNull);
    expect(validateShortName('JDUPO'), isNotNull);
    expect(validateShortName('J-D'), isNotNull);
  });
  test('validateRequired', () {
    expect(validateRequired(' ', 'Nom'), 'Nom obligatoire.');
    expect(validateRequired('x', 'Nom'), isNull);
  });
}
```

`test/features/admin/users_admin_screen_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/profile_badge.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/admin/users_admin_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeAdminApi api) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      admin: api,
      child: const MaterialApp(home: UsersAdminScreen()),
    );

void main() {
  testWidgets('liste : nom, code, badge, catégorie, inactif signalé', (tester) async {
    final api = FakeAdminApi()
      ..users = [testUser(uid: 'u1'), testUser(uid: 'u2', active: false, profile: 'instructeur')];
    await tester.pumpWidget(host(api));
    await tester.pump();
    expect(find.text('Jean Dupont'), findsNWidgets(2));
    expect(find.byType(ProfileBadge), findsNWidgets(2));
    expect(find.text('EXT'), findsNWidgets(2));
    expect(find.text('Désactivé'), findsOneWidget);
  });

  testWidgets('création : envoie les champs normalisés', (tester) async {
    final api = FakeAdminApi();
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Nouveau compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('f-email')), ' Pilote@Club.fr ');
    await tester.enterText(find.byKey(const Key('f-name')), 'Paul Martin');
    await tester.enterText(find.byKey(const Key('f-short')), 'pma');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.created.single, {
      'email': 'pilote@club.fr',
      'displayName': 'Paul Martin',
      'shortName': 'PMA',
      'profile': 'eleve',
      'category': 'EXT',
      'isAdmin': false,
      'active': true,
    });
  });

  testWidgets('création : e-mail invalide bloque l\'envoi', (tester) async {
    final api = FakeAdminApi();
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Nouveau compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('f-email')), 'nope');
    await tester.enterText(find.byKey(const Key('f-name')), 'Paul');
    await tester.enterText(find.byKey(const Key('f-short')), 'PMA');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.created, isEmpty);
    expect(find.text('E-mail invalide.'), findsOneWidget);
  });

  testWidgets('modification : n\'envoie pas l\'e-mail', (tester) async {
    final api = FakeAdminApi()..users = [testUser(uid: 'u1')];
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.updated['u1']!.containsKey('email'), isFalse);
    expect(api.updated['u1']!['shortName'], 'JDU');
  });
}
```

`test/features/admin/aircraft_admin_screen_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/admin/aircraft_admin_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeAdminApi api) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      admin: api,
      child: const MaterialApp(home: AircraftAdminScreen()),
    );

void main() {
  testWidgets('liste et création', (tester) async {
    final api = FakeAdminApi()
      ..aircraft = [
        Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true}),
      ];
    await tester.pumpWidget(host(api));
    await tester.pump();
    expect(find.text('ULM 1'), findsOneWidget);
    expect(find.text('F-JABC'), findsOneWidget);

    await tester.tap(find.byTooltip('Nouvel appareil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('a-reg')), ' f-jxyz ');
    await tester.enterText(find.byKey(const Key('a-label')), 'ULM 2');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.upserted.single, {'registration': 'F-JXYZ', 'label': 'ULM 2', 'active': true});
  });

  testWidgets('modification : transmet l\'id', (tester) async {
    final api = FakeAdminApi()
      ..aircraft = [
        Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true}),
      ];
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.text('ULM 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.upserted.single['id'], 'a1');
  });
}
```

- [ ] **Step 2 : lancer les tests pour vérifier qu'ils échouent**

Run : `fvm flutter test test/features/admin`
Expected : FAIL, car les fichiers n'existent pas.

- [ ] **Step 3 : modèle, validateurs, API**

`lib/data/aircraft.dart` :

```dart
class Aircraft {
  const Aircraft({
    required this.id,
    required this.registration,
    required this.label,
    required this.active,
  });

  final String id;
  final String registration;
  final String label;
  final bool active;

  factory Aircraft.fromMap(String id, Map<String, dynamic> m) => Aircraft(
        id: id,
        registration: (m['registration'] as String?) ?? '',
        label: (m['label'] as String?) ?? '',
        active: m['active'] == true,
      );
}
```

`lib/features/admin/validators.dart` :

```dart
// Mêmes règles que functions/src/admin/validation.ts (le serveur reste l'autorité).
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _shortRe = RegExp(r'^[A-Z0-9]{2,4}$');

String? validateEmail(String v) =>
    _emailRe.hasMatch(v.trim()) ? null : 'E-mail invalide.';

String? validateShortName(String v) => _shortRe.hasMatch(v.trim().toUpperCase())
    ? null
    : '2 à 4 lettres ou chiffres.';

String? validateRequired(String v, String field) =>
    v.trim().isEmpty ? '$field obligatoire.' : null;
```

`lib/data/admin_api.dart` (version complète, remplace la précédente) :

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'aircraft.dart';
import 'app_user.dart';

abstract class AdminApi {
  Stream<List<AppUser>> watchAllUsers();
  Future<String> createUser(Map<String, dynamic> input);
  Future<void> updateUser(String uid, Map<String, dynamic> patch);
  Stream<List<Aircraft>> watchAircraft();
  Future<String> upsertAircraft(Map<String, dynamic> input);
}

class FirebaseAdminApi implements AdminApi {
  FirebaseAdminApi({FirebaseFirestore? db, FirebaseFunctions? fn, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;
  final FirebaseAuth _auth;

  @override
  Stream<List<AppUser>> watchAllUsers() => _db
      .collection('users')
      .orderBy('displayName')
      .snapshots()
      .map((q) => q.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  @override
  Future<String> createUser(Map<String, dynamic> input) async {
    final res = await _fn.httpsCallable('adminCreateUser').call(input);
    // Le nouvel utilisateur reçoit le lien pour définir son mot de passe.
    await _auth.sendPasswordResetEmail(email: input['email'] as String);
    return (res.data as Map)['uid'] as String;
  }

  @override
  Future<void> updateUser(String uid, Map<String, dynamic> patch) =>
      _fn.httpsCallable('adminUpdateUser').call({'uid': uid, ...patch});

  @override
  Stream<List<Aircraft>> watchAircraft() => _db
      .collection('aircraft')
      .orderBy('label')
      .snapshots()
      .map((q) => q.docs.map((d) => Aircraft.fromMap(d.id, d.data())).toList());

  @override
  Future<String> upsertAircraft(Map<String, dynamic> input) async {
    final res = await _fn.httpsCallable('adminUpsertAircraft').call(input);
    return (res.data as Map)['id'] as String;
  }
}
```

- [ ] **Step 4 : formulaires et écrans**

`lib/features/admin/user_form_dialog.dart` :

```dart
import 'package:flutter/material.dart';

import '../../core/profiles.dart';
import '../../data/app_user.dart';
import 'validators.dart';

/// Renvoie le payload à envoyer (création : avec email ; modification : sans).
Future<Map<String, dynamic>?> showUserFormDialog(BuildContext context, {AppUser? user}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserFormDialog(user: user),
    );

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user});
  final AppUser? user;
  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.user?.email ?? '');
  late final _name = TextEditingController(text: widget.user?.displayName ?? '');
  late final _short = TextEditingController(text: widget.user?.shortName ?? '');
  late PilotProfile? _profile = widget.user == null ? PilotProfile.eleve : widget.user!.profile;
  late UserCategory _category = widget.user?.category ?? UserCategory.ext;
  late bool _isAdmin = widget.user?.isAdmin ?? false;
  late bool _active = widget.user?.active ?? true;

  bool get _isNew => widget.user == null;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(<String, dynamic>{
      if (_isNew) 'email': _email.text.trim().toLowerCase(),
      'displayName': _name.text.trim(),
      'shortName': _short.text.trim().toUpperCase(),
      'profile': _profile?.code,
      'category': _category.code,
      'isAdmin': _isAdmin,
      'active': _active,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Nouveau compte' : 'Modifier le compte'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('f-email'),
                controller: _email,
                enabled: _isNew,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (v) => validateEmail(v ?? ''),
              ),
              TextFormField(
                key: const Key('f-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: (v) => validateRequired(v ?? '', 'Nom'),
              ),
              TextFormField(
                key: const Key('f-short'),
                controller: _short,
                decoration: const InputDecoration(labelText: 'Code court (trigramme)'),
                validator: (v) => validateShortName(v ?? ''),
              ),
              DropdownButtonFormField<PilotProfile?>(
                value: _profile,
                decoration: const InputDecoration(labelText: 'Profil'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Non pilote')),
                  for (final p in PilotProfile.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (v) => setState(() => _profile = v),
              ),
              DropdownButtonFormField<UserCategory>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Appartenance'),
                items: [
                  for (final c in UserCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.code)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              SwitchListTile(
                title: const Text('Administrateur'),
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v),
              ),
              SwitchListTile(
                title: const Text('Compte actif'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
```

`lib/features/admin/users_admin_screen.dart` :

```dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import 'user_form_dialog.dart';

class UsersAdminScreen extends StatelessWidget {
  const UsersAdminScreen({super.key});

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppServices.of(context).admin!;
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouveau compte',
        child: const Icon(Icons.person_add),
        onPressed: () async {
          final input = await showUserFormDialog(context);
          if (input != null && context.mounted) {
            await _guard(context, () => api.createUser(input));
          }
        },
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: api.watchAllUsers(),
        builder: (context, snap) {
          final users = snap.data ?? const <AppUser>[];
          return ListView(
            children: [
              for (final u in users)
                ListTile(
                  // Pas de `enabled: false` : un compte désactivé doit rester
                  // cliquable pour pouvoir être réactivé.
                  textColor: u.active ? null : Theme.of(context).disabledColor,
                  leading: ProfileBadge(profile: u.profile, compact: true),
                  title: Text(u.displayName),
                  subtitle: Text('${u.shortName} · ${u.email}'),
                  trailing: Wrap(spacing: 6, children: [
                    Chip(label: Text(u.category.code)),
                    if (u.isAdmin) const Icon(Icons.admin_panel_settings),
                    if (!u.active) const Chip(label: Text('Désactivé')),
                  ]),
                  onTap: () async {
                    final patch = await showUserFormDialog(context, user: u);
                    if (patch != null && context.mounted) {
                      await _guard(context, () => api.updateUser(u.uid, patch));
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
```

`lib/features/admin/aircraft_form_dialog.dart` :

```dart
import 'package:flutter/material.dart';

import '../../data/aircraft.dart';
import 'validators.dart';

Future<Map<String, dynamic>?> showAircraftFormDialog(BuildContext context, {Aircraft? aircraft}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AircraftFormDialog(aircraft: aircraft),
    );

class _AircraftFormDialog extends StatefulWidget {
  const _AircraftFormDialog({this.aircraft});
  final Aircraft? aircraft;
  @override
  State<_AircraftFormDialog> createState() => _AircraftFormDialogState();
}

class _AircraftFormDialogState extends State<_AircraftFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _reg = TextEditingController(text: widget.aircraft?.registration ?? '');
  late final _label = TextEditingController(text: widget.aircraft?.label ?? '');
  late bool _active = widget.aircraft?.active ?? true;

  @override
  void dispose() {
    _reg.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.aircraft == null ? 'Nouvel appareil' : 'Modifier l\'appareil'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('a-reg'),
              controller: _reg,
              decoration: const InputDecoration(labelText: 'Immatriculation'),
              validator: (v) => validateRequired(v ?? '', 'Immatriculation'),
            ),
            TextFormField(
              key: const Key('a-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Libellé'),
              validator: (v) => validateRequired(v ?? '', 'Libellé'),
            ),
            SwitchListTile(
              title: const Text('Actif'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop(<String, dynamic>{
              if (widget.aircraft != null) 'id': widget.aircraft!.id,
              'registration': _reg.text.trim().toUpperCase(),
              'label': _label.text.trim(),
              'active': _active,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
```

`lib/features/admin/aircraft_admin_screen.dart` :

```dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../data/aircraft.dart';
import '../../data/services.dart';
import 'aircraft_form_dialog.dart';

class AircraftAdminScreen extends StatelessWidget {
  const AircraftAdminScreen({super.key});

  Future<void> _save(BuildContext context, Map<String, dynamic>? input) async {
    if (input == null) return;
    try {
      await AppServices.of(context).admin!.upsertAircraft(input);
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppServices.of(context).admin!;
    return Scaffold(
      appBar: AppBar(title: const Text('Appareils')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouvel appareil',
        child: const Icon(Icons.add),
        onPressed: () async {
          final input = await showAircraftFormDialog(context);
          if (context.mounted) await _save(context, input);
        },
      ),
      body: StreamBuilder<List<Aircraft>>(
        stream: api.watchAircraft(),
        builder: (context, snap) => ListView(
          children: [
            for (final a in snap.data ?? const <Aircraft>[])
              ListTile(
                // Reste cliquable même inactif (pour le réactiver).
                textColor: a.active ? null : Theme.of(context).disabledColor,
                leading: const Icon(Icons.airplanemode_active),
                title: Text(a.label),
                subtitle: Text(a.registration),
                trailing: a.active ? null : const Chip(label: Text('Inactif')),
                onTap: () async {
                  final input = await showAircraftFormDialog(context, aircraft: a);
                  if (context.mounted) await _save(context, input);
                },
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5 : brancher dans l'app**

Dans `lib/features/home/home_shell.dart` :
- ajouter les imports `import '../admin/aircraft_admin_screen.dart';` et
  `import '../admin/users_admin_screen.dart';` ;
- ajouter, **avant** l'`IconButton` de déconnexion, dans `actions` :

```dart
          if (user.isAdmin)
            PopupMenuButton<String>(
              tooltip: 'Administration',
              icon: const Icon(Icons.admin_panel_settings),
              onSelected: (v) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    v == 'users' ? const UsersAdminScreen() : const AircraftAdminScreen(),
              )),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'users', child: Text('Comptes')),
                PopupMenuItem(value: 'aircraft', child: Text('Appareils')),
              ],
            ),
```

Dans `lib/main.dart`, ajouter `import 'data/admin_api.dart';` et passer
`admin: FirebaseAdminApi(),` au constructeur `AppServices`.

- [ ] **Step 6 : lancer les tests**

Run : `fvm flutter test && fvm flutter analyze`
Expected : PASS (tous les tests), aucune erreur d'analyse.

- [ ] **Step 7 : commit**

```bash
git add lib test
git commit -m "feat: admin screens for accounts and aircraft"
```

---

### Task 9 : premier admin, déploiement dev et recette

**Files :**
- Create: `functions/scripts/bootstrap-admin.js`
- Modify: `README.md` (section « Premier admin »)

**Interfaces :**
- Consumes : le modèle `users` et `profiles` (Task 5).

- [ ] **Step 1 : script de premier admin**

`functions/scripts/bootstrap-admin.js` :

```js
// Crée (ou promeut) le premier admin d'un projet. Usage :
//   node scripts/bootstrap-admin.js --project ulmgap-dev --email moi@x.fr --name "Nom" --short ABC
// Identifiants : gcloud auth application-default login (compte propriétaire du projet).
const admin = require("firebase-admin");

const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project");
const email = (arg("email") || "").trim().toLowerCase();
const name = arg("name") || email;
const short = (arg("short") || "").toUpperCase();
if (!projectId || !email || !/^[A-Z0-9]{2,4}$/.test(short)) {
  console.error("Usage : --project <id> --email <e-mail> --name <nom> --short <2-4 car.>");
  process.exit(1);
}

admin.initializeApp({ projectId });
(async () => {
  let rec;
  try {
    rec = await admin.auth().getUserByEmail(email);
  } catch {
    rec = await admin.auth().createUser({ email, displayName: name });
  }
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("users").doc(rec.uid).set({
    email, displayName: name, shortName: short, profile: null, category: "GAP",
    isAdmin: true, active: true, balance: 0, fcmToken: null, createdAt: now, updatedAt: now,
  }, { merge: true });
  await db.collection("profiles").doc(rec.uid).set(
    { displayName: name, shortName: short, profile: null, active: true }, { merge: true });
  const link = await admin.auth().generatePasswordResetLink(email);
  console.log(`Admin prêt : ${email} (uid ${rec.uid}).`);
  console.log(`Lien pour définir le mot de passe : ${link}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
```

Ajouter au `README.md` :

````markdown
## Premier admin (une fois par projet)

```bash
cd functions && npm run build
node scripts/bootstrap-admin.js --project ulmgap-dev --email moi@x.fr --name "Mon Nom" --short ABC
```

Ouvrir le lien affiché pour définir le mot de passe, puis se connecter à
l'app et vérifier l'e-mail.
````

- [ ] **Step 2 : déployer en dev**

Run : `firebase deploy --project dev --only firestore:rules,functions`
Expected : règles et trois fonctions (`adminCreateUser`, `adminUpdateUser`,
`adminUpsertAircraft`) déployées sur `ulmgap-dev`. Les Functions exigent le
forfait Blaze sur le projet. Si le déploiement est refusé à l'agent, le faire
lancer par l'utilisateur.

- [ ] **Step 3 : créer le premier admin en dev**

Run : la commande du README avec l'e-mail de l'utilisateur. Si l'agent n'a
pas accès aux identifiants, la faire lancer par l'utilisateur.

- [ ] **Step 4 : recette en dev**

Lancer `fvm flutter run -d chrome` (dev par défaut), puis vérifier :
1. Le bandeau DEV est visible. La connexion avec l'admin fonctionne, et
   l'écran « Vérifiez votre adresse e-mail » s'affiche avant la
   vérification, puis disparaît après « J'ai vérifié mon e-mail ».
2. Administration → Comptes : créer un élève (catégorie EXT). Il reçoit
   l'e-mail de définition du mot de passe, et son badge « Élève » s'affiche.
3. Désactiver ce compte : sa session est coupée (écran « pas d'accès »).
4. Essayer de retirer ses propres droits d'admin : le message de refus
   s'affiche.
5. Administration → Appareils : créer « ULM 1 » et « ULM 2 ». Créer une
   seconde fois la même immatriculation est refusé.

- [ ] **Step 5 : commit**

```bash
git add functions/scripts/bootstrap-admin.js README.md
git commit -m "chore: first-admin bootstrap script and dev rollout notes"
```

- [ ] **Step 6 : actions de l'utilisateur en prod (hors exécution du plan)**

À reporter tel quel dans le résumé final ; **l'agent ne l'exécute pas** :
1. Avant le 25/10/2026 : `firebase deploy --project prod --only firestore:rules,functions`.
2. Créer le premier admin de prod avec `--project ulmgap-prod`.
