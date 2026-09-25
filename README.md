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
