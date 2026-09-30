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
- Plan 4, compteurs et vols effectués (terminé) : `docs/superpowers/plans/2026-09-30-ulmgap-04-compteurs.md`
- Découpage prévu des plans suivants :
  2. vols et matrice de droits ;
  3. finances (forfaits, crédit FCFA, relevé) ;
  4. compteurs pilote et appareil, et panneau « Vols effectués » (clôturés
     ou non, date ≤ aujourd'hui) : c'est là qu'on clôture les vols ;
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

## État au 2026-09-30

- Plans 1 à 4 terminés. `main` contient les plans 1, 2 et 2b ; le plan 3 est
  sur `feature/finances`, le plan 4 sur `feature/compteurs` (créée depuis
  `feature/finances`) ; aucune des deux n'est fusionnée.
- En dev : Authentication activé, premier admin (DPS), règles et Functions du
  plan 3 déployées (vols, finances : `closeFlight`, `creditAccount`,
  `correctAccount`, `adminUpdateFlight`, `adminDeleteFlight`,
  `adminUpdatePricing`). Crédit initial de 500 000 FCFA versé aux 4 comptes
  de dev (transaction « Crédit initial (tests) »). Plan 4 : `closeFlight`
  redéployée (clôture dès le jour du vol, à l'heure d'Africa/Libreville).
- En prod : **règles et Functions à déployer par l'utilisateur avant le
  25/10/2026**, date d'expiration des règles du mode test (Functions dans
  leur version du plan 4 : `closeFlight` a changé ; ni règle ni index
  nouveau au plan 4). Premier admin à
  créer ensuite (`cd functions && npm run build && node
  scripts/bootstrap-admin.js --project ulmgap-prod …`), et Authentication à
  activer (e-mail et mot de passe, création de compte par l'utilisateur
  désactivée).
- **Node.js 20 retiré par Google Cloud le 30/10/2026** : après cette date,
  plus aucun déploiement de Functions possible sans passer à Node 22
  (`functions/package.json` → `engines.node`) et sans mettre à jour
  `firebase-functions`. À faire avant.
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

- Plan 5 (notifications) : rappels de clôture ; tant qu'ils n'existent pas,
  des vols validés passés restent non clôturés et pèsent sur le crédit
  disponible.
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
