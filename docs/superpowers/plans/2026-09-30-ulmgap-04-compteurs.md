# UlmGap, plan 4 : compteurs et panneau « Vols effectués »

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** livrer les écrans « Vols effectués » (seul accès aux vols passés,
donc à la clôture) et « Compteurs » (pilote et appareil) de la spec §5.

**Architecture :** presque tout se passe **côté client**. Seule exception :
`closeFlight` accepte désormais un vol **du jour**, même avant l'heure de
départ (décision 6). Aucune règle Firestore ni aucun index nouveau.
- Les lectures existent déjà : `FinanceApi.watchFlightsBetween` (vols par
  période). On ajoute une seule requête, `watchValidUnclosedFlights`, avec
  deux égalités et donc sans index composite.
- La clôture existe déjà (plan 3) : `FlightScreen` affiche « Clôturer » selon
  `flightActions`. Le panneau ouvre simplement `FlightScreen`. La condition
  passe de « départ passé » à « date du jour ou avant », à l'heure du club
  (`Africa/Libreville`, UTC+1 fixe, sans heure d'été).
- Les calculs sont des **fonctions pures**, testées sans widget :
  `lib/features/counters/counters.dart` et
  `lib/features/performed/performed.dart`.
- Le sélecteur de période « Du … / Au … » du relevé devient un widget commun,
  `lib/core/period_bar.dart`, réutilisé par les trois écrans.

**Tech Stack :** Flutter 3.32.8 (`fvm flutter`), cloud_firestore. Aucun
paquet nouveau.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §3.1
(vol effectué), §3.3 (`closeFlight`), §5 (Vols effectués, Compteurs, Mon
compte), §7.3 (`lib/features/counters`).

**Branche :** `feature/compteurs`, créée depuis `feature/finances` (le plan 3
n'est pas encore fusionné dans `main`).

## Décisions de l'utilisateur (2026-09-30)

1. **Visibilité des vols effectués** : un pilote ne voit que les vols dont il
   est membre de l'équipage (`crew`). Les instructeurs et les admins voient
   tous les vols.
2. **Filtres** : période (mois en cours par défaut, boutons « Du … / Au … »
   comme au relevé), appareil (« Tous les appareils » par défaut) et
   « À clôturer seulement ».
   - Les vols à clôturer sont surlignés en orange.
   - En haut de la liste, un compteur affiche « N vols à clôturer ».
   - Tri : du plus récent au plus ancien.
   - Seuls les vols **validés et non supprimés** apparaissent : pas les
     refusés ni les demandes expirées.
3. **Compteur pilote** : chaque membre de `crew` cumule les
   `actualFlightMinutes` du vol, l'instructeur comme l'élève. Les passagers
   sans compte ne comptent pas.
4. **Accès** : deux icônes dans la barre du haut, « Vols effectués » et
   « Compteurs ». L'écran « Compteurs » a deux onglets, « Pilote » et
   « Appareil ».
5. **« Se déconnecter » quitte la barre d'accueil** et passe dans la barre de
   « Mon compte ». Sans ce déplacement, la barre d'un admin déborderait sur un
   téléphone de 360 px de large. Il reste 5 icônes ; le titre « UlmGap »
   peut être tronqué.
6. **Vol du jour = à clôturer**, sans condition d'heure : un vol validé non
   clôturé dont la date est aujourd'hui ou avant est « à clôturer ».
   L'équipage peut le clôturer dès le jour du vol, même avant l'heure de
   départ prévue (« un équipage ne clôture pas un vol qui n'a pas eu lieu »).
   Côté serveur, `closeFlight` compare les dates à l'heure du club
   (UTC+1) ; il refuse toujours un vol d'un jour suivant.

## Décisions du contrôleur (à relire)

- **Vols à clôturer de toute période.** Avec le seul filtre de période, un vol
  non clôturé du mois précédent disparaîtrait de la vue par défaut, alors
  qu'il réserve encore du crédit. Le compteur « N vols à clôturer » et le
  filtre « À clôturer seulement » portent donc sur **toutes les périodes**
  (requête `watchValidUnclosedFlights`). Quand ce filtre est coché, les
  boutons de période sont désactivés.
- **Vol à clôturer** = validé, non supprimé, non clôturé, date du jour ou
  avant (décision 6, même règle que l'action « Clôturer »).
- **Libellé à droite de chaque vol** : « Clôturé · 1 h 15 » ou
  « À clôturer » (orange).
- **Avant l'heure de départ d'un vol du jour**, les actions d'avant départ
  (modifier, annuler, valider, refuser) restent disponibles, en plus de
  « Clôturer ».
- **Période des compteurs** : l'année civile en cours par défaut, commune aux
  deux onglets. On garde le format de durée existant, `formatDurationHm`
  (« 154 h 45 »), plutôt que « 154h45 ».
- **Sélecteurs des compteurs** : tout l'annuaire (comptes inactifs compris,
  pour l'historique), le compte connecté par défaut. Pour l'appareil, tous
  les appareils, inactifs compris, avec le premier actif par défaut.
- **Déconnexion depuis « Mon compte »** : on revient d'abord à la racine du
  `Navigator` (`popUntil(isFirst)`), puis on se déconnecte. Sinon, l'écran
  « Mon compte » resterait empilé au-dessus de l'écran de connexion.

## Global Constraints

- Toujours `fvm flutter` / `fvm dart`, jamais `flutter` nu.
- TDD : chaque changement commence par un test qui échoue.
- Textes de l'interface en français.
- Aucune écriture client dans Firestore.
- Seul changement serveur : la condition de date de `closeFlight`. Tests
  unitaires et d'intégration des Functions à relancer ; déploiement en
  **dev** seulement (`firebase deploy --only functions:closeFlight --project dev`).
- Aucune requête qui exige un index composite (pas de `firestore.indexes.json`
  à déployer).
- Ne jamais déployer en prod.
- Vérification finale : `fvm flutter test && fvm flutter analyze`, sans aucun
  problème signalé.

## Review Focus

1. **Vol non clôturé d'un mois précédent** : il doit être compté dans « N vols
   à clôturer » et apparaître avec « À clôturer seulement », même hors de la
   période affichée (Task 5, test « vol à clôturer hors période »).
2. **Vol du jour pas encore parti, et fuseau horaire** : il est « à
   clôturer » et le serveur accepte sa clôture. Un vol du lendemain est
   refusé, y compris vers minuit à l'heure du club alors qu'il est encore la
   veille en UTC (Task 3, tests `localDay`).
3. **Vol clôturé puis supprimé par un admin, ou clôturé sans
   `actualFlightMinutes`** (données anciennes) : il compte 0 minute, sans
   plantage (Task 1).
4. **Déconnexion depuis « Mon compte »** : l'écran ne doit pas rester affiché
   après la déconnexion (Task 7, test `popUntil`).
5. **Barre d'accueil d'un admin sur 360 px de large** : aucun débordement, et
   les 5 icônes restent accessibles (Task 7). De même, un annuaire encore vide
   dans « Compteurs » ne doit pas planter la liste déroulante (Task 6).

---

### Task 1 : calcul des compteurs (fonctions pures)

**Files:**
- Create: `lib/features/counters/counters.dart`
- Test: `test/features/counters/counters_test.dart`

**Interfaces:**
- Consumes : `Flight` (`lib/data/flight.dart`), champs `isClosed`, `deleted`,
  `actualFlightMinutes`, `crew`, `aircraftId`.
- Produces :
  - `int countedMinutes(Flight f)`
  - `int pilotMinutes(Iterable<Flight> flights, String uid)`
  - `int aircraftMinutes(Iterable<Flight> flights, String aircraftId)`

- [ ] **Step 0 : vérifier la branche** (créée avec le plan)

```bash
git checkout feature/compteurs
```

- [ ] **Step 1 : écrire le test qui échoue**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/counters/counters.dart';

import '../../support/fakes.dart';

void main() {
  group('countedMinutes', () {
    test('vol clôturé non supprimé : ses minutes réelles', () {
      expect(countedMinutes(testFlight(isClosed: true, actualFlightMinutes: 75)), 75);
    });
    test('vol non clôturé : 0', () {
      expect(countedMinutes(testFlight(actualFlightMinutes: 75)), 0);
    });
    test('vol clôturé puis supprimé : 0', () {
      expect(
          countedMinutes(testFlight(isClosed: true, deleted: true, actualFlightMinutes: 75)), 0);
    });
    test('vol clôturé sans minutes réelles (données anciennes) : 0', () {
      expect(countedMinutes(testFlight(isClosed: true)), 0);
    });
  });

  test('pilotMinutes : tout membre de l\'équipage cumule, pas les autres', () {
    final flights = [
      testFlight(id: 'a', crew: ['u1', 'u2'], isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'b', crew: ['u2'], isClosed: true, actualFlightMinutes: 45),
      testFlight(id: 'c', crew: ['u1'], passengers: ['Paul'], isClosed: true, actualFlightMinutes: 90),
      testFlight(id: 'd', crew: ['u1']), // non clôturé
    ];
    expect(pilotMinutes(flights, 'u1'), 150);
    expect(pilotMinutes(flights, 'u2'), 105);
    expect(pilotMinutes(flights, 'u3'), 0);
  });

  test('aircraftMinutes : seuls les vols de l\'appareil', () {
    final flights = [
      testFlight(id: 'a', aircraftId: 'a1', isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'b', aircraftId: 'a2', isClosed: true, actualFlightMinutes: 45),
      testFlight(id: 'c', aircraftId: 'a1', isClosed: true, actualFlightMinutes: 30),
    ];
    expect(aircraftMinutes(flights, 'a1'), 90);
    expect(aircraftMinutes(flights, 'a2'), 45);
    expect(aircraftMinutes(flights, 'a9'), 0);
  });
}
```

- [ ] **Step 2 : lancer le test, il doit échouer**

Run: `fvm flutter test test/features/counters/counters_test.dart`
Expected : échec de compilation, `counters.dart` introuvable.

- [ ] **Step 3 : implémentation minimale**

```dart
// Compteurs d'heures (spec §5) : base = actualFlightMinutes des vols
// clôturés, non supprimés. Fonctions pures, testées sans widget.
import '../../data/flight.dart';

/// Minutes comptées pour [f] : 0 s'il n'est pas clôturé, s'il est supprimé
/// ou s'il n'a pas de durée réelle.
int countedMinutes(Flight f) =>
    f.isClosed && !f.deleted ? (f.actualFlightMinutes ?? 0) : 0;

/// Total d'un pilote : chaque membre de `crew` cumule le vol (décision 3).
int pilotMinutes(Iterable<Flight> flights, String uid) => flights
    .where((f) => f.crew.contains(uid))
    .fold(0, (sum, f) => sum + countedMinutes(f));

/// Total d'un appareil.
int aircraftMinutes(Iterable<Flight> flights, String aircraftId) => flights
    .where((f) => f.aircraftId == aircraftId)
    .fold(0, (sum, f) => sum + countedMinutes(f));
```

- [ ] **Step 4 : relancer, le test doit passer**

Run: `fvm flutter test test/features/counters/counters_test.dart`
Expected : PASS.

- [ ] **Step 5 : commit**

```bash
git add lib/features/counters/counters.dart test/features/counters/counters_test.dart
git commit -m "feat(app): pilot and aircraft counter computations"
```

---

### Task 2 : règles du panneau « Vols effectués » (fonctions pures)

**Files:**
- Create: `lib/features/performed/performed.dart`
- Test: `test/features/performed/performed_test.dart`

**Interfaces:**
- Consumes : `Flight`, `FlightStatus` (`lib/data/flight.dart`), `AppUser`
  (`lib/data/app_user.dart`, `isAdmin`, `isInstructor`, `uid`), `dayOf`
  (`lib/core/formats.dart`), `formatDurationHm` et `statusColor`
  (`lib/features/flight/flight_texts.dart`).
- Produces :
  - `bool isPerformed(Flight f, DateTime now)`
  - `bool needsClosing(Flight f, DateTime now)` (utilisée aussi par
    `flightActions`, Task 3)
  - `bool visibleTo(Flight f, AppUser me)`
  - `List<Flight> performedList(Iterable<Flight> flights, {required AppUser me, required DateTime now, String? aircraftId})` : triée du plus récent au plus ancien.
  - `String performedLabel(Flight f, DateTime now)`
  - `String toCloseCountText(int n)`
  - constantes `Color toCloseColor`, `Color toCloseFill`

- [ ] **Step 1 : écrire le test qui échoue**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/performed/performed.dart';

import '../../support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 15, 12);

  group('needsClosing', () {
    test('validé, non clôturé, départ passé : à clôturer', () {
      expect(needsClosing(testFlight(start: DateTime(2026, 10, 15, 9)), now), isTrue);
    });
    test('vol du jour pas encore parti : à clôturer (décision 6)', () {
      expect(needsClosing(testFlight(start: DateTime(2026, 10, 15, 23, 30)), now), isTrue);
    });
    test('vol de demain : non', () {
      expect(needsClosing(testFlight(start: DateTime(2026, 10, 16, 0, 0)), now), isFalse);
    });
    test('clôturé, supprimé, demande ou refusé : non', () {
      final past = DateTime(2026, 10, 10, 9);
      expect(needsClosing(testFlight(start: past, isClosed: true), now), isFalse);
      expect(needsClosing(testFlight(start: past, deleted: true), now), isFalse);
      expect(needsClosing(testFlight(start: past, status: 'demande'), now), isFalse);
      expect(needsClosing(testFlight(start: past, status: 'refuse'), now), isFalse);
    });
  });

  group('isPerformed', () {
    test('validé, départ aujourd\'hui ou avant : oui, même pas encore parti', () {
      expect(isPerformed(testFlight(start: DateTime(2026, 10, 1, 9)), now), isTrue);
      expect(isPerformed(testFlight(start: DateTime(2026, 10, 15, 23, 30)), now), isTrue);
    });
    test('départ demain : non', () {
      expect(isPerformed(testFlight(start: DateTime(2026, 10, 16, 0, 0)), now), isFalse);
    });
    test('supprimé, demande (expirée) ou refusé : non', () {
      final past = DateTime(2026, 10, 10, 9);
      expect(isPerformed(testFlight(start: past, deleted: true), now), isFalse);
      expect(isPerformed(testFlight(start: past, status: 'demande'), now), isFalse);
      expect(isPerformed(testFlight(start: past, status: 'refuse'), now), isFalse);
    });
  });

  group('visibleTo', () {
    final f = testFlight(crew: ['u2', 'u3']);
    test('pilote : seulement s\'il est dans l\'équipage', () {
      expect(visibleTo(f, testUser(uid: 'u1', profile: 'lache_solo')), isFalse);
      expect(visibleTo(f, testUser(uid: 'u3', profile: 'eleve')), isTrue);
    });
    test('instructeur ou admin : tout', () {
      expect(visibleTo(f, testUser(uid: 'u1', profile: 'instructeur')), isTrue);
      expect(visibleTo(f, testUser(uid: 'u1', profile: null, isAdmin: true)), isTrue);
    });
  });

  test('performedList : filtre, appareil, tri du plus récent au plus ancien', () {
    final me = testUser(uid: 'u1', profile: 'lache_solo');
    final flights = [
      testFlight(id: 'old', start: DateTime(2026, 10, 2, 9), crew: ['u1']),
      testFlight(id: 'recent', start: DateTime(2026, 10, 12, 9), crew: ['u1']),
      testFlight(id: 'other-ac', start: DateTime(2026, 10, 8, 9), crew: ['u1'], aircraftId: 'a2'),
      testFlight(id: 'not-mine', start: DateTime(2026, 10, 9, 9), crew: ['u2']),
      testFlight(id: 'future', start: DateTime(2026, 10, 20, 9), crew: ['u1']),
    ];
    expect(performedList(flights, me: me, now: now).map((f) => f.id),
        ['recent', 'other-ac', 'old']);
    expect(performedList(flights, me: me, now: now, aircraftId: 'a1').map((f) => f.id),
        ['recent', 'old']);
  });

  test('performedLabel', () {
    expect(
        performedLabel(
            testFlight(start: DateTime(2026, 10, 10, 9), isClosed: true, actualFlightMinutes: 75),
            now),
        'Clôturé · 1 h 15');
    expect(performedLabel(testFlight(start: DateTime(2026, 10, 10, 9)), now), 'À clôturer');
    expect(performedLabel(testFlight(start: DateTime(2026, 10, 15, 14)), now), 'À clôturer');
  });

  test('toCloseCountText : singulier et pluriel', () {
    expect(toCloseCountText(1), '1 vol à clôturer');
    expect(toCloseCountText(3), '3 vols à clôturer');
  });
}
```

- [ ] **Step 2 : lancer le test, il doit échouer**

Run: `fvm flutter test test/features/performed/performed_test.dart`
Expected : échec de compilation, `performed.dart` introuvable.

- [ ] **Step 3 : implémentation minimale**

```dart
// Panneau « Vols effectués » (spec §5, plan 4) : règles pures de filtrage
// et libellés, testées sans widget.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/app_user.dart';
import '../../data/flight.dart';
import '../flight/flight_texts.dart';

/// Surlignage des vols à clôturer (orange des demandes).
final toCloseColor = statusColor(FlightStatus.demande);
const toCloseFill = Color(0xFFFFF3E0);

/// Vol affiché dans le panneau : validé, non supprimé, départ le jour même
/// ou avant (spec §5 : date ≤ aujourd'hui, clôturé ou non).
bool isPerformed(Flight f, DateTime now) =>
    !f.deleted &&
    f.status == FlightStatus.valide &&
    !dayOf(f.start).isAfter(dayOf(now));

/// Vol effectué non clôturé : même règle que l'action « Clôturer »
/// (décision 6 : la date seule compte, pas l'heure).
bool needsClosing(Flight f, DateTime now) => isPerformed(f, now) && !f.isClosed;

/// Décision 1 : instructeurs et admins voient tout ; les autres, les vols
/// dont ils sont membres de l'équipage.
bool visibleTo(Flight f, AppUser me) =>
    me.isAdmin || me.isInstructor || f.crew.contains(me.uid);

/// Vols effectués visibles par [me], sur [aircraftId] si donné, du plus
/// récent au plus ancien.
List<Flight> performedList(
  Iterable<Flight> flights, {
  required AppUser me,
  required DateTime now,
  String? aircraftId,
}) =>
    flights
        .where((f) =>
            isPerformed(f, now) &&
            visibleTo(f, me) &&
            (aircraftId == null || f.aircraftId == aircraftId))
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));

/// Mention à droite de chaque vol du panneau.
String performedLabel(Flight f, DateTime now) => f.isClosed
    ? 'Clôturé · ${formatDurationHm(f.actualFlightMinutes ?? 0)}'
    : 'À clôturer';

String toCloseCountText(int n) => n == 1 ? '1 vol à clôturer' : '$n vols à clôturer';
```

- [ ] **Step 4 : relancer, le test doit passer**

Run: `fvm flutter test test/features/performed/performed_test.dart`
Expected : PASS.

- [ ] **Step 5 : commit**

```bash
git add lib/features/performed/performed.dart test/features/performed/performed_test.dart
git commit -m "feat(app): performed flights filtering rules"
```

---

### Task 3 : clôture dès le jour du vol (serveur et app)

**Files:**
- Create: `functions/src/rules/club-day.ts`
- Test: `functions/src/rules/club-day.test.ts`
- Modify: `functions/src/flights/close.ts` (condition de date)
- Modify: `functions/src/flights/close.int.test.ts` (nouveau cas « plus tard
  dans la journée »)
- Modify: `lib/features/flight/flight_actions.dart`
- Modify: `test/features/flight/flight_actions_test.dart`

**Interfaces:**
- Consumes : `needsClosing` (Task 2).
- Produces :
  - `export const CLUB_UTC_OFFSET_MS = 3_600_000` (Africa/Libreville, UTC+1
    fixe)
  - `export function clubDay(ms: number): number` : numéro du jour à l'heure
    du club
  - `export function isOnOrBeforeClubToday(startMs: number, nowMs: number): boolean`
  - `flightActions` : `FlightAction.close` quand le vol est validé, non
    clôturé, du jour ou d'avant (`needsClosing`), pour un membre de
    l'équipage ou un admin. Avant l'heure de départ, cette action s'ajoute à
    celles d'avant départ.

- [ ] **Step 1 : tests unitaires serveur qui échouent**

`functions/src/rules/club-day.test.ts` :

```ts
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { clubDay, isOnOrBeforeClubToday } from "./club-day";

const utc = (iso: string) => Date.parse(iso);

test("clubDay : minuit à Libreville = 23:00 UTC la veille", () => {
  assert.equal(clubDay(utc("2026-10-14T23:00:00Z")), clubDay(utc("2026-10-15T12:00:00Z")));
  assert.equal(clubDay(utc("2026-10-14T22:59:59Z")) + 1, clubDay(utc("2026-10-15T12:00:00Z")));
});

test("isOnOrBeforeClubToday : plus tard le même jour → oui", () => {
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-15T21:30:00Z"), utc("2026-10-15T07:00:00Z")), true);
});

test("isOnOrBeforeClubToday : jour passé → oui ; lendemain → non", () => {
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-10T09:00:00Z"), utc("2026-10-15T07:00:00Z")), true);
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-16T08:00:00Z"), utc("2026-10-15T07:00:00Z")), false);
});

test("isOnOrBeforeClubToday : 23:30 UTC est déjà le lendemain au club", () => {
  // now = 15/10 22:00 UTC (23:00 au club) ; start = 15/10 23:30 UTC (16/10 00:30 au club).
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-15T23:30:00Z"), utc("2026-10-15T22:00:00Z")), false);
});
```

Run: `cd functions && npm test`
Expected : échec, module `./club-day` introuvable.

- [ ] **Step 2 : module pur**

`functions/src/rules/club-day.ts` :

```ts
// Jour calendaire à l'heure du club (Africa/Libreville, UTC+1 sans heure
// d'été, comme AppGAP). Module pur, sans Firestore.
export const CLUB_UTC_OFFSET_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** Numéro du jour (depuis l'époque) à l'heure du club. */
export function clubDay(ms: number): number {
  return Math.floor((ms + CLUB_UTC_OFFSET_MS) / DAY_MS);
}

/** Décision 6 (plan 4) : un vol se clôture dès son jour, sans condition d'heure. */
export function isOnOrBeforeClubToday(startMs: number, nowMs: number): boolean {
  return clubDay(startMs) <= clubDay(nowMs);
}
```

Run: `cd functions && npm test`
Expected : PASS.

- [ ] **Step 3 : test d'intégration qui échoue**

Dans `functions/src/flights/close.int.test.ts`, importer
`import { CLUB_UTC_OFFSET_MS, clubDay } from "../rules/club-day";`, puis
ajouter après le test « avant le départ : failed-precondition » (qui reste
tel quel : `at(10)` est après-demain, donc toujours refusé) :

```ts
test("vol du jour pas encore parti : clôture acceptée (décision 6)", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  // Dernière seconde du jour au club : toujours aujourd'hui, et dans le
  // futur sauf pendant cette seconde-là.
  const endOfClubDay = (clubDay(Date.now()) + 1) * 86_400_000 - CLUB_UTC_OFFSET_MS - 1000;
  const id = await seedFlight({
    start: endOfClubDay - 60 * 60_000, end: endOfClubDay, crew: [pilot.uid], aircraftId: a,
    status: "valide", pricingMode: "standard",
  });
  const r = await closeFlight(pilot, { flightId: id, actualMinutes: 60 });
  assert.equal(r.billedTo, "account");
});
```

Run: `cd functions && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`
Expected : ce test échoue avec « Le vol n'a pas encore eu lieu. », sauf si
on le lance moins d'une heure avant minuit au club.

- [ ] **Step 4 : condition de date dans `closeFlight`**

Dans `functions/src/flights/close.ts`, importer
`import { isOnOrBeforeClubToday } from "../rules/club-day";` et remplacer :

```ts
    if ((f.get("start") as FirebaseFirestore.Timestamp).toMillis() > now) {
```

par :

```ts
    if (!isOnOrBeforeClubToday((f.get("start") as FirebaseFirestore.Timestamp).toMillis(), now)) {
```

Le message « Le vol n'a pas encore eu lieu. » ne change pas.

Run: `cd functions && npm test && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`
Expected : PASS.

- [ ] **Step 5 : tests Dart de `flightActions` qui échouent**

Dans `test/features/flight/flight_actions_test.dart` (`now` = 12/10/2026
08:00), remplacer le test « vol validé, départ non passé : pas de clôture
même pour l'équipage » par :

```dart
  test('vol validé du jour, départ non passé : clôturer en plus de modifier et annuler', () {
    final today = testFlight(start: DateTime(2026, 10, 12, 15), crew: ['u1'], createdBy: 'u1');
    expect(flightActions(today, testUser(uid: 'u1'), now),
        {FlightAction.edit, FlightAction.cancel, FlightAction.close});
    expect(flightActions(today, testUser(uid: 'x'), now), isEmpty);
  });

  test('vol validé de demain : pas de clôture même pour l\'équipage', () {
    final tomorrow = testFlight(start: DateTime(2026, 10, 13, 9), crew: ['u1'], createdBy: 'u1');
    expect(flightActions(tomorrow, testUser(uid: 'u1'), now).contains(FlightAction.close), isFalse);
  });

  test('demande du jour pas encore partie : pas de clôture', () {
    final req = testFlight(
        start: DateTime(2026, 10, 12, 15), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    expect(flightActions(req, testUser(uid: 'ins', profile: 'instructeur'), now),
        {FlightAction.validate, FlightAction.refuse, FlightAction.cancel});
  });
```

Run: `fvm flutter test test/features/flight/flight_actions_test.dart`
Expected : FAIL sur le premier test (`close` absent).

- [ ] **Step 6 : `flightActions`**

Dans `lib/features/flight/flight_actions.dart`, importer
`import '../performed/performed.dart';`, compléter le commentaire de tête
(« Plan 4, décision 6 : la clôture est permise dès le jour du vol, même
avant l'heure de départ, en plus des actions d'avant départ. ») et
remplacer le corps après `if (f.isClosed) return admin;` par :

```dart
  final member = f.crew.contains(me.uid) || me.isAdmin;
  final close = <FlightAction>{
    if (member && needsClosing(f, now)) FlightAction.close,
  };
  if (!f.start.isAfter(now)) return {...close, ...admin};
  final reviewer = me.isAdmin || f.instructorUid == me.uid;
  final creator = f.createdBy == me.uid;
  return {
    if (f.status == FlightStatus.demande && reviewer) ...{
      FlightAction.validate,
      FlightAction.refuse,
    },
    if (creator) FlightAction.edit,
    if (creator || reviewer) FlightAction.cancel,
    ...close,
    ...admin,
  };
```

`needsClosing` exige déjà un vol validé, non supprimé, non clôturé.

- [ ] **Step 7 : suites Dart complètes**

Run: `fvm flutter test && fvm flutter analyze`
Expected : PASS, « No issues found! ». Si un test de `flight_screen_test.dart`
monte un vol validé du jour avant son départ et compte exactement les
boutons, ajouter « Clôturer » à l'attendu : c'est le nouveau comportement.

- [ ] **Step 8 : déployer en dev et commit**

```bash
cd functions && npm run build && npx firebase deploy --only functions:closeFlight --project dev
cd .. && git add functions/src/rules/club-day.ts functions/src/rules/club-day.test.ts \
  functions/src/flights/close.ts functions/src/flights/close.int.test.ts \
  lib/features/flight/flight_actions.dart test/features/flight/flight_actions_test.dart
git commit -m "feat: close a flight from its day on, before departure time"
```

---

### Task 4 : widget commun de période, repris par le relevé

**Files:**
- Create: `lib/core/period_bar.dart`
- Modify: `lib/features/admin/billing_report_screen.dart` (remplacer
  `_pickFrom`, `_pickTo` et la `Row` des deux `OutlinedButton` par
  `PeriodBar`)
- Test: `test/core/period_bar_test.dart`

**Interfaces:**
- Consumes : `formatDay` (`lib/core/formats.dart`).
- Produces :

```dart
class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.from,      // premier jour inclus (minuit)
    required this.to,        // exclusif : lendemain du dernier jour inclus
    required this.onChanged, // (from, to) avec la même convention
    this.lastDay,            // dernier jour sélectionnable, défaut 31/12/2100
    this.enabled = true,
  });
}
```

Boutons : `Key('period-from')` avec le texte « Du <formatDay(from)> », et
`Key('period-to')` avec « Au <formatDay(dernier jour inclus)> ». Même
convention `[from, to[` que `FinanceApi.watchFlightsBetween`.

- [ ] **Step 1 : écrire le test qui échoue**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/formats.dart';
import 'package:ulmgap/core/period_bar.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, {bool enabled = true}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PeriodBar(
            from: DateTime(2026, 10, 1),
            to: DateTime(2026, 11, 1),
            enabled: enabled,
            onChanged: (_, __) {},
          ),
        ),
      ));

  testWidgets('affiche le premier et le dernier jour inclus', (tester) async {
    await pumpBar(tester);
    expect(find.text('Du ${formatDay(DateTime(2026, 10, 1))}'), findsOneWidget);
    expect(find.text('Au ${formatDay(DateTime(2026, 10, 31))}'), findsOneWidget);
  });

  testWidgets('choisir « Du » renvoie le jour choisi, « to » inchangé', (tester) async {
    List<DateTime>? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PeriodBar(
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 11, 1),
          onChanged: (f, t) => changed = [f, t],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('period-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(changed, [DateTime(2026, 10, 10), DateTime(2026, 11, 1)]);
  });

  testWidgets('choisir « Au » renvoie le lendemain du jour choisi', (tester) async {
    List<DateTime>? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PeriodBar(
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 11, 1),
          onChanged: (f, t) => changed = [f, t],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('period-to')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(changed, [DateTime(2026, 10, 1), DateTime(2026, 10, 21)]);
  });

  testWidgets('désactivé : boutons inactifs', (tester) async {
    await pumpBar(tester, enabled: false);
    final from = tester.widget<OutlinedButton>(find.byKey(const Key('period-from')));
    final to = tester.widget<OutlinedButton>(find.byKey(const Key('period-to')));
    expect(from.onPressed, isNull);
    expect(to.onPressed, isNull);
  });
}
```

- [ ] **Step 2 : lancer le test, il doit échouer**

Run: `fvm flutter test test/core/period_bar_test.dart`
Expected : échec de compilation, `period_bar.dart` introuvable.

- [ ] **Step 3 : implémenter `PeriodBar`**

```dart
// Sélecteur de période « Du … / Au … » (relevé, vols effectués, compteurs).
// Bornes en [from, to[ : `to` est le lendemain du dernier jour inclus, comme
// FinanceApi.watchFlightsBetween.
import 'package:flutter/material.dart';

