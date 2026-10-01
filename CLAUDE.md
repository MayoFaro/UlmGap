# UlmGap : consignes pour Claude Code

Application Flutter (Android, iOS, web) de gestion des vols ULM, séparée
d'AppGAP pour des raisons de sécurité : des pilotes externes au GAP ne
doivent jamais accéder à AppGAP.

## Documents de référence

- Spec (autorité) : `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`
- Plan 1, le socle (terminé) : `docs/superpowers/plans/2026-09-25-ulmgap-01-socle.md`
- Plan 2, vols et matrice de droits (terminé) : `docs/superpowers/plans/2026-09-28-ulmgap-02-vols.md`
- Plan 2b, retours de recette du plan 2 (terminé) : `docs/superpowers/plans/2026-09-28-ulmgap-02b-retours-recette.md`
- Plan 3, finances (terminé) : `docs/superpowers/plans/2026-09-29-ulmgap-03-finances.md`
- Plan 4b, atterrissages, amerrissages, heure de fin à la clôture (terminé) :
  `docs/superpowers/plans/2026-10-01-ulmgap-04b-atterrissages.md`
- Plan 5, Node 22, notifications push et rappels de clôture (terminé) :
  `docs/superpowers/plans/2026-10-01-ulmgap-05-notifications.md`
- Plan 4, carnet de vol (terminé) : `docs/superpowers/plans/2026-09-30-ulmgap-04-compteurs.md`
  (les écrans « Vols effectués » et « Compteurs » du plan y sont remplacés
  par un seul « Carnet de vol », voir la révision en fin de plan et spec §5)
- Découpage prévu des plans suivants :
  2. vols et matrice de droits ;
  3. finances (forfaits, crédit FCFA, relevé) ;
  4. carnet de vol (vols effectués, temps de vol total, clôture) ;
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

## État au 2026-10-01

- Plans 1 à 5 terminés. `main` contient les plans 1, 2 et 2b ; les plans 3,
  4 et 4b sont sur `feature/finances` (poussée, non fusionnée dans `main`) ;
  le plan 5 sur `feature/notifications` (créée depuis `feature/finances`).
- En dev : Authentication activé, premier admin (DPS), règles et Functions du
  plan 3 déployées (vols, finances : `closeFlight`, `creditAccount`,
  `correctAccount`, `adminUpdateFlight`, `adminDeleteFlight`,
  `adminUpdatePricing`). Crédit initial de 500 000 FCFA versé aux 4 comptes
  de dev (transaction « Crédit initial (tests) »). Plan 4 : `closeFlight`
  redéployée (clôture dès le jour du vol, à l'heure d'Africa/Libreville).
  Plan 4b : `closeFlight`, `adminUpdateFlight` et `adminUpsertAircraft`
  redéployées (atterrissages, amerrissages, appareil amphibie, fin allongée).
  Pour tester les amerrissages, cocher « Amphibie » sur un appareil.
  Toutes les Functions redéployées ensuite (conflits contrôlés en
  planification seulement, spec §3.5).
- En prod : **règles et Functions à déployer par l'utilisateur avant le
  25/10/2026**, date d'expiration des règles du mode test. Déployer
  **toutes les Functions dans leur version du plan 5** (Node 22, dont la
  tâche planifiée `closingReminders` : le déploiement active Cloud
  Scheduler), en même temps que l'app web (`closeFlight` exige le nombre
  d'atterrissages, `correctAccount` le nouveau solde). Ni règle ni index
  nouveau depuis le plan 3. Ensuite :
  - premier admin (`cd functions && npm run build && node
    scripts/bootstrap-admin.js --project ulmgap-prod …`) et Authentication
    (e-mail et mot de passe, création de compte par l'utilisateur
    désactivée) ;
  - marquer l'ULM amphibie dans Administration → Appareils ;
  - clé VAPID web du projet prod (voir plus bas), à reporter dans
    `lib/core/env.dart` avant le build web de prod.
- Functions en **Node 22** (`firebase-functions` 7, `firebase-admin` 13 :
  la 14 supprime l'API `admin.firestore()` utilisée partout). Le Node local
  reste en 20 : accepté par les tests et l'émulateur.
- Plan 5 en dev : toutes les Functions redéployées, dont `closingReminders`
  (tâche planifiée horaire). **Notifications web : clé VAPID à créer** dans
  la console (Paramètres du projet → Cloud Messaging → Certificats Web Push →
  Générer), en dev puis en prod, à reporter dans `lib/core/env.dart`
  (`_webVapidKeyDev` / `_webVapidKeyProd`). Sans clé : pas de notifications
  web, sans erreur. Android n'en a pas besoin. iOS : plus tard (clés APNs).
- Comptes de test en dev (e-mails `test-…@ulmgap.invalid`, déjà vérifiés) :
  `cd functions && npm run build && node scripts/seed-test-users.js --project ulmgap-dev --password <8 car. min.>`.
  Crédit initial (une fois par compte) :
  `node scripts/seed-dev-credit.js --project ulmgap-dev [--amount 500000]`.
  Les deux scripts refusent tout autre projet.
- Android : toujours passer `--flavor` et `--dart-define=ENV` ensemble ; une
  discordance bloque l'app au démarrage.
- Tests d'intégration : exécutés fichier par fichier (`--test-concurrency=1`),
  car ils modifient le document global `settings/pricing`.

### À reprendre aux plans suivants

- La durée prévue maximale (12 h) et l'horizon de réservation (366 jours)
  restent codés en dur ; `minPlannedMinutes` est dans `settings/pricing`.
- Une demande expirée reste `demande` en base (statut calculé côté app).
- Pour les vols validés avant le plan 2b, le compte débité peut ne pas être
  le créateur (données de dev seulement).
- Export CSV du relevé : vérifié par tests unitaires ; le téléchargement dans
  le navigateur reste à contrôler en recette web.

### Rappel côté AppGAP (plan 6)

Le pont `syncUlmFlights` d'AppGAP ne doit copier que les vols
`status == 'valide'`, et `externalCount` doit inclure `passengers.length`.
Spec §8.
