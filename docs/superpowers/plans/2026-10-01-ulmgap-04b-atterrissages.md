# UlmGap, plan 4b : atterrissages, amerrissages et heure de fin à la clôture

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** saisir à la clôture le nombre d'atterrissages, et d'amerrissages
pour un appareil amphibie, puis les afficher dans le carnet de vol. À la
clôture, allonger l'heure de fin quand le temps de vol saisi dépasse la
durée prévue.

**Architecture :** comme au plan 3.
- Toute écriture passe par les callables `closeFlight`, `adminUpdateFlight`
  et `adminUpsertAircraft`.
- La règle d'heure de fin est une fonction pure du module `rules/`.
- L'app reprend les contrôles en local (dialogue de clôture, correction
  admin) ; le serveur reste l'autorité.

**Tech Stack :** inchangée.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §2.3,
§2.5, §3.3, §5 (clôture, carnet de vol). Elle est mise à jour à la Task 6.

**Branche :** `feature/compteurs` (suite du plan 4).

## Décisions de l'utilisateur (2026-10-01)

1. **Atterrissages** : nombre saisi à chaque clôture, pour tout appareil.
2. **Amerrissages** : nombre saisi à la clôture, seulement pour un appareil
   **amphibie**. Le drapeau `amphibious` est réglé par un admin dans la fiche
   appareil.
3. **Saisie** : « Atterrissages » est pré-rempli à 1 et « Amerrissages » à 0,
   les deux modifiables. Valeurs entières de 0 à 99, avec **au moins 1 au
   total**. Sur un appareil classique, il faut donc au moins 1 atterrissage.
4. **Heure de fin** : si `fin − début` est **inférieur** au temps de vol
   saisi, la fin devient `début + temps de vol`. Si cet écart est supérieur
   ou égal, la fin ne change pas (l'appareil a pu rester posé ailleurs).
5. **Affichage** :
   - en haut du carnet, sous le temps de vol : « Atterrissages : N », puis
     « · Amerrissages : N » seulement s'il y en a sur la période ;
   - sur chaque vol clôturé : « Clôturé · 1 h 15 · 2 att. », complété par
     « · 1 am. » s'il y en a ;
   - dans le récapitulatif de la fenêtre du vol clôturé.
6. **Correction admin d'un vol clôturé** : atterrissages et amerrissages y
   sont modifiables, et la règle de la décision 4 s'applique à la durée
   réelle corrigée.

## Décisions du contrôleur (à relire)

- **Données en base.** `flights.landings: int` et
  `flights.waterLandings: int`. Pour un appareil non amphibie,
  `waterLandings` vaut 0. Les vols clôturés avant ce plan n'ont pas ces
  champs : ils comptent 0, et le libellé « att. » est omis.
- **Serveur.** `closeFlight` lit l'appareil du vol :
  - s'il n'est pas amphibie, un `waterLandings` > 0 est refusé avec le
    message « Cet appareil n'est pas amphibie. » ;
  - un `waterLandings` absent vaut 0, un `landings` absent est refusé.
- **Allongement de la fin à la clôture.** Pas de contrôle de conflit : le
  vol a eu lieu. En correction admin, la fin allongée passe par
  `planFlight`, qui vérifie les conflits comme pour toute correction.
- **Correction admin.** Les nombres absents restent inchangés. Pour un vol
  clôturé sans nombres (données anciennes), l'app pré-remplit 1 et 0. Si
  l'admin change d'appareil vers un appareil non amphibie avec des
  amerrissages, la correction est refusée (même message).
- **Champs hors contrat AppGAP.** `landings` et `waterLandings` ne sont pas
  lus par le pont. En revanche, `end` est un champ du contrat : le pont
  recopie la fin allongée.

## Global Constraints

- `fvm flutter` / `fvm dart` ; TDD ; textes en français.
- Aucune écriture client ; aucune règle Firestore ni index nouveau.
- Déploiement **dev** seulement, à la fin :
  `firebase deploy --only functions:closeFlight,functions:adminUpdateFlight,functions:adminUpsertAircraft --project dev`.
- Vérification : `fvm flutter test && fvm flutter analyze`, `cd functions &&
  npm test`, puis les tests d'intégration (JDK d'Android Studio).

## Review Focus

1. **Temps de vol plus long que prévu** : la fin s'allonge à la clôture ;
   un temps plus court ne change rien. Le cas d'égalité ne change rien non
   plus (Task 1 et Task 3).
2. **Amerrissages sur un appareil non amphibie** : le serveur refuse, à la
   clôture comme en correction admin, y compris après un changement
   d'appareil (Task 3 et Task 4).