import 'formats.dart';

class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
    this.lastDay,
    this.enabled = true,
  });

  final DateTime from;
  final DateTime to;
  final void Function(DateTime from, DateTime to) onChanged;

  /// Dernier jour sélectionnable (défaut : 31/12/2100).
  final DateTime? lastDay;
  final bool enabled;

  DateTime get _lastIncludedDay => DateTime(to.year, to.month, to.day - 1);

  Future<void> _pickFrom(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from,
      firstDate: DateTime(2020),
      lastDate: _lastIncludedDay,
    );
    if (d != null) onChanged(DateTime(d.year, d.month, d.day), to);
  }

  Future<void> _pickTo(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _lastIncludedDay,
      firstDate: from,
      lastDate: lastDay ?? DateTime(2100, 12, 31),
    );
    if (d != null) onChanged(from, DateTime(d.year, d.month, d.day + 1));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('period-from'),
              onPressed: enabled ? () => _pickFrom(context) : null,
              child: Text('Du ${formatDay(from)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('period-to'),
              onPressed: enabled ? () => _pickTo(context) : null,
              child: Text('Au ${formatDay(_lastIncludedDay)}'),
            ),
          ),
        ]),
      );
}
```

- [ ] **Step 4 : relancer le test, il doit passer**

Run: `fvm flutter test test/core/period_bar_test.dart`
Expected : PASS.

- [ ] **Step 5 : faire utiliser `PeriodBar` par le relevé**

Dans `lib/features/admin/billing_report_screen.dart` :
- supprimer `_pickFrom` et `_pickTo` ;
- garder `_lastIncludedDay` (nom du fichier CSV) ;
- ajouter `import '../../core/period_bar.dart';` ;
- remplacer le `Padding(... Row(... OutlinedButton ...))` en tête de
  `Column` par :

```dart
          PeriodBar(
            from: _from,
            to: _to,
            onChanged: (f, t) => setState(() {
              _from = f;
              _to = t;
            }),
          ),
