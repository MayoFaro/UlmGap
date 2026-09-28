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

Sur Android/iOS, `--flavor` et `--dart-define=ENV` doivent **toujours être
passés ensemble et concordants** : un flavor `prod` installe l'app de prod
(`com.ulmgap.app`), qui parlerait à `ulmgap-dev` sans `ENV=prod`. Au
démarrage, l'app compare son flavor de compilation (`appFlavor`) à `ENV` et
**bloque** (écran d'erreur, pas d'accès à Firebase) en cas de discordance ;
sans flavor (web), aucun contrôle n'est fait.

## Contrat avec AppGAP (NE PAS CASSER)

Le pont AppGAP (`syncUlmFlights`) lit la collection `flights` de
`ulmgap-prod`. Ces champs ne doivent ni changer de nom ni de sens :
`start`, `end`, `destination`, `aircraft` (immatriculation), `crew` (uid),
`passengers` (noms), `status` (`demande`/`valide`/`refuse`), `isClosed`,
`actualFlightMinutes`, `deleted` (suppression logique uniquement),
`updatedAt` (horodatage serveur à chaque écriture). Voir la spec §2.5 et §8.

## Tests des Functions

```bash
cd functions
npm test                 # tests unitaires
npm run test:int         # émulateurs Auth + Firestore (nécessite Java 21)
```

Les émulateurs de `firebase-tools` 15 exigent Java 21. Sur cette machine,
utiliser le JDK d'Android Studio :
`JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`.

## Premier admin (une fois par projet)

```bash
cd functions && npm run build
node scripts/bootstrap-admin.js --project ulmgap-dev --email moi@x.fr --name "Mon Nom" --short ABC
```

Ouvrir le lien affiché pour définir le mot de passe, puis se connecter à
l'app et vérifier l'e-mail.

## Comptes de test (dev)

Réservé à `ulmgap-dev` (ou un projet d'émulateur `demo-*`) : refusé sur tout
autre projet, y compris la prod. Crée 8 comptes fixes (un par profil et
appartenance), e-mail déjà vérifié, mot de passe fourni en argument.
Relançable sans risque : les comptes déjà créés sont remis à niveau (mot de
passe, vérification) sans toucher leur solde.

```bash
cd functions && npm run build
node scripts/seed-test-users.js --project ulmgap-dev --password <mot de passe, 8 car. min>
```

Comptes créés (e-mail `test-<code>@ulmgap.invalid`) :

| code | Nom | Profil | Appartenance |
|---|---|---|---|
| eleve-ext | Élève Externe | eleve | EXT |
| eleve-gap | Élève GAP | eleve | GAP |
| solo-gap | Lâché Solo GAP | lache_solo | GAP |
| ltm-gap | Lâché Mission GAP | lache_toute_mission | GAP |
| ltm-mil | Lâché Mission MIL | lache_toute_mission | MIL |
| instr-gap | Instructeur GAP | instructeur | GAP |
| instr-gr | Instructeur GR | instructeur | GR |
| gest-gap | Gestionnaire GAP | — | GAP |