3. **Total nul** (0 atterrissage et 0 amerrissage) : refusé par le dialogue
   et par le serveur (Task 2 et Task 5).
4. **Vol clôturé avant ce plan, sans `landings`** : il s'affiche sans
   « att. », compte 0 dans les totaux, et la correction admin pré-remplit
   1 et 0 (Task 5 et Task 6).
5. **Correction admin qui allonge la fin vers un vol suivant** : un conflit
   est signalé comme pour toute correction, sans plantage (Task 4).

---

### Task 1 : règle pure de l'heure de fin

**Files:** create `functions/src/rules/closing.ts`, test
`functions/src/rules/closing.test.ts`.

**Produces :** `export function closingEnd(startMs: number, endMs: number, actualMinutes: number): number`.

- [ ] Test qui échoue :

```ts
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { closingEnd } from "./closing";

const M = 60_000;
test("temps de vol plus long que prévu : fin = début + temps de vol", () => {
  assert.equal(closingEnd(0, 60 * M, 90), 90 * M);
});
test("temps de vol plus court : fin inchangée (appareil posé ailleurs)", () => {
  assert.equal(closingEnd(0, 180 * M, 90), 180 * M);
});
test("égalité : fin inchangée", () => {
  assert.equal(closingEnd(0, 90 * M, 90), 90 * M);
});
```

- [ ] Implémentation :

```ts
// Heure de fin à la clôture (plan 4b, décision 4) : allongée si le temps de
// vol réel dépasse fin − début, jamais raccourcie. Module pur.
export function closingEnd(startMs: number, endMs: number, actualMinutes: number): number {
  return Math.max(endMs, startMs + actualMinutes * 60_000);
}
```

- [ ] `cd functions && npm test` : PASS, puis commit
  `feat(functions): closing end-time rule`.

### Task 2 : validation des nombres et appareil amphibie (serveur)

**Files:** `functions/src/flights/validation.ts` (+ `validation.test.ts`),
`functions/src/admin/validation.ts` (+ `validation.test.ts`),
`functions/src/admin/aircraft.ts`.

**Produces :**
- `validateClosing` renvoie en plus `landings: number` et
  `waterLandings: number` (0 par défaut).
- `validateAdminUpdate` renvoie en plus `landings?: number` et
  `waterLandings?: number`.
- `validateAircraft` renvoie `amphibious: boolean` (faux par défaut), et
  `upsertAircraft` l'écrit.

- [ ] Tests qui échouent, dans `functions/src/flights/validation.test.ts` :
  - `validateClosing({flightId, actualMinutes: 60, landings: 2})` →
    `landings 2, waterLandings 0` ;
  - `landings` absent → `ValidationError` « Nombre d'atterrissages
    invalide (0 à 99). » ;
  - `landings: 100`, `-1` ou `1.5` → même erreur ;
  - `waterLandings: 100` → « Nombre d'amerrissages invalide (0 à 99). » ;
  - `landings: 0, waterLandings: 0` → « Au moins un atterrissage ou
    amerrissage. » ;
  - `landings: 0, waterLandings: 1` → accepté ;
  - `validateAdminUpdate` : les nombres absents restent `undefined` ; un
    nombre hors plage donne le même message.

  Dans `functions/src/admin/validation.test.ts` :
  - `validateAircraft({registration: "F-JA", label: "ULM 1"}).amphibious === false` ;
  - avec `amphibious: true` → `true`.
- [ ] Implémentation, dans `functions/src/flights/validation.ts` :

```ts
function count(v: unknown, label: string): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > 99) {
    throw new ValidationError(`Nombre ${label} invalide (0 à 99).`);
  }
  return v;
}
function checkTotal(landings: number, waterLandings: number): void {
  if (landings + waterLandings < 1) throw new ValidationError("Au moins un atterrissage ou amerrissage.");
}
```

  - `validateClosing` : `landings = count(d.landings, "d'atterrissages")`,
    `waterLandings = d.waterLandings === undefined ? 0 : count(d.waterLandings, "d'amerrissages")`,
    puis `checkTotal`.
  - `validateAdminUpdate` : même conversion pour chaque champ présent. Le
    total est vérifié par l'action, après fusion avec les valeurs stockées.
  - `validateAircraft` : `amphibious: bool(d.amphibious, "Amphibie", false)`,
    écrit par `upsertAircraft` (`amphibious: a.amphibious` dans `tx.set`).