```

- [ ] **Step 6 : tests du relevé et analyse**

Run: `fvm flutter test test/features/admin/billing_report_screen_test.dart test/core/period_bar_test.dart && fvm flutter analyze`
Expected : PASS, « No issues found! ».

- [ ] **Step 7 : commit**

```bash
git add lib/core/period_bar.dart test/core/period_bar_test.dart lib/features/admin/billing_report_screen.dart
git commit -m "refactor(app): shared period picker, used by the billing report"
```

---

### Task 5 : écran « Vols effectués »

**Files:**
- Modify: `lib/data/finance_api.dart` (interface et implémentation
  Firebase : `watchValidUnclosedFlights`)
- Modify: `test/support/fakes.dart` (`FakeFinanceApi.watchValidUnclosedFlights`)
- Create: `lib/features/performed/performed_flight_tile.dart`
- Create: `lib/features/performed/performed_flights_screen.dart`
- Test: `test/features/performed/performed_flights_screen_test.dart`

**Interfaces:**
- Consumes : Task 2 (`needsClosing`, `performedList`, `performedLabel`,
  `toCloseCountText`, `toCloseColor`, `toCloseFill`), Task 4 (`PeriodBar`),
  `FinanceApi.watchFlightsBetween`, `FlightApi.watchDirectory`,
  `FlightApi.watchAircraft`, `crewText`, `formatDay`, `formatRange`,
  `asyncState`, `FlightScreen({required AppUser me, Flight? flight})`.
- Produces :
  - `Stream<List<Flight>> FinanceApi.watchValidUnclosedFlights()`
  - `PerformedFlightsScreen({required AppUser me, DateTime Function() now = DateTime.now, void Function(Flight)? onOpen})`.
    Sans `onOpen`, un appui pousse `FlightScreen(me: me, flight: f)`.
  - Clés : `Key('aircraft-filter')` (DropdownButton), `Key('only-to-close')`
    (FilterChip), `Key('to-close-count')` (Text), `Key('performed-<id>')`
    (ListTile de chaque vol).

- [ ] **Step 1 : ajouter la requête (interface, Firebase, fake)**

Dans `abstract class FinanceApi`, après `watchUnclosedFlightsPaidBy` :

```dart
  /// Vols validés non clôturés, passés comme à venir : les vols à clôturer
  /// de toute période (panneau « Vols effectués »). Égalités seules, sans
  /// index composite.
  Stream<List<Flight>> watchValidUnclosedFlights();
