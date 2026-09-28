# UlmGap : consignes pour Claude Code

Application Flutter (Android, iOS, web) de gestion des vols ULM, séparée
d'AppGAP pour des raisons de sécurité : des pilotes externes au GAP ne
doivent jamais accéder à AppGAP.

## Documents de référence

- Spec (autorité) : `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`
- Plan 1, le socle (terminé) : `docs/superpowers/plans/2026-09-25-ulmgap-01-socle.md`
- Découpage prévu des plans suivants :
  2. vols et matrice de droits ;
  3. finances (forfaits, crédit FCFA, relevé) ;
  4. compteurs pilote et appareil ;
  5. notifications et rappels de clôture ;
  6. adaptation du pont AppGAP (dans le repo `~/StudioProjects/app_gap`).

## Règles de travail

- **Toujours `fvm flutter` / `fvm dart`** (Flutter 3.32.8), jamais `flutter` nu.
- **Dev par défaut.** L'environnement se choisit avec `--dart-define=ENV=dev|prod`
  et, sur Android, avec `--flavor dev|prod`.
- **Ne jamais déployer en prod** (`--project prod`) : c'est toujours
  l'utilisateur qui le fait.
- **Toute écriture métier passe par des Cloud Functions callables**
  (`europe-west1`). Les règles Firestore interdisent les écritures client,
  sauf `users/{uid}.fcmToken`.
- **TDD** : chaque changement commence par un test qui échoue.
- **KISS** : proposer d'abord l'option la plus simple ; les durcissements ne
  viennent qu'en option.
- **Mise en page** : quand l'utilisateur fournit une maquette précise, la
  reproduire telle quelle, sans proposer d'alternative.
- Textes de l'interface **en français**.

## Tests

```bash
fvm flutter test && fvm flutter analyze
cd functions && npm test                        # unitaires
cd functions && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int
```

Les émulateurs de `firebase-tools` 15 exigent Java 21 ; le système a Java 17,
d'où le JDK d'Android Studio.

**Disque presque plein** (environ 6 Go libres) : éviter les builds inutiles.
`build/` peut être supprimé, il est régénérable.

## État au 2026-09-28

- Plan 1 terminé sur la branche `feature/socle`.
- En dev : Authentication activé, règles et Functions déployées, premier admin
  créé (DPS).
- En prod : **règles et Functions à déployer par l'utilisateur avant le
  25/10/2026**, date d'expiration des règles du mode test. Premier admin à
  créer ensuite (`functions/scripts/bootstrap-admin.js`), et Authentication à
  activer (e-mail et mot de passe, création de compte par l'utilisateur
  désactivée).
- Fichier non suivi `android/android/app/build.gradle.kts` apparu hors plan :
  à clarifier avec l'utilisateur avant d'y toucher.

### Points mineurs reportés, à traiter au début du plan 2

- M1 : un bref écran « pas d'accès » peut apparaître juste après « J'ai vérifié
  mon e-mail » (course sur le jeton).
- M3 : `updateUser` n'est pas atomique entre Firestore et Auth (une
  réactivation peut laisser Auth désactivé).
- M4 : `updateUser` peut créer un document `profiles` partiel pour un ancien
  compte qui n'en avait pas.
- M5 : règles Firestore, type et taille de `fcmToken` non vérifiés.
- M6 : listes admin vides sans message en cas d'erreur ou de chargement.
- M7 : l'unicité de l'immatriculation n'est pas garantie en cas de créations
  simultanées.
- M8 : `bootstrap-admin.js` traite toute erreur de `getUserByEmail` comme
  « compte inexistant » (cela a masqué « Authentication non activé ») et
  écrase `createdAt` à chaque relance.
- M9 : `--flavor` et `ENV` sont indépendants, donc une app au package prod
  pourrait parler à dev.

### Rappel côté AppGAP (plan 6)

Le pont `syncUlmFlights` d'AppGAP ne doit copier que les vols
`status == 'valide'`, et `externalCount` doit inclure `passengers.length`.
Spec §8.