- [ ] `cd functions && npm test` : PASS, puis commit
  `feat(functions): landings validation, amphibious aircraft`.

### Task 3 : `closeFlight` enregistre les nombres et allonge la fin

**Files:** `functions/src/flights/close.ts`,
`functions/src/flights/close.int.test.ts`,
`functions/src/flights/testkit.ts` (`seedAircraft(active = true, amphibious = false)`).

- [ ] Tests d'intégration qui échouent (ajouter `landings: 1` aux appels
  existants de `closeFlight` qui doivent réussir) :
  - vol de 9 h à 10 h, clôturé avec 90 min et 2 atterrissages →
    `end = start + 90 min`, `landings 2`, `waterLandings 0`, et `updatedAt`
    mis à jour ;
  - vol de 9 h à 12 h, clôturé avec 90 min → `end` inchangé ;
  - appareil amphibie, `landings 1` et `waterLandings 3` → enregistrés ;
  - appareil non amphibie avec `waterLandings 1` → `failed-precondition`
    « Cet appareil n'est pas amphibie. », et le vol reste non clôturé.
- [ ] Implémentation, dans `close.ts`. Lectures avant écritures :
  - lire `aircraft/{aircraftId}` après le vol ; si
    `waterLandings > 0 && aircraft.amphibious !== true`, refuser ;
  - dans `tx.update`, ajouter
    `landings`, `waterLandings` et
    `end: Timestamp.fromMillis(closingEnd(start, end, actualMinutes))`.
- [ ] Tests unitaires et d'intégration : PASS, puis commit
  `feat(functions): closeFlight records landings and extends end time`.

### Task 4 : `adminUpdateFlight` (vol clôturé)

**Files:** `functions/src/flights/admin-edit.ts`,
`functions/src/flights/admin-edit.int.test.ts`.

- [ ] Tests d'intégration qui échouent :
  - correction d'un vol clôturé avec `landings: 3` → enregistré, les
    autres nombres sont conservés ;
  - nombre envoyé sur un vol non clôturé → « Réservé aux vols clôturés. » ;
  - durée réelle corrigée à 120 min sur un vol de 60 min → `end = start + 120 min` ;
  - `waterLandings: 1` sur un appareil non amphibie → « Cet appareil n'est
    pas amphibie. » ;
  - fin allongée qui chevauche un autre vol validé du même appareil →
    conflit (`failed-precondition`, avec `details.conflict`).