```

Dans `FirebaseFinanceApi` :

```dart
  @override
  Stream<List<Flight>> watchValidUnclosedFlights() => _flights
      .where('status', isEqualTo: 'valide')
      .where('isClosed', isEqualTo: false)
      .snapshots()
      .map((q) => q.docs.map((d) => Flight.fromMap(d.id, d.data())).toList());
```

Dans `FakeFinanceApi` (`test/support/fakes.dart`) :

```dart
  @override
  Stream<List<Flight>> watchValidUnclosedFlights() => Stream.value(
        flights.where((f) => f.status == FlightStatus.valide && !f.isClosed).toList(),
      );
```

- [ ] **Step 2 : écrire les tests d'écran qui échouent**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/performed/performed_flights_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 15, 12);

Widget host(AppUser me, List<Flight> flights, {void Function(Flight)? onOpen}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: FakeFinanceApi()..flights = flights,
      flights: FakeFlightApi()
        ..directory = [member('u1', 'DPS', 'instructeur'), member('u2', 'LDX', 'eleve')]
        ..aircraft = const [
          Aircraft(id: 'a1', registration: 'F-JABC', label: 'ULM 1', active: true),
          Aircraft(id: 'a2', registration: 'F-JXYZ', label: 'ULM 2', active: true),
        ],
      child: MaterialApp(
        home: PerformedFlightsScreen(me: me, now: () => now, onOpen: onOpen),
      ),
    );

Finder tileOf(String id) => find.byKey(Key('performed-$id'));

void main() {
  testWidgets('pilote : seulement ses vols validés, du jour ou passés, du mois', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'mine', start: DateTime(2026, 10, 10, 9), crew: ['u1', 'u2'],
          isClosed: true, actualFlightMinutes: 75),
      testFlight(id: 'not-mine', start: DateTime(2026, 10, 11, 9), crew: ['u1'],
          isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'refused', start: DateTime(2026, 10, 9, 9), crew: ['u2'], status: 'refuse'),
      testFlight(id: 'expired', start: DateTime(2026, 10, 8, 9), crew: ['u2'], status: 'demande'),
      testFlight(id: 'deleted', start: DateTime(2026, 10, 7, 9), crew: ['u2'], deleted: true),
      testFlight(id: 'tomorrow', start: DateTime(2026, 10, 16, 9), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('mine'), findsOneWidget);
    expect(find.text('Clôturé · 1 h 15'), findsOneWidget);
    for (final id in ['not-mine', 'refused', 'expired', 'deleted', 'tomorrow']) {
      expect(tileOf(id), findsNothing, reason: id);
    }
  });

  testWidgets('instructeur : voit aussi les vols des autres', (tester) async {
    final me = testUser(uid: 'u9', profile: 'instructeur');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'a', start: DateTime(2026, 10, 10, 9), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('a'), findsOneWidget);
  });

  testWidgets('vol du jour pas encore parti : à clôturer', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'later', start: DateTime(2026, 10, 15, 14), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('later'), findsOneWidget);
    expect(find.text('À clôturer'), findsOneWidget);
    expect(find.text('1 vol à clôturer'), findsOneWidget);
  });

  testWidgets('vol à clôturer hors période : compté, et visible avec « À clôturer seulement »',
      (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'this-month', start: DateTime(2026, 10, 12, 9), crew: ['u2']),
      testFlight(id: 'last-month', start: DateTime(2026, 9, 20, 9), crew: ['u2']),
      testFlight(id: 'closed', start: DateTime(2026, 10, 11, 9), crew: ['u2'],
          isClosed: true, actualFlightMinutes: 60),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('2 vols à clôturer'), findsOneWidget);
    expect(tileOf('this-month'), findsOneWidget);
    expect(tileOf('last-month'), findsNothing); // hors du mois en cours
    expect(tileOf('closed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('only-to-close')));
    await tester.pumpAndSettle();
    expect(tileOf('this-month'), findsOneWidget);
    expect(tileOf('last-month'), findsOneWidget);
    expect(tileOf('closed'), findsNothing);
    // Période désactivée tant que le filtre est coché.
    final from = tester.widget<OutlinedButton>(find.byKey(const Key('period-from')));
    expect(from.onPressed, isNull);
  });

  testWidgets('tri du plus récent au plus ancien', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'old', start: DateTime(2026, 10, 2, 9), crew: ['u2']),
      testFlight(id: 'recent', start: DateTime(2026, 10, 12, 9), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(tileOf('recent')).dy,
        lessThan(tester.getTopLeft(tileOf('old')).dy));
  });

  testWidgets('filtre appareil', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'on-a1', start: DateTime(2026, 10, 10, 9), crew: ['u2'], aircraftId: 'a1'),
      testFlight(id: 'on-a2', start: DateTime(2026, 10, 11, 9), crew: ['u2'],
          aircraftId: 'a2', aircraft: 'F-JXYZ'),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('on-a1'), findsOneWidget);
    expect(tileOf('on-a2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('aircraft-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ULM 2 (F-JXYZ)').last);
    await tester.pumpAndSettle();
    expect(tileOf('on-a1'), findsNothing);
    expect(tileOf('on-a2'), findsOneWidget);
  });

  testWidgets('un appui ouvre le vol', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    Flight? opened;
    await tester.pumpWidget(host(me, [
      testFlight(id: 'x', start: DateTime(2026, 10, 12, 9), crew: ['u2']),
    ], onOpen: (f) => opened = f));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('x'));
    expect(opened?.id, 'x');
  });

  testWidgets('aucun vol : message vide', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve'), []));
    await tester.pumpAndSettle();
    expect(find.text('Aucun vol effectué sur cette période.'), findsOneWidget);
  });
}
```

