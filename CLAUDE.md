# UlmGap : consignes pour Claude Code

Application Flutter (Android, iOS, web) de gestion des vols ULM, séparée
d'AppGAP pour des raisons de sécurité : des pilotes externes au GAP ne
doivent jamais accéder à AppGAP.

## Documents de référence

- Spec (autorité) : `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`
- Plan 1, le socle (terminé) : `docs/superpowers/plans/2026-09-25-ulmgap-01-socle.md`
- Plan 2, vols et matrice de droits (terminé) : `docs/superpowers/plans/2026-09-28-ulmgap-02-vols.md`
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

- Plans 1 et 2 terminés. `feature/socle` est fusionnée dans `main` ; le plan 2
  est sur la branche `feature/vols` (non fusionnée).
- Points mineurs M1 à M9 du plan 1 soldés au plan 2.
- En dev : Authentication activé, premier admin créé (DPS), règles et
  Functions du plan 2 déployées (`createFlight`, `updateFlight`,
  `validateFlight`, `refuseFlight`, `cancelFlight` et les fonctions admin).
- En prod : **règles et Functions à déployer par l'utilisateur avant le
  25/10/2026**, date d'expiration des règles du mode test. Premier admin à
  créer ensuite (`cd functions && npm run build && node
  scripts/bootstrap-admin.js --project ulmgap-prod …`), et Authentication à
  activer (e-mail et mot de passe, création de compte par l'utilisateur
  désactivée).
- Android : toujours passer `--flavor` et `--dart-define=ENV` ensemble ; une
  discordance bloque l'app au démarrage.

### À reprendre au plan 3

- `pricingSnapshot` vaut `null` sur les vols validés pendant le plan 2 :
  prévoir un repli sur les tarifs courants.
- `MIN_PLANNED_MINUTES` (serveur) et `minPlannedMinutes` (Dart) sont codés en
  dur à 45 : les lire dans `settings/pricing`. La durée prévue maximale
  (12 h) et l'horizon de réservation (366 jours) sont aussi en dur.
- Aperçu du formulaire : ajouter le coût estimé et le crédit disponible du
  payeur ; contrôle du crédit à la validation (§4.4).
- `adminUpdateFlight` : correction d'un vol passé ou déjà commencé (un admin
  peut déjà créer après coup un vol passé via `createFlight`).
- Une demande expirée reste `demande` en base (statut calculé côté app) : le
  pont AppGAP ne copie que les vols `valide`, donc aucun impact.
- Questions ouvertes pour l'utilisateur : consentement du payeur (le créateur
  choisit `crew[0]`, qui paiera) ; faut-il garder « carburant seulement »
  quand un non-instructeur modifie un vol entre GAP (aujourd'hui il repasse
  en standard et le vol redevient une demande s'il y a un instructeur).

### Rappel côté AppGAP (plan 6)

Le pont `syncUlmFlights` d'AppGAP ne doit copier que les vols
`status == 'valide'`, et `externalCount` doit inclure `passengers.length`.
Spec §8.