- [ ] Implémentation :
  - ajouter `v.landings !== undefined || v.waterLandings !== undefined` à
    la condition « Réservé aux vols clôturés » ;
  - sur un vol clôturé, avant `planFlight`, remplacer `v.input.end` par
    `closingEnd(v.input.start, v.input.end, actualMinutes)`, où
    `actualMinutes = v.actualMinutes ?? stocké`. `planFlight` contrôle alors
    les conflits sur l'intervalle réel ;
  - fusionner les nombres (`v.x ?? stocké ?? 0`, avec 1 pour `landings`
    si le vol n'en a pas), lire l'appareil de `v.input.aircraftId` pour le
    contrôle amphibie, vérifier le total ≥ 1, et écrire `landings` et
    `waterLandings` dans le `tx.update` du vol clôturé.
- [ ] Tests : PASS, puis commit
  `feat(functions): admin correction of landings and end-time rule`.

### Task 5 : app, modèles, dialogue de clôture, correction admin

**Files:**
- `lib/data/aircraft.dart` (`amphibious`) ;
- `lib/data/flight.dart` (`landings`, `waterLandings`, tous deux `int?`) ;
- `lib/data/finance_api.dart` (`closeFlight(..., required int landings, int waterLandings = 0)`, et le fake dans `test/support/fakes.dart`) ;
- `lib/features/admin/aircraft_form_dialog.dart` (switch « Amphibie »,
  `Key('a-amphibious')`) et `aircraft_admin_screen.dart` (sous-titre
  « F-JABC · amphibie ») ;
- `lib/features/flight/closing_dialog.dart` (`amphibious`, champs
  `Key('closing-landings')` pré-rempli à « 1 » et
  `Key('closing-water-landings')` pré-rempli à « 0 », amphibie seulement ;
  `ClosingResult` gagne `landings` et `waterLandings`) ;
- `lib/features/flight/flight_screen.dart` (amphibie lu dans `_aircraft`,
  passé au dialogue et transmis à `closeFlight` ; en correction d'un vol
  clôturé, champs `Key('correct-landings')` et
  `Key('correct-water-landings')`, celui-ci seulement si l'appareil choisi
  est amphibie ; mêmes contrôles ; payload `landings`, `waterLandings`) ;
- `lib/features/flight/flight_texts.dart` (`closedSummary` gagne
  `landings` et `waterLandings`, `int?`) ;
- tests : `test/data/flight_test.dart`, `test/features/flight/flight_screen_test.dart`,
  `test/features/flight/flight_texts_test.dart`,
  `test/features/admin/aircraft_admin_screen_test.dart`.

**Produces :**
- `String landingsText(int? landings, int? waterLandings)` dans
  `flight_texts.dart`. Il renvoie « 2 att. » ou « 2 att. · 1 am. », et
  une chaîne vide si `landings` est null.
- `closedSummary(...)` termine par « , 2 att. » ou « , 2 att., 1 am. »,
  rien si `landings` est null.

- [ ] Tests qui échouent :
  - `Flight.fromMap` lit `landings` et `waterLandings` (null si absents) ;
  - `Aircraft.fromMap` lit `amphibious` (faux par défaut) ;
  - dialogue de clôture :
    - « Atterrissages » vaut « 1 », sans champ amerrissages sur un appareil
      classique ;
    - sur un appareil amphibie, les deux champs sont présents ;
    - 0 et 0 donnent l'erreur « Au moins un atterrissage ou amerrissage. » ;
    - 100 donne « Nombre d'atterrissages invalide (0 à 99). » ;
    - la clôture envoie `landings` et `waterLandings` au fake ;
  - correction admin : envoi de `landings` ; pré-remplissage à 1 et 0 pour
    un vol sans nombres ;
  - `closedSummary` et `landingsText` (vides si null) ;
  - formulaire appareil : le switch « Amphibie » renvoie `amphibious: true`.
- [ ] Implémentation, puis `fvm flutter test && fvm flutter analyze`, puis
  commit `feat(app): landings and water landings at closing`.

### Task 6 : carnet de vol, docs, déploiement dev

**Files:** `lib/features/logbook/logbook.dart`
(`({int landings, int waterLandings}) totalLandings(Iterable<Flight>)`, vols
clôturés non supprimés, null = 0), `logbook.dart` `performedLabel`
(« Clôturé · 1 h 15 · 2 att. »), `logbook_screen.dart`
(`Key('logbook-landings')` : « Atterrissages : N », complété par
« · Amerrissages : N » si > 0), tests du carnet, la spec et CLAUDE.md.

- [ ] Tests qui échouent :
  - `totalLandings` ignore les vols non clôturés et supprimés, et compte 0
    pour un null ;
  - `performedLabel` avec et sans nombres ;
  - l'écran affiche « Atterrissages : 3 » sans amerrissages, puis
    « Atterrissages : 3 · Amerrissages : 2 ».
- [ ] Implémentation ; suites Dart et Functions (unitaires et
  intégration) ; commit `feat(app): landings totals in the logbook`.
- [ ] Spec :
  - §2.3 : `amphibious` ;
  - §2.5 : `landings`, `waterLandings`, et `end` allongée à la clôture ;
  - §3.3 : `closeFlight` (atterrissages, amerrissages, fin) ;
  - §5 : clôture et carnet de vol.

  CLAUDE.md : plan 4b terminé, Functions redéployées en dev, prod à
  redéployer. Commit `docs: plan 4b in spec and CLAUDE.md`.
- [ ] Déploiement dev (commande des Global Constraints).

---

## Révision du 2026-10-01 : conflits en planification seulement

Retour de l'utilisateur : « les blocages sont pour la planification, jamais
pour la conduite ». Un vol décalé (météo) décale les suivants. Une fin
allongée à la clôture, une correction d'horaires ou de temps de vol ne doit
jamais rien bloquer.

- `findConflict` (TS et Dart, cas partagés dans `test/fixtures/flight_rules.json`) :
  un vol clôturé n'est jamais en conflit.
- `isPlanning(start, now, closed)` : le contrôle de conflit ne s'applique
  qu'à un vol à venir non clôturé. Il est utilisé par `planFlight` (donc
  `createFlight`, `updateFlight`, `validateFlight`, `adminUpdateFlight`) et
  par l'aperçu de `FlightScreen`.
- Ceci remplace la décision du contrôleur « en correction admin, la fin
  allongée passe par `planFlight`, qui vérifie les conflits » et le point 5
  de la Review Focus : une correction qui allonge la fin vers un vol
  suivant est désormais acceptée.
- La saisie après coup d'un vol passé par un admin n'est plus soumise aux
  conflits non plus (avant : « conflits toujours contrôlés »).