- [ ] **Step 3 : lancer les tests, ils doivent échouer**

Run: `fvm flutter test test/features/performed/performed_flights_screen_test.dart`
Expected : échec de compilation, `performed_flights_screen.dart` introuvable.

- [ ] **Step 4 : implémenter la tuile**

`lib/features/performed/performed_flight_tile.dart` :

```dart
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../flight/flight_texts.dart';
import 'performed.dart';

/// Une ligne du panneau « Vols effectués » ; surlignée en orange quand le
/// vol est à clôturer.
class PerformedFlightTile extends StatelessWidget {
  const PerformedFlightTile({
    super.key,
    required this.flight,
    required this.dir,
    required this.now,
    this.onTap,
  });

  final Flight flight;
  final Map<String, CrewMember> dir;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = flight;
    final toClose = needsClosing(f, now);
    final color = toClose
        ? toCloseColor
        : f.isClosed
            ? statusColor(FlightStatus.valide)
            : Colors.grey;
    final tile = ListTile(
      key: Key('performed-${f.id}'),
      onTap: onTap,
      title: Text('${formatDay(f.start)} · ${formatRange(f.start, f.end)}'),
      subtitle: Text('${f.aircraft} · ${crewText(f.crew, f.passengers, dir)} → ${f.destination}'),
      trailing: Text(
        performedLabel(f, now),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
    if (!toClose) return tile;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: toCloseFill,
        border: Border.all(color: toCloseColor, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: tile,
    );
  }
}
```

- [ ] **Step 5 : implémenter l'écran**

`lib/features/performed/performed_flights_screen.dart` :

```dart
// Panneau « Vols effectués » (spec §5, plan 4) : seul accès aux vols passés,
// donc à la clôture (l'action « Clôturer » est dans FlightScreen).
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../core/period_bar.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/finance_api.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_screen.dart';
import 'performed.dart';
import 'performed_flight_tile.dart';

class PerformedFlightsScreen extends StatefulWidget {
  const PerformedFlightsScreen({
    super.key,
    required this.me,
    this.now = DateTime.now,
    this.onOpen,
  });

  final AppUser me;
  final DateTime Function() now;

  /// Ouverture d'un vol ; par défaut, FlightScreen.
  final void Function(Flight flight)? onOpen;

  @override
  State<PerformedFlightsScreen> createState() => _PerformedFlightsScreenState();
}

class _PerformedFlightsScreenState extends State<PerformedFlightsScreen> {
  // [_to] est exclusif (comme FinanceApi.watchFlightsBetween).
  late DateTime _from;
  late DateTime _to;
  String? _aircraftId; // null : tous les appareils
  bool _onlyToClose = false;

  FinanceApi? _finance;
  Stream<List<Flight>>? _periodFlights;
  Stream<List<Flight>>? _unclosed;
  Stream<List<CrewMember>>? _dir;
  Stream<List<Aircraft>>? _aircraft;

  @override
  void initState() {
    super.initState();
    final n = widget.now();
    _from = DateTime(n.year, n.month);
    _to = DateTime(n.year, n.month, n.day + 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    final finance = services.finance!;
    if (!identical(_finance, finance)) {
      _finance = finance;
      _periodFlights = finance.watchFlightsBetween(_from, _to);
      _unclosed = finance.watchValidUnclosedFlights();
      _dir = services.flights!.watchDirectory();
      _aircraft = services.flights!.watchAircraft();
    }
  }

  void _setPeriod(DateTime from, DateTime to) => setState(() {
        _from = from;
        _to = to;
        _periodFlights = _finance!.watchFlightsBetween(from, to);
      });

  void _open(Flight f) {
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen(f);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlightScreen(me: widget.me, flight: f),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vols effectués')),
        body: StreamBuilder<List<CrewMember>>(
          stream: _dir,
          builder: (context, dirSnap) {
            final dir = {for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m};
            return StreamBuilder<List<Aircraft>>(
              stream: _aircraft,
              builder: (context, acSnap) => StreamBuilder<List<Flight>>(
                stream: _unclosed,
                builder: (context, unclosedSnap) => StreamBuilder<List<Flight>>(
                  stream: _periodFlights,
                  builder: (context, periodSnap) => _body(
                      dir, acSnap.data ?? const <Aircraft>[], unclosedSnap, periodSnap),
                ),
              ),
            );
          },
        ),
      );

  Widget _body(Map<String, CrewMember> dir, List<Aircraft> aircraft,
      AsyncSnapshot<List<Flight>> unclosedSnap, AsyncSnapshot<List<Flight>> periodSnap) {
    final now = widget.now();
    final me = widget.me;
    final toClose = performedList(unclosedSnap.data ?? const <Flight>[],
            me: me, now: now, aircraftId: _aircraftId)
        .where((f) => needsClosing(f, now))
        .toList();
    final shown = _onlyToClose
        ? toClose
        : performedList(periodSnap.data ?? const <Flight>[],
            me: me, now: now, aircraftId: _aircraftId);
    final state = asyncState(
      _onlyToClose ? unclosedSnap : periodSnap,
      isEmpty: shown.isEmpty,
      empty: _onlyToClose ? 'Aucun vol à clôturer.' : 'Aucun vol effectué sur cette période.',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeriodBar(
          from: _from,
          to: _to,
          lastDay: dayOf(now),
          enabled: !_onlyToClose,
          onChanged: _setPeriod,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String?>(
                key: const Key('aircraft-filter'),
                // Appareil disparu de la liste : retour à « Tous » plutôt
                // qu'une assertion de DropdownButton.
                value: aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : null,
                onChanged: (v) => setState(() => _aircraftId = v),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tous les appareils')),
                  for (final a in aircraft)
                    DropdownMenuItem<String?>(
                        value: a.id, child: Text('${a.label} (${a.registration})')),
                ],
              ),
              FilterChip(
                key: const Key('only-to-close'),
                label: const Text('À clôturer seulement'),
                selected: _onlyToClose,
                onSelected: (v) => setState(() => _onlyToClose = v),
              ),
            ],
          ),
        ),
        if (toClose.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              toCloseCountText(toClose.length),
              key: const Key('to-close-count'),
              style: TextStyle(color: toCloseColor, fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: state ??
              ListView(children: [
                for (final f in shown)
                  PerformedFlightTile(flight: f, dir: dir, now: now, onTap: () => _open(f)),
              ]),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6 : relancer les tests, ils doivent passer**

Run: `fvm flutter test test/features/performed/ && fvm flutter analyze`
Expected : PASS, « No issues found! ».

- [ ] **Step 7 : commit**

```bash
git add lib/data/finance_api.dart test/support/fakes.dart lib/features/performed/ test/features/performed/
git commit -m "feat(app): performed flights panel, entry point to closing"
```

---

### Task 6 : écran « Compteurs » (onglets Pilote et Appareil)

**Files:**
- Create: `lib/features/counters/counters_screen.dart`
- Test: `test/features/counters/counters_screen_test.dart`

**Interfaces:**
- Consumes : Task 1 (`pilotMinutes`, `aircraftMinutes`), Task 4
  (`PeriodBar`), `FinanceApi.watchFlightsBetween`, `FlightApi.watchDirectory`,
  `FlightApi.watchAircraft`, `formatDurationHm`, `connectionErrorMessage`.
- Produces : `CountersScreen({required AppUser me, DateTime Function() now = DateTime.now})`.
  Clés : `Key('pilot-select')` (DropdownButton, instructeurs et admins
  seulement), `Key('pilot-total')`, `Key('aircraft-select')`,
  `Key('aircraft-total')`. Texte des totaux : « Total : <formatDurationHm> ».

- [ ] **Step 1 : écrire les tests qui échouent**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/crew_member.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/counters/counters_screen.dart';

import '../../support/fakes.dart';

Widget host(AppUser me, List<Flight> flights, {List<CrewMember>? directory}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: FakeFinanceApi()..flights = flights,
      flights: FakeFlightApi()
        ..directory = directory ??
            [member('u1', 'DPS', 'instructeur'), member('u2', 'LDX', 'eleve')]
        ..aircraft = const [
          Aircraft(id: 'a0', registration: 'F-JOLD', label: 'ULM 0', active: false),
          Aircraft(id: 'a1', registration: 'F-JABC', label: 'ULM 1', active: true),
          Aircraft(id: 'a2', registration: 'F-JXYZ', label: 'ULM 2', active: true),
        ],
      child: MaterialApp(home: CountersScreen(me: me, now: () => DateTime(2026, 10, 15, 12))),
    );

String total(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

final flights = [
  testFlight(id: 'a', start: DateTime(2026, 3, 1, 9), crew: ['u1', 'u2'], aircraftId: 'a1',
      isClosed: true, actualFlightMinutes: 75),
  testFlight(id: 'b', start: DateTime(2026, 9, 1, 9), crew: ['u2'], aircraftId: 'a2',
      isClosed: true, actualFlightMinutes: 60),
  testFlight(id: 'c', start: DateTime(2026, 9, 2, 9), crew: ['u1'], aircraftId: 'a1',
      isClosed: true, actualFlightMinutes: 50),
  testFlight(id: 'unclosed', start: DateTime(2026, 9, 3, 9), crew: ['u2'], aircraftId: 'a1'),
  testFlight(id: 'deleted', start: DateTime(2026, 9, 4, 9), crew: ['u2'], aircraftId: 'a1',
      isClosed: true, deleted: true, actualFlightMinutes: 600),
  testFlight(id: 'last-year', start: DateTime(2025, 12, 31, 9), crew: ['u2'], aircraftId: 'a1',
      isClosed: true, actualFlightMinutes: 600),
];

void main() {
  testWidgets('élève : son total de l\'année, sans choix du pilote', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve', shortName: 'LDX'), flights));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pilot-select')), findsNothing);
    expect(total(tester, 'pilot-total'), 'Total : 2 h 15'); // 75 + 60
  });

  testWidgets('instructeur : choisit le pilote, lui-même par défaut', (tester) async {
    await tester.pumpWidget(
        host(testUser(uid: 'u1', profile: 'instructeur', shortName: 'DPS'), flights));
    await tester.pumpAndSettle();
    expect(total(tester, 'pilot-total'), 'Total : 2 h 05'); // 75 + 50

    await tester.tap(find.byKey(const Key('pilot-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LDX · Nom LDX').last);
    await tester.pumpAndSettle();
    expect(total(tester, 'pilot-total'), 'Total : 2 h 15');
  });

  testWidgets('appareil : premier actif par défaut, puis au choix', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve'), flights));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareil'));
    await tester.pumpAndSettle();
    expect(find.text('ULM 1 (F-JABC)'), findsOneWidget);
    expect(total(tester, 'aircraft-total'), 'Total : 2 h 05'); // a : 75 + c : 50

    await tester.tap(find.byKey(const Key('aircraft-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ULM 2 (F-JXYZ)').last);
    await tester.pumpAndSettle();
    expect(total(tester, 'aircraft-total'), 'Total : 1 h 00');
  });

  testWidgets('période : année en cours par défaut', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve'), flights));
    await tester.pumpAndSettle();
    expect(find.textContaining('Du jeudi 1 janvier'), findsOneWidget);
    expect(find.textContaining('Au jeudi 31 décembre'), findsOneWidget);
  });

  testWidgets('annuaire vide : pas de plantage, total du compte connecté', (tester) async {
    await tester.pumpWidget(host(
        testUser(uid: 'u1', profile: 'instructeur'), flights, directory: const []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(total(tester, 'pilot-total'), 'Total : 2 h 05');
  });
}
```

Note : le 1er janvier 2026 et le 31 décembre 2026 sont des jeudis.

- [ ] **Step 2 : lancer les tests, ils doivent échouer**

Run: `fvm flutter test test/features/counters/counters_screen_test.dart`
Expected : échec de compilation, `counters_screen.dart` introuvable.

- [ ] **Step 3 : implémenter l'écran**

```dart
// Écran « Compteurs » (spec §5) : total d'heures d'un pilote ou d'un
// appareil sur une période (année en cours par défaut, commune aux deux
// onglets). Base : vols clôturés non supprimés (counters.dart).
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/period_bar.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/finance_api.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_texts.dart';
import 'counters.dart';

class CountersScreen extends StatefulWidget {
  const CountersScreen({super.key, required this.me, this.now = DateTime.now});
  final AppUser me;
  final DateTime Function() now;

  @override
  State<CountersScreen> createState() => _CountersScreenState();
}

class _CountersScreenState extends State<CountersScreen> {
  // [_to] est exclusif (comme FinanceApi.watchFlightsBetween).
  late DateTime _from;
  late DateTime _to;
  late String _pilotUid;
  String? _aircraftId; // null : premier appareil actif

  FinanceApi? _finance;
  Stream<List<Flight>>? _flights;
  Stream<List<CrewMember>>? _dir;
  Stream<List<Aircraft>>? _aircraft;

  bool get _canChoosePilot => widget.me.isAdmin || widget.me.isInstructor;

  @override
  void initState() {
    super.initState();
    final n = widget.now();
    _from = DateTime(n.year);
    _to = DateTime(n.year + 1);
    _pilotUid = widget.me.uid;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    final finance = services.finance!;
    if (!identical(_finance, finance)) {
      _finance = finance;
      _flights = finance.watchFlightsBetween(_from, _to);
      _dir = services.flights!.watchDirectory();
      _aircraft = services.flights!.watchAircraft();
    }
  }

  void _setPeriod(DateTime from, DateTime to) => setState(() {
        _from = from;
        _to = to;
        _flights = _finance!.watchFlightsBetween(from, to);
      });

  Widget _total(String key, int minutes) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Total : ${formatDurationHm(minutes)}',
          key: Key(key),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Compteurs'),
            bottom: const TabBar(tabs: [Tab(text: 'Pilote'), Tab(text: 'Appareil')]),
          ),
          body: Column(children: [
            PeriodBar(from: _from, to: _to, onChanged: _setPeriod),
            Expanded(
              child: StreamBuilder<List<Flight>>(
                stream: _flights,
                builder: (context, snap) {
                  if (snap.hasError) return connectionErrorMessage();
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final flights = snap.data!;
                  return TabBarView(children: [_pilotTab(flights), _aircraftTab(flights)]);
                },
              ),
            ),
          ]),
        ),
      );

  Widget _pilotTab(List<Flight> flights) => StreamBuilder<List<CrewMember>>(
        stream: _dir,
        builder: (context, snap) {
          final dir = snap.data ?? const <CrewMember>[];
          final selector = !_canChoosePilot
              ? Text('Pilote : ${widget.me.shortName}')
              : DropdownButton<String>(
                  key: const Key('pilot-select'),
                  // Annuaire pas encore chargé (ou sans ce compte) : pas de
                  // valeur plutôt qu'une assertion de DropdownButton.
                  value: dir.any((m) => m.uid == _pilotUid) ? _pilotUid : null,
                  hint: Text(widget.me.shortName),
                  onChanged: (v) => setState(() => _pilotUid = v ?? _pilotUid),
                  items: [
                    for (final m in dir)
                      DropdownMenuItem(value: m.uid, child: Text('${m.shortName} · ${m.displayName}')),
                  ],
                );
          return ListView(padding: const EdgeInsets.all(16), children: [
            selector,
            _total('pilot-total', pilotMinutes(flights, _pilotUid)),
          ]);
        },
      );

  Widget _aircraftTab(List<Flight> flights) => StreamBuilder<List<Aircraft>>(
        stream: _aircraft,
        builder: (context, snap) {
          final aircraft = snap.data ?? const <Aircraft>[];
          if (snap.hasData && aircraft.isEmpty) {
            return const Center(child: Text('Aucun appareil.'));
          }
          String? fallback() {
            for (final a in aircraft) {
              if (a.active) return a.id;
            }
            return aircraft.isEmpty ? null : aircraft.first.id;
          }

          final selected =
              aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : fallback();
          return ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButton<String>(
              key: const Key('aircraft-select'),
              value: selected,
              onChanged: (v) => setState(() => _aircraftId = v),
              items: [
                for (final a in aircraft)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.label} (${a.registration})${a.active ? '' : ' (inactif)'}'),
                  ),
              ],
            ),
            if (selected != null) _total('aircraft-total', aircraftMinutes(flights, selected)),
          ]);
        },
      );
}
```

- [ ] **Step 4 : relancer les tests, ils doivent passer**

Run: `fvm flutter test test/features/counters/ && fvm flutter analyze`
Expected : PASS, « No issues found! ».

- [ ] **Step 5 : commit**

```bash
git add lib/features/counters/counters_screen.dart test/features/counters/counters_screen_test.dart
git commit -m "feat(app): pilot and aircraft counters screen"
```

---

### Task 7 : accès depuis l'accueil, déconnexion dans « Mon compte », docs

**Files:**
- Modify: `lib/features/home/home_shell.dart`
- Modify: `lib/features/account/account_screen.dart`
- Modify: `test/features/home/home_shell_test.dart`
- Modify: `test/features/account/account_screen_test.dart`
- Modify: `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md` (§5)
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes : `PerformedFlightsScreen({required AppUser me})` (Task 5),
  `CountersScreen({required AppUser me})` (Task 6),
  `AppServices.of(context).auth.signOut`.
- Produces : dans la barre d'accueil, les icônes « Vols effectués »
  (`Icons.history`) et « Compteurs » (`Icons.timer`), placées avant
  « Mon compte ». L'icône « Se déconnecter » (`Icons.logout`) passe dans la
  barre de `AccountScreen`.

- [ ] **Step 1 : écrire les tests qui échouent**

Dans `test/features/home/home_shell_test.dart`, ajouter les imports de
`PerformedFlightsScreen` et `CountersScreen`, puis :

```dart
  testWidgets('icône Vols effectués : visible pour tous, ouvre le panneau', (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    await tester.tap(find.byTooltip('Vols effectués'));
    await tester.pumpAndSettle();
    expect(find.byType(PerformedFlightsScreen), findsOneWidget);
  });

  testWidgets('icône Compteurs : visible pour tous, ouvre CountersScreen', (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    await tester.tap(find.byTooltip('Compteurs'));
    await tester.pumpAndSettle();
    expect(find.byType(CountersScreen), findsOneWidget);
  });

  testWidgets('plus de « Se déconnecter » dans la barre d\'accueil', (tester) async {
    await tester.pumpWidget(host(testUser(isAdmin: true)));
    await tester.pump();
    expect(find.byTooltip('Se déconnecter'), findsNothing);
  });

  testWidgets('admin sur 360 px de large : pas de débordement, 5 icônes accessibles',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(testUser(profile: 'instructeur', isAdmin: true)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final t in ['Vols effectués', 'Compteurs', 'Mon compte', 'Instructeurs', 'Administration']) {
      expect(find.byTooltip(t).hitTestable(), findsOneWidget, reason: t);
    }
  });
```

Dans `test/features/account/account_screen_test.dart` (le test monte son
propre `AppServices`, avec une route racine sous `AccountScreen`) :

```dart
  testWidgets('Se déconnecter : revient à la racine puis déconnecte', (tester) async {
    final auth = FakeAuthService();
    final me = _user(balance: 0);
    await tester.pumpWidget(AppServices(
      auth: auth,
      users: FakeUserRepository(),
      finance: FakeFinanceApi(),
      flights: FakeFlightApi(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AccountScreen(me: me)),
            ),
            child: const Text('racine'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('racine'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(auth.calls, contains('signOut'));
    expect(find.byType(AccountScreen), findsNothing);
  });
```


- [ ] **Step 2 : lancer les tests, ils doivent échouer**

Run: `fvm flutter test test/features/home/home_shell_test.dart test/features/account/account_screen_test.dart`
Expected : FAIL. Les tooltips « Vols effectués » et « Compteurs » sont
introuvables, « Se déconnecter » est encore présent sur l'accueil et absent
de « Mon compte ».

- [ ] **Step 3 : implémenter**

`lib/features/home/home_shell.dart` :
- ajouter `import '../counters/counters_screen.dart';` et
  `import '../performed/performed_flights_screen.dart';` ;
- insérer, juste avant l'`IconButton` « Mon compte » :

```dart
          IconButton(
            tooltip: 'Vols effectués',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PerformedFlightsScreen(me: user),
            )),
          ),
          IconButton(
            tooltip: 'Compteurs',
            icon: const Icon(Icons.timer),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CountersScreen(me: user),
            )),
          ),
```

- supprimer l'`IconButton` « Se déconnecter » (et l'import de `services.dart`
  s'il ne sert plus : l'analyseur le signalera).

`lib/features/account/account_screen.dart`, dans l'`AppBar` :

```dart
      appBar: AppBar(
        title: const Text('Mon compte'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Service lu avant de démonter l'écran ; retour à la racine
              // d'abord, sinon cet écran resterait empilé au-dessus de
              // l'écran de connexion.
              final auth = AppServices.of(context).auth;
              Navigator.of(context).popUntil((r) => r.isFirst);
              auth.signOut();
            },
          ),
        ],
      ),
```

- [ ] **Step 4 : relancer toute la suite**

Run: `fvm flutter test && fvm flutter analyze`
Expected : tous les tests passent, « No issues found! ».

- [ ] **Step 5 : mettre à jour la spec (§5)**

Dans `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, section
**Vols effectués**, remplacer la puce « À préciser au plan 4 : … » par :

```markdown
- Précisions du plan 4 (2026-09-30) :
  - un pilote voit les vols dont il est membre de l'équipage ; les
    instructeurs et les admins voient tout ;
  - seuls les vols validés et non supprimés apparaissent, du plus récent au
    plus ancien ;
  - filtres : période (mois en cours par défaut), appareil, « À clôturer
    seulement » ;
  - les vols à clôturer (date du jour ou avant, non clôturés, sans
    condition d'heure) sont surlignés en orange ; la clôture est permise dès
    le jour du vol, à l'heure du club (Africa/Libreville). Le compteur « N vols à clôturer » et le filtre portent sur toutes
    les périodes.
```

Section **Compteurs**, ajouter :

```markdown
- Chaque membre de `crew` cumule les minutes du vol (instructeur et élève) ;
  les passagers sans compte ne comptent pas.
- Période par défaut : l'année civile en cours. Accès par l'icône
  « Compteurs » de l'accueil, avec deux onglets, « Pilote » et « Appareil ».
```

Section **Mon compte**, ajouter : `- Bouton « Se déconnecter » (retiré de la
barre d'accueil au plan 4).`

- [ ] **Step 6 : mettre à jour `CLAUDE.md`**

- Liste « Documents de référence » : ajouter
  `- Plan 4, compteurs et vols effectués (terminé) : docs/superpowers/plans/2026-09-30-ulmgap-04-compteurs.md`.
- « État au … » : dater du jour. Plans 1 à 4 terminés ; le plan 4 est sur
  `feature/compteurs`, créée depuis `feature/finances` (aucune des deux
  n'est fusionnée). En dev, `closeFlight` est déployée avec la clôture dès le
  jour du vol. **En prod : redéployer les Functions** (`closeFlight`) avec
  celles du plan 3 ; ni règle ni index nouveau.
- « À reprendre aux plans suivants » : supprimer la puce « Plan 4
  (compteurs) … », désormais faite ; garder la puce du plan 5 telle quelle.

- [ ] **Step 7 : commit**

```bash
git add lib/features/home/home_shell.dart lib/features/account/account_screen.dart \
  test/features/home/home_shell_test.dart test/features/account/account_screen_test.dart \
  docs/superpowers/specs/2026-09-25-ulmgap-app-design.md CLAUDE.md
git commit -m "feat(app): home access to performed flights and counters, sign-out in account"
```

---

## Recette en dev (après le plan, par l'utilisateur)

- Web ou Android dev : ouvrir « Vols effectués » avec un compte élève puis
  avec DPS. Vérifier la visibilité, le compteur « à clôturer », puis clôturer
  un vol depuis le panneau.
- La première requête `status == valide && isClosed == false` ne doit pas
  demander d'index. Si la console affiche un lien de création d'index,
  signaler l'erreur au lieu de créer l'index.
- « Compteurs » : comparer le total d'un appareil au relevé des vols facturés
  sur la même période.
- Se déconnecter depuis « Mon compte ».
