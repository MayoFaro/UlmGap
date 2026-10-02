# UlmGap, plan 7 : suivi carburant par appareil

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** à la clôture, l'équipage déclare le carburant au départ (confirmé
ou corrigé), le carburant ajouté et le carburant à bord une fois l'appareil
rangé ; l'app affiche le carburant actuel de chaque appareil et un écran
« Suivi carburant » avec une consommation estimée.

**Architecture :** comme aux plans 3 et 4b.
- Toute écriture passe par `closeFlight` et `adminUpdateFlight` ; le
  carburant actuel est recopié sur `aircraft/{id}` dans la même transaction.
- La règle « ce vol devient-il la source du carburant de l'appareil ? » est
  une fonction pure de `functions/src/rules/fuel.ts`.
- Côté app, contrôles de saisie et calcul de consommation dans
  `lib/core/fuel.dart` (pur, testé) ; nouvel écran
  `lib/features/fuel/fuel_log_screen.dart`.

**Tech Stack :** inchangée (Flutter 3.32.8 via fvm, Functions TypeScript
Node 22, `node:test`, émulateurs Firestore/Auth).

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §9
(et §2.3, §2.5, §3.3, §5). Déjà à jour (commit `8f5e230`).

**Branche :** `feature/carburant`, créée depuis `main`.

## Global Constraints

- Toujours `fvm flutter` / `fvm dart`, jamais `flutter` nu.
- Valeurs carburant : **litres entiers de 0 à 100** ; mêmes messages côté app
  et côté serveur :
  - `Carburant prévu invalide (0 à 100 L).`
  - `Carburant au départ invalide (0 à 100 L).`
  - `Carburant ajouté invalide (0 à 100 L).`
  - `Carburant rangé invalide (0 à 100 L).`
- Le serveur ne calcule **rien** entre les valeurs carburant ; seule la
  consommation estimée de l'écran « Suivi carburant » est calculée (dans
  l'app).
- Aucune nouvelle règle Firestore, aucun nouvel index, aucun champ du contrat
  du pont modifié.
- Textes de l'interface en français.
- TDD : chaque étape commence par un test qui échoue.
- Ne jamais déployer en prod. Déploiement dev des Functions autorisé à la
  dernière tâche.
- Tests : `fvm flutter test && fvm flutter analyze` ; `cd functions && npm
  test` ; intégration : `cd functions && JAVA_HOME=/opt/android-studio/jbr
  PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`.

## Review Focus

1. **Clôture tardive** : un vol de lundi clôturé après celui de mardi ne doit
   pas remplacer le carburant de l'appareil (Task 2, test « clôture tardive »).
2. **Appareil au carburant inconnu** : la case « non conforme » disparaît, le
   champ « Carburant au départ » est obligatoire (Task 5, test « inconnu »).
3. **Case cochée puis décochée** : le départ envoyé redevient la valeur prévue,
   pas la valeur tapée entre-temps (Task 5, test « décochée »).
4. **Fiche appareil modifiée par un admin** : `adminUpsertAircraft` ne doit
   pas effacer `fuelLiters` (Task 2, test « upsert conserve le carburant »).
5. **Consommation** : vols anciens sans carburant, vols supprimés ou non
   clôturés exclus ; masquée sans vol utile (Task 4, tests `fuelStats`).

---

### Task 1 : validation carburant et règle de source (serveur, pur)

**Files:**
- Create: `functions/src/rules/fuel.ts`
- Create: `functions/src/rules/fuel.test.ts`
- Modify: `functions/src/flights/validation.ts` (`validateClosing`,
  `AdminUpdate`, `validateAdminUpdate`)
- Test: `functions/src/flights/validation.test.ts`

**Interfaces:**
- Produces:
  - `MAX_FUEL_LITERS = 100` (exporté de `validation.ts`)
  - `validateClosing(data)` rend en plus `fuelStartExpected: number | null`,
    `fuelStart: number`, `fuelAdded: number`, `fuelEnd: number`
  - `AdminUpdate` gagne `fuelStart?: number`, `fuelAdded?: number`,
    `fuelEnd?: number`
  - `becomesFuelSource(flightStartMs: number, sourceStartMs: number | null): boolean`

- [ ] **Step 1 : tests de la règle pure** (`functions/src/rules/fuel.test.ts`)

```ts
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { becomesFuelSource } from "./fuel";

test("becomesFuelSource : appareil sans valeur, vol plus récent ou simultané", () => {
  assert.equal(becomesFuelSource(1_000, null), true);
  assert.equal(becomesFuelSource(2_000, 1_000), true);
  assert.equal(becomesFuelSource(1_000, 1_000), true);
});

test("becomesFuelSource : vol plus ancien que la source (clôture tardive)", () => {
  assert.equal(becomesFuelSource(1_000, 2_000), false);
});
```

- [ ] **Step 2 : tests de validation** (ajouter à `validation.test.ts`)

```ts
const closing = { flightId: "f1", actualMinutes: 60, landings: 1,
  fuelStartExpected: 40, fuelStart: 40, fuelAdded: 0, fuelEnd: 30 };

test("validateClosing : carburant rendu tel quel, prévu null accepté", () => {
  const v = validateClosing(closing);
  assert.equal(v.fuelStartExpected, 40);
  assert.equal(v.fuelStart, 40);
  assert.equal(v.fuelAdded, 0);
  assert.equal(v.fuelEnd, 30);
  assert.equal(validateClosing({ ...closing, fuelStartExpected: null }).fuelStartExpected, null);
  assert.equal(validateClosing({ ...closing, fuelStartExpected: undefined }).fuelStartExpected, null);
});

test("validateClosing : carburant obligatoire, entier de 0 à 100", () => {
  const msg = (m: string) => (e: unknown) => e instanceof ValidationError && e.message === m;
  assert.throws(() => validateClosing({ ...closing, fuelStart: undefined }),
    msg("Carburant au départ invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelAdded: -1 }),
    msg("Carburant ajouté invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelEnd: 101 }),
    msg("Carburant rangé invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelEnd: 12.5 }),
    msg("Carburant rangé invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelStartExpected: "40" }),
    msg("Carburant prévu invalide (0 à 100 L)."));
  assert.equal(validateClosing({ ...closing, fuelAdded: 100 }).fuelAdded, 100);
});

test("validateAdminUpdate : carburant facultatif, mêmes bornes", () => {
  const base = { flightId: "f1", ...ok };
  const none = validateAdminUpdate(base);
  assert.equal(none.fuelStart, undefined);
  assert.equal(none.fuelEnd, undefined);
  const v = validateAdminUpdate({ ...base, fuelStart: 10, fuelAdded: 20, fuelEnd: 5 });
  assert.deepEqual([v.fuelStart, v.fuelAdded, v.fuelEnd], [10, 20, 5]);
  assert.throws(() => validateAdminUpdate({ ...base, fuelEnd: 150 }), ValidationError);
});
```

- [ ] **Step 3 : vérifier l'échec** — `cd functions && npm test` : échec
  (module `./fuel` absent, champs carburant `undefined`).

- [ ] **Step 4 : implémenter**

`functions/src/rules/fuel.ts` :

```ts
// Suivi carburant (spec §9.2) : un vol clôturé devient la source du
// carburant actuel de l'appareil s'il part au même moment ou après le vol
// source actuel, ou si l'appareil n'a pas encore de valeur. Module pur.
export function becomesFuelSource(flightStartMs: number, sourceStartMs: number | null): boolean {
  return sourceStartMs === null || flightStartMs >= sourceStartMs;
}
```

Dans `validation.ts`, après `checkLandingsTotal` :

```ts
/** Carburant (spec §9) : litres entiers de 0 à 100. */
export const MAX_FUEL_LITERS = 100;

function liters(v: unknown, label: string): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > MAX_FUEL_LITERS) {
    throw new ValidationError(`${label} invalide (0 à ${MAX_FUEL_LITERS} L).`);
  }
  return v;
}
```

`validateClosing` : ajouter au type de retour et à l'objet rendu

```ts
    fuelStartExpected: d.fuelStartExpected == null ? null : liters(d.fuelStartExpected, "Carburant prévu"),
    fuelStart: liters(d.fuelStart, "Carburant au départ"),
    fuelAdded: liters(d.fuelAdded, "Carburant ajouté"),
    fuelEnd: liters(d.fuelEnd, "Carburant rangé"),
```

`AdminUpdate` : `fuelStart?: number; fuelAdded?: number; fuelEnd?: number;`
et dans `validateAdminUpdate`, avant les montants :

```ts
  if (d.fuelStart !== undefined) out.fuelStart = liters(d.fuelStart, "Carburant au départ");
  if (d.fuelAdded !== undefined) out.fuelAdded = liters(d.fuelAdded, "Carburant ajouté");
  if (d.fuelEnd !== undefined) out.fuelEnd = liters(d.fuelEnd, "Carburant rangé");
```

- [ ] **Step 5 : vérifier** — `cd functions && npm test` : tout passe
  (`npm run build` compris si le script le lance ; sinon `npx tsc --noEmit`).

- [ ] **Step 6 : commit**

```bash
git add functions/src/rules/fuel.ts functions/src/rules/fuel.test.ts functions/src/flights/validation.ts functions/src/flights/validation.test.ts
git commit -m "feat(functions): fuel validation and fuel source rule (plan 7)"
```

---

### Task 2 : `closeFlight` enregistre le carburant et met à jour l'appareil

**Files:**
- Modify: `functions/src/flights/close.ts`
- Modify: `functions/src/flights/testkit.ts` (constante `FUEL`)
- Modify (appels existants) : `functions/src/flights/close.int.test.ts`,
  `functions/src/flights/admin-edit.int.test.ts`,
  `functions/src/finance/accounts.int.test.ts`,
  `functions/src/notify/movements.int.test.ts`
- Test: `functions/src/flights/close.int.test.ts`,
  `functions/src/admin/admin.int.test.ts`

**Interfaces:**
- Consumes: `validateClosing` (Task 1), `becomesFuelSource` (Task 1).
- Produces: champs `flights.fuelStartExpectedLiters`, `fuelStartLiters`,
  `fuelAddedLiters`, `fuelEndLiters` ; champs `aircraft.fuelLiters`,
  `fuelFlightId`, `fuelFlightStart` (Timestamp) ; `FUEL` dans `testkit.ts`.

- [ ] **Step 1 : `FUEL` et appels existants.** Dans `testkit.ts` :

```ts
/** Carburant valide pour les clôtures de test (plan 7, champs obligatoires). */
export const FUEL = { fuelStartExpected: null, fuelStart: 40, fuelAdded: 0, fuelEnd: 30 };
```

Puis, dans les quatre fichiers d'intégration listés, préfixer **chaque**
objet passé à `closeFlight` par `...FUEL, ` et importer `FUEL` depuis le
testkit (`./testkit` ou `../flights/testkit`) :

```bash
cd functions/src
sed -i 's/closeFlight(\([A-Za-z0-9_]*\), { /closeFlight(\1, { ...FUEL, /' \
  flights/close.int.test.ts flights/admin-edit.int.test.ts finance/accounts.int.test.ts notify/movements.int.test.ts
grep -n "closeFlight(" flights/*.int.test.ts finance/*.int.test.ts notify/*.int.test.ts | grep -v "\.\.\.FUEL"
```

La dernière commande ne doit rien afficher (sinon corriger à la main, par
exemple un appel `closeFlight(x, {` sans espace ou sur plusieurs lignes).

- [ ] **Step 2 : tests qui échouent** (fin de `close.int.test.ts`)

```ts
const getAircraft = async (id: string) => (await db.collection("aircraft").doc(id).get()).data()!;

test("carburant : valeurs enregistrées sur le vol, recopiées sur l'appareil", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start, end: start + H });
  await closeFlight(pilot, { flightId: id, actualMinutes: 60, landings: 1,
    fuelStartExpected: null, fuelStart: 35, fuelAdded: 20, fuelEnd: 41 });
  const f = await getFlight(id);
  assert.equal(f.fuelStartExpectedLiters, null);
  assert.equal(f.fuelStartLiters, 35);
  assert.equal(f.fuelAddedLiters, 20);
  assert.equal(f.fuelEndLiters, 41);
  const ac = await getAircraft(a);
  assert.equal(ac.fuelLiters, 41);
  assert.equal(ac.fuelFlightId, id);
  assert.equal(ac.fuelFlightStart.toMillis(), start);
});

test("carburant : clôture tardive d'un vol plus ancien, appareil inchangé", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const older = Date.now() - 30 * H;
  const newer = Date.now() - 5 * H;
  const idNew = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start: newer, end: newer + H });
  const idOld = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start: older, end: older + H });
  await closeFlight(pilot, { ...FUEL, flightId: idNew, actualMinutes: 60, landings: 1, fuelEnd: 25 });
  await closeFlight(pilot, { ...FUEL, flightId: idOld, actualMinutes: 60, landings: 1, fuelEnd: 70 });
  assert.equal((await getFlight(idOld)).fuelEndLiters, 70);
  const ac = await getAircraft(a);
  assert.equal(ac.fuelLiters, 25);
  assert.equal(ac.fuelFlightId, idNew);
});

test("carburant manquant : invalid-argument, vol non clôturé", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });
  await assert.rejects(
    closeFlight(pilot, { flightId: id, actualMinutes: 60, landings: 1, fuelStart: 40, fuelAdded: 0 }),
    (e) => code(e) === "invalid-argument" && (e as Error).message === "Carburant rangé invalide (0 à 100 L).",
  );
  assert.equal((await getFlight(id)).isClosed, false);
});
```

Et dans `functions/src/admin/admin.int.test.ts` (Review Focus 4) :

```ts
test("appareils : la modification de la fiche conserve le carburant", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const reg = `F-${uniq().toUpperCase().slice(0, 4)}`;
  const { id } = await upsertAircraft(me, { registration: reg, label: "ULM 1" });
  await db.collection("aircraft").doc(id).update({ fuelLiters: 33, fuelFlightId: "f-x" });
  await upsertAircraft(me, { id, registration: reg, label: "ULM 1 bis" });
  const a = (await db.collection("aircraft").doc(id).get()).data()!;
  assert.equal(a.fuelLiters, 33);
  assert.equal(a.fuelFlightId, "f-x");
});
```

- [ ] **Step 3 : vérifier l'échec** — intégration (commande des Global
  Constraints) : les tests carburant de `close.int.test.ts` échouent
  (`fuelStartLiters` absent) ; le test d'upsert passe déjà (il fige le
  comportement de `merge: true`).

- [ ] **Step 4 : implémenter** dans `close.ts`.
  - Déstructurer aussi `fuelStartExpected, fuelStart, fuelAdded, fuelEnd`
    depuis `validateClosing`.
  - Remplacer le bloc « Plan 4b : amerrissages » par une lecture
    **systématique** de l'appareil (avant toute écriture) :

```ts
    // Plan 4b : amerrissages réservés à un appareil amphibie. Plan 7 :
    // l'appareil est lu dans tous les cas (carburant actuel, spec §9.2).
    const aircraftRef = db.collection("aircraft").doc(f.get("aircraftId") as string);
    const aircraft = await tx.get(aircraftRef);
    if (waterLandings > 0 && aircraft.get("amphibious") !== true) {
      throw new HttpsError("failed-precondition", "Cet appareil n'est pas amphibie.");
    }
```

  - Dans `tx.update(ref, { ... })`, ajouter :

```ts
      fuelStartExpectedLiters: fuelStartExpected,
      fuelStartLiters: fuelStart,
      fuelAddedLiters: fuelAdded,
      fuelEndLiters: fuelEnd,
```

  - Juste après ce `tx.update`, avant le `return` :

```ts
    // 5. Carburant actuel de l'appareil (spec §9.2) : seulement si ce vol
    // est le plus récent à avoir déclaré son carburant.
    const sourceStart = aircraft.get("fuelFlightStart") as FirebaseFirestore.Timestamp | undefined;
    if (aircraft.exists && becomesFuelSource(startMs, sourceStart?.toMillis() ?? null)) {
      tx.update(aircraftRef, {
        fuelLiters: fuelEnd,
        fuelFlightId: ref.id,
        fuelFlightStart: f.get("start"),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
```

  - Importer `becomesFuelSource` depuis `../rules/fuel` ; mettre à jour le
    commentaire d'en-tête du fichier (« et carburant, spec §9 »).

- [ ] **Step 5 : vérifier** — `npm test` puis l'intégration complète : tout
  passe.

- [ ] **Step 6 : commit**

```bash
git add functions/src
git commit -m "feat(functions): closeFlight records fuel and updates the aircraft's current fuel (plan 7)"
```

---

### Task 3 : correction admin du carburant (`adminUpdateFlight`)

**Files:**
- Modify: `functions/src/flights/admin-edit.ts`
- Test: `functions/src/flights/admin-edit.int.test.ts`

**Interfaces:**
- Consumes: `AdminUpdate.fuelStart/fuelAdded/fuelEnd` (Task 1), champs de la
  Task 2, `FUEL` du testkit.

- [ ] **Step 1 : tests qui échouent** (fin de `admin-edit.int.test.ts` ;
  `closedFlight` y appelle déjà `closeFlight` avec `...FUEL`, donc `fuelEnd`
  = 30 et l'appareil a pour source ce vol)

```ts
const fuelOf = async (aircraftId: string) =>
  (await db.collection("aircraft").doc(aircraftId).get()).get("fuelLiters") as number | undefined;

test("carburant corrigé sur le vol source : le vol et l'appareil suivent", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });
  assert.equal(await fuelOf(a), 30);
  await adminUpdateFlight(boss, await correction(id, { fuelStart: 12, fuelAdded: 30, fuelEnd: 22 }));
  const f = await getFlight(id);
  assert.deepEqual([f.fuelStartLiters, f.fuelAddedLiters, f.fuelEndLiters], [12, 30, 22]);
  assert.equal(await fuelOf(a), 22);
});

test("carburant corrigé sur un vol qui n'est pas la source : appareil inchangé", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });
  await db.collection("aircraft").doc(a).update({ fuelFlightId: "autre-vol", fuelLiters: 55 });
  await adminUpdateFlight(boss, await correction(id, { fuelEnd: 10 }));
  assert.equal((await getFlight(id)).fuelEndLiters, 10);
  assert.equal(await fuelOf(a), 55);
});

test("correction sans carburant : valeurs carburant du vol inchangées", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });
  await adminUpdateFlight(boss, await correction(id, { destination: "Kara" }));
  const f = await getFlight(id);
  assert.deepEqual([f.fuelStartLiters, f.fuelAddedLiters, f.fuelEndLiters], [40, 0, 30]);
  assert.equal(await fuelOf(a), 30);
});

test("carburant sur un vol non clôturé : refusé", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedFlight({ start: at(10), end: at(11), crew: [pilot.uid], aircraftId: a, createdBy: pilot.uid });
  await assert.rejects(adminUpdateFlight(boss, await correction(id, { fuelEnd: 10 })),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "Réservé aux vols clôturés.");
});
```

- [ ] **Step 2 : vérifier l'échec** — intégration : les trois premiers
  échouent (champs non écrits), le quatrième aussi (pas encore refusé).

- [ ] **Step 3 : implémenter** dans `admin-edit.ts`.
  - Ajouter `v.fuelStart !== undefined || v.fuelAdded !== undefined ||
    v.fuelEnd !== undefined` à la condition du refus
    « Réservé aux vols clôturés. ».
  - Dans le bloc `if (closed) { ... }`, **après** le contrôle amphibie
    (lectures avant écritures), lire l'appareil source éventuel :

```ts
      // Plan 7 (spec §9.3) : le carburant actuel suit la correction si ce
      // vol en est la source et que son appareil ne change pas.
      if (v.fuelEnd !== undefined && input.aircraftId === f.get("aircraftId")) {
        const ref2 = db.collection("aircraft").doc(input.aircraftId);
        const ac = await tx.get(ref2);
        if (ac.exists && ac.get("fuelFlightId") === ref.id) fuelAircraftRef = ref2;
      }
```

    avec `let fuelAircraftRef: Ref | null = null;` déclaré à côté de
    `let landings = 0;`.
  - Dans le `tx.update(ref, { ...p.fields, ... })` du vol clôturé, ajouter :

```ts
      ...(v.fuelStart !== undefined ? { fuelStartLiters: v.fuelStart } : {}),
      ...(v.fuelAdded !== undefined ? { fuelAddedLiters: v.fuelAdded } : {}),
      ...(v.fuelEnd !== undefined ? { fuelEndLiters: v.fuelEnd } : {}),
```

    puis, juste après :

```ts
    if (fuelAircraftRef) {
      tx.update(fuelAircraftRef, { fuelLiters: v.fuelEnd, updatedAt: FieldValue.serverTimestamp() });
    }
```

- [ ] **Step 4 : vérifier** — `npm test` et intégration complète : tout passe.

- [ ] **Step 5 : commit**

```bash
git add functions/src/flights/admin-edit.ts functions/src/flights/admin-edit.int.test.ts
git commit -m "feat(functions): admin fuel correction follows on the aircraft for the source flight (plan 7)"
```

---

### Task 4 : app, modèles, API et calculs carburant (purs)

**Files:**
- Create: `lib/core/fuel.dart`
- Create: `test/core/fuel_test.dart`
- Modify: `lib/data/aircraft.dart`, `lib/data/flight.dart`,
  `lib/data/finance_api.dart`, `lib/data/flight_api.dart`,
  `test/support/fakes.dart`
- Test: `test/data/flight_test.dart`

**Interfaces:**
- Produces:
  - `Aircraft.fuelLiters` (`int?`), `Aircraft.fuelFlightId` (`String?`)
  - `Flight.fuelStartExpectedLiters`, `fuelStartLiters`, `fuelAddedLiters`,
    `fuelEndLiters` (tous `int?`) ; getter `bool get hasFuel` (les trois
    valeurs départ/ajouté/rangé présentes)
  - `FinanceApi.closeFlight(..., required int? fuelStartExpected, required int fuelStart, required int fuelAdded, required int fuelEnd)`
  - `FlightApi.watchAircraftFlights(String aircraftId) → Stream<List<Flight>>`
  - `lib/core/fuel.dart` : `const maxFuelLiters = 100;`,
    `String? fuelError({required int? start, required int? added, required int? end})`,
    `String fuelText(int? liters)` (« 40 L » / « inconnu »),
    `bool fuelGap(Flight f)`, `class FuelStats { final double litersPerHour; final int flights; final int minutes; }`,
    `FuelStats? fuelStats(Iterable<Flight> flights)`,
    `String formatLitersPerHour(double v)` (« 14,2 L/h »)
  - `testFlight(...)` (fakes) accepte `fuelStartExpected`, `fuelStart`,
    `fuelAdded`, `fuelEnd` (`int?`) ; `FakeFinanceApi.closed` enregistre les
    quatre valeurs sous ces mêmes clés.

- [ ] **Step 1 : tests qui échouent** (`test/core/fuel_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/fuel.dart';

import '../support/fakes.dart';

void main() {
  test('fuelError : bornes 0 à 100, messages du serveur', () {
    expect(fuelError(start: 40, added: 0, end: 30), isNull);
    expect(fuelError(start: null, added: 0, end: 30), 'Carburant au départ invalide (0 à 100 L).');
    expect(fuelError(start: 40, added: 101, end: 30), 'Carburant ajouté invalide (0 à 100 L).');
    expect(fuelError(start: 40, added: 0, end: -1), 'Carburant rangé invalide (0 à 100 L).');
    expect(fuelError(start: 100, added: 100, end: 0), isNull);
  });

  test('fuelText', () {
    expect(fuelText(40), '40 L');
    expect(fuelText(null), 'inconnu');
  });

  test('fuelGap : départ différent du prévu, ou prévu inconnu', () {
    Flight f(int? expected, int start) => testFlight(
        isClosed: true, actualFlightMinutes: 60,
        fuelStartExpected: expected, fuelStart: start, fuelAdded: 0, fuelEnd: 10);
    expect(fuelGap(f(40, 40)), isFalse);
    expect(fuelGap(f(40, 30)), isTrue);
    expect(fuelGap(f(null, 30)), isTrue);
  });

  test('fuelStats : Σ (départ + ajouté − rangé) / Σ minutes', () {
    final flights = [
      testFlight(id: 'a', isClosed: true, actualFlightMinutes: 60,
          fuelStartExpected: 40, fuelStart: 40, fuelAdded: 20, fuelEnd: 45), // 15 L
      testFlight(id: 'b', isClosed: true, actualFlightMinutes: 120,
          fuelStartExpected: 45, fuelStart: 45, fuelAdded: 0, fuelEnd: 20), // 25 L
    ];
    final s = fuelStats(flights)!;
    expect(s.flights, 2);
    expect(s.minutes, 180);
    expect(s.litersPerHour, closeTo(40 / 3, 1e-9));
    expect(formatLitersPerHour(s.litersPerHour), '13,3 L/h');
  });

  test('fuelStats : vols sans carburant, non clôturés ou supprimés exclus ; null sans vol utile', () {
    expect(fuelStats([]), isNull);
    expect(fuelStats([testFlight(isClosed: true, actualFlightMinutes: 60)]), isNull);
    final counted = testFlight(id: 'ok', isClosed: true, actualFlightMinutes: 60,
        fuelStart: 30, fuelAdded: 0, fuelEnd: 18);
    final deleted = testFlight(id: 'del', isClosed: true, deleted: true, actualFlightMinutes: 60,
        fuelStart: 30, fuelAdded: 0, fuelEnd: 0);
    final open = testFlight(id: 'open', actualFlightMinutes: null,
        fuelStart: 30, fuelAdded: 0, fuelEnd: 0);
    final s = fuelStats([counted, deleted, open])!;
    expect(s.flights, 1);
    expect(s.litersPerHour, 12);
  });
}
```

Dans `test/data/flight_test.dart`, ajouter :

```dart
  test('carburant lu depuis Firestore ; hasFuel', () {
    final f = testFlight(fuelStartExpected: null, fuelStart: 35, fuelAdded: 20, fuelEnd: 41);
    expect(f.fuelStartExpectedLiters, isNull);
    expect([f.fuelStartLiters, f.fuelAddedLiters, f.fuelEndLiters], [35, 20, 41]);
    expect(f.hasFuel, isTrue);
    expect(testFlight().hasFuel, isFalse);
  });

  test('appareil : carburant actuel', () {
    final a = Aircraft.fromMap('a1', {'registration': 'F-X', 'label': 'ULM', 'active': true,
        'fuelLiters': 41, 'fuelFlightId': 'f1'});
    expect(a.fuelLiters, 41);
    expect(a.fuelFlightId, 'f1');
    expect(Aircraft.fromMap('a2', {}).fuelLiters, isNull);
  });
```

(importer `package:ulmgap/data/aircraft.dart` si absent.)

- [ ] **Step 2 : vérifier l'échec** — `fvm flutter test test/core/fuel_test.dart test/data/flight_test.dart` : échec de compilation.

- [ ] **Step 3 : implémenter**
  - `Aircraft` : champs `fuelLiters` et `fuelFlightId` (constructeur
    facultatif), lus par `fromMap` (`(m['fuelLiters'] as num?)?.toInt()`,
    `m['fuelFlightId'] as String?`), doc « Plan 7 : carburant actuel (spec
    §9.2) ».
  - `Flight` : quatre champs `int?` (constructeur facultatif), lus par
    `fromMap` depuis `fuelStartExpectedLiters`, `fuelStartLiters`,
    `fuelAddedLiters`, `fuelEndLiters` ; getter
    `bool get hasFuel => fuelStartLiters != null && fuelAddedLiters != null && fuelEndLiters != null;`
  - `testFlight` (fakes) : paramètres `int? fuelStartExpected, int? fuelStart, int? fuelAdded, int? fuelEnd`
    recopiés dans la map sous les noms Firestore.
  - `FinanceApi.closeFlight` (abstrait, Firebase, fake) : quatre paramètres
    nommés `required int? fuelStartExpected, required int fuelStart, required int fuelAdded, required int fuelEnd` ;
    l'implémentation Firebase envoie `'fuelStartExpected': fuelStartExpected`
    (null compris), `'fuelStart'`, `'fuelAdded'`, `'fuelEnd'` ; le fake les
    ajoute à `closed` sous ces clés.
  - `FlightApi.watchAircraftFlights(String aircraftId)` : doc « Vols d'un
    appareil (écran Suivi carburant) ; égalité seule, tri dans l'app » ;
    Firebase : `_flights.where('aircraftId', isEqualTo: aircraftId).snapshots().map(...)` ;
    fake : 

```dart
  @override
  Stream<List<Flight>> watchAircraftFlights(String aircraftId) async* {
    yield flights.where((f) => f.aircraftId == aircraftId).toList();
    yield* flightsCtrl.stream.map((l) => l.where((f) => f.aircraftId == aircraftId).toList());
  }
```

  - `lib/core/fuel.dart` :

```dart
// Suivi carburant (spec §9) : contrôles de saisie (mêmes messages que le
// serveur) et consommation estimée, indicative. Module pur.
import '../data/flight.dart';

const maxFuelLiters = 100;

bool _ok(int? v) => v != null && v >= 0 && v <= maxFuelLiters;

/// null si les trois valeurs sont valides.
String? fuelError({required int? start, required int? added, required int? end}) {
  if (!_ok(start)) return 'Carburant au départ invalide (0 à $maxFuelLiters L).';
  if (!_ok(added)) return 'Carburant ajouté invalide (0 à $maxFuelLiters L).';
  if (!_ok(end)) return 'Carburant rangé invalide (0 à $maxFuelLiters L).';
  return null;
}

String fuelText(int? liters) => liters == null ? 'inconnu' : '$liters L';

/// Écart au départ : valeur déclarée différente de la valeur prévue, ou
/// prévue inconnue.
bool fuelGap(Flight f) =>
    f.fuelStartExpectedLiters == null || f.fuelStartExpectedLiters != f.fuelStartLiters;

class FuelStats {
  const FuelStats(this.litersPerHour, this.flights, this.minutes);
  final double litersPerHour;
  final int flights;
  final int minutes;
}

/// Consommation estimée : Σ (départ + ajouté − rangé) / Σ durée réelle, sur
/// les vols clôturés non supprimés avec carburant ; null sans vol utile.
FuelStats? fuelStats(Iterable<Flight> flights) {
  var liters = 0;
  var minutes = 0;
  var count = 0;
  for (final f in flights) {
    final m = f.actualFlightMinutes;
    if (!f.isClosed || f.deleted || !f.hasFuel || m == null || m <= 0) continue;
    liters += f.fuelStartLiters! + f.fuelAddedLiters! - f.fuelEndLiters!;
    minutes += m;
    count++;
  }
  if (count == 0) return null;
  return FuelStats(liters * 60 / minutes, count, minutes);
}

String formatLitersPerHour(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} L/h';
```

  - Corriger les appelants de `closeFlight` qui ne compilent plus
    (`flight_screen.dart`) **provisoirement** en passant
    `fuelStartExpected: null, fuelStart: 0, fuelAdded: 0, fuelEnd: 0` : la
    Task 5 les remplace par les valeurs saisies.

- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze` :
  tout passe.

- [ ] **Step 5 : commit**

```bash
git add lib test
git commit -m "feat(app): fuel fields, aircraft flights stream and fuel stats (plan 7)"
```

---

### Task 5 : dialogue de clôture, bloc carburant

**Files:**
- Modify: `lib/features/flight/closing_dialog.dart`
- Modify: `lib/features/flight/flight_screen.dart` (`_openClosing`)
- Test: `test/features/flight/closing_dialog_test.dart`,
  `test/features/flight/flight_screen_test.dart`

**Interfaces:**
- Consumes: `fuelError`, `fuelText` (Task 4), `FinanceApi.closeFlight`
  (Task 4), `Aircraft.fuelLiters`.
- Produces: `ClosingDialog({..., int? fuelExpected})` ;
  `ClosingResult.fuelStartExpected` (`int?`), `fuelStart`, `fuelAdded`,
  `fuelEnd` (`int`) ; clés de widgets `closing-fuel-expected` (Text),
  `closing-fuel-gap` (case), `closing-fuel-start`, `closing-fuel-added`,
  `closing-fuel-end` (TextField).

- [ ] **Step 1 : tests qui échouent** (`closing_dialog_test.dart`).
  Ajouter le paramètre `int? fuelExpected = 40` à `open(...)` (transmis au
  dialogue), et l'aide :

```dart
/// Remplit les champs carburant obligatoires (et le départ s'il est affiché).
Future<void> fillFuel(WidgetTester tester, {String added = '0', String end = '30'}) async {
  final start = find.byKey(const Key('closing-fuel-start'));
  if (start.evaluate().isNotEmpty) await tester.enterText(start, '40');
  await tester.enterText(find.byKey(const Key('closing-fuel-added')), added);
  await tester.enterText(find.byKey(const Key('closing-fuel-end')), end);
}
```

  Appeler `await fillFuel(tester);` avant `submit` dans chaque test
  existant qui attend une clôture **réussie** (ceux qui vérifient un refus
  restent tels quels). Nouveaux tests :

```dart
  testWidgets('carburant connu : prévu affiché, départ = prévu si la case n\'est pas cochée',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: 40);
    expect(find.text('Carburant prévu au départ : 40 L'), findsOneWidget);
    expect(find.byKey(const Key('closing-fuel-start')), findsNothing);
    await fillFuel(tester, added: '20', end: '45');
    await submit(tester);
    final r = out.single!;
    expect([r.fuelStartExpected, r.fuelStart, r.fuelAdded, r.fuelEnd], [40, 40, 20, 45]);
  });

  testWidgets('non conforme : départ corrigé transmis', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: 40);
    await tester.tap(find.byKey(const Key('closing-fuel-gap')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '25');
    await fillFuel(tester);
    await submit(tester);
    expect(out.single!.fuelStart, 25);
    expect(out.single!.fuelStartExpected, 40);
  });

  testWidgets('non conforme cochée puis décochée : départ = prévu', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: 40);
    await tester.tap(find.byKey(const Key('closing-fuel-gap')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '25');
    await tester.tap(find.byKey(const Key('closing-fuel-gap')));
    await tester.pumpAndSettle();
    await fillFuel(tester);
    await submit(tester);
    expect(out.single!.fuelStart, 40);
  });

  testWidgets('carburant inconnu : pas de case, départ obligatoire', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: null);
    expect(find.text('Carburant prévu au départ : inconnu'), findsOneWidget);
    expect(find.byKey(const Key('closing-fuel-gap')), findsNothing);
    await tester.enterText(find.byKey(const Key('closing-fuel-added')), '0');
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '30');
    await submit(tester);
    expect(find.text('Carburant au départ invalide (0 à 100 L).'), findsOneWidget);
    expect(out, isEmpty);
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '12');
    await submit(tester);
    expect(out.single!.fuelStartExpected, isNull);
    expect(out.single!.fuelStart, 12);
  });

  testWidgets('ajouté et rangé vides : refusés ; plus de 100 L : refusé', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await submit(tester);
    expect(find.text('Carburant ajouté invalide (0 à 100 L).'), findsOneWidget);
    await fillFuel(tester, end: '101');
    await submit(tester);
    expect(find.text('Carburant rangé invalide (0 à 100 L).'), findsOneWidget);
    expect(out, isEmpty);
  });
```

  Dans `flight_screen_test.dart`, ajouter la même aide `fillFuel` (copie,
  fichiers de test indépendants) et l'appeler avant chaque
  `tap(find.text('Clôturer').last)` qui attend une clôture réussie (lignes
  ~656, ~694, ~787, ~1098 au moment de l'écriture). Nouveau test :

```dart
  testWidgets('clôture : carburant prévu = carburant actuel de l\'appareil, valeurs envoyées',
      (tester) async {
    // Reprendre la mise en place du test de clôture existant (vol 'c1' passé,
    // équipage u1, FakeFinanceApi), avec un appareil à 40 L :
    final a = api()
      ..aircraft = [
        Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true,
            'fuelLiters': 40}),
      ];
    // ... même vol et même `finance` que le test « clôture » existant ...
    // ouvrir le dialogue, puis :
    expect(find.text('Carburant prévu au départ : 40 L'), findsOneWidget);
    await fillFuel(tester, added: '10', end: '35');
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    final c = finance.closed.single;
    expect([c['fuelStartExpected'], c['fuelStart'], c['fuelAdded'], c['fuelEnd']], [40, 40, 10, 35]);
  });
```

  (L'implémenteur recopie concrètement la mise en place du test de clôture
  existant, ligne ~640, en remplaçant seulement la liste d'appareils.)

- [ ] **Step 2 : vérifier l'échec** — `fvm flutter test test/features/flight/` : échec.

- [ ] **Step 3 : implémenter.**
  - `ClosingResult` : ajouter `this.fuelStartExpected, this.fuelStart = 0, this.fuelAdded = 0, this.fuelEnd = 0`
    en paramètres nommés et les champs correspondants.
  - `ClosingDialog` : paramètre `final int? fuelExpected;` (doc « Plan 7 :
    carburant actuel de l'appareil, null si inconnu »).
  - État : `bool _fuelGap = false;` et trois contrôleurs vides
    `_fuelStart`, `_fuelAdded`, `_fuelEnd` (libérés dans `dispose`).
  - `_submit`, après le contrôle des atterrissages :

```dart
    final unknown = widget.fuelExpected == null;
    final fuelStart = unknown || _fuelGap ? int.tryParse(_fuelStart.text.trim()) : widget.fuelExpected;
    final fuelAdded = int.tryParse(_fuelAdded.text.trim());
    final fuelEnd = int.tryParse(_fuelEnd.text.trim());
    final fuelErr = fuelError(start: fuelStart, added: fuelAdded, end: fuelEnd);
    if (fuelErr != null) {
      setState(() => _error = fuelErr);
      return;
    }
```

    et passer `fuelStartExpected: widget.fuelExpected, fuelStart: fuelStart!, fuelAdded: fuelAdded!, fuelEnd: fuelEnd!`
    au `ClosingResult`.
  - Interface, après le champ « Amerrissages » :

```dart
            const SizedBox(height: 12),
            Text('Carburant', style: Theme.of(context).textTheme.titleSmall),
            Text('Carburant prévu au départ : ${fuelText(widget.fuelExpected)}',
                key: const Key('closing-fuel-expected')),
            if (widget.fuelExpected != null)
              CheckboxListTile(
                key: const Key('closing-fuel-gap'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Carburant réel à bord non conforme'),
                value: _fuelGap,
                onChanged: (v) => setState(() => _fuelGap = v ?? false),
              ),
            if (widget.fuelExpected == null || _fuelGap)
              TextField(
                key: const Key('closing-fuel-start'),
                controller: _fuelStart,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: widget.fuelExpected == null
                        ? 'Carburant au départ (L)'
                        : 'Carburant réel au départ (L)'),
              ),
            TextField(
              key: const Key('closing-fuel-added'),
              controller: _fuelAdded,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Carburant ajouté (L)'),
            ),
            TextField(
              key: const Key('closing-fuel-end'),
              controller: _fuelEnd,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Carburant à bord, appareil rangé (L)'),
            ),
```

  - `flight_screen.dart`, `_openClosing` : passer
    `fuelExpected: _aircraftOf(f.aircraftId)?.fuelLiters` au dialogue, avec

```dart
  Aircraft? _aircraftOf(String? id) {
    for (final a in _allAircraft) {
      if (a.id == id) return a;
    }
    return null;
  }
```

    puis remplacer les valeurs provisoires de la Task 4 par
    `result.fuelStartExpected`, `result.fuelStart`, `result.fuelAdded`,
    `result.fuelEnd`.
  - Mettre à jour le commentaire de classe de `ClosingDialog` (bloc
    carburant, spec §9.1).

- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze` :
  tout passe.

- [ ] **Step 5 : commit**

```bash
git add lib/features/flight test/features/flight
git commit -m "feat(app): fuel block in the closing dialog (plan 7)"
```

---

### Task 6 : affichages et écran « Suivi carburant »

**Files:**
- Create: `lib/features/fuel/fuel_log_screen.dart` (écran + widget
  `CurrentFuelTile`)
- Create: `test/features/fuel/fuel_log_screen_test.dart`
- Modify: `lib/features/flight/flight_texts.dart` (`fuelSummary`)
- Modify: `lib/features/flight/flight_screen.dart` (affichages)
- Modify: `lib/features/admin/aircraft_admin_screen.dart`
- Test: `test/features/flight/flight_texts_test.dart`,
  `test/features/flight/flight_screen_test.dart`,
  `test/features/admin/aircraft_admin_screen_test.dart`

**Interfaces:**
- Consumes: `FlightApi.watchAircraft`, `watchAircraftFlights`,
  `watchDirectory` ; `fuelText`, `fuelGap`, `fuelStats`,
  `formatLitersPerHour` (Task 4) ; `crewText`, `formatDurationHm`
  (`flight_texts.dart`) ; `formatDay` (`core/formats.dart`) ;
  `FlightScreen`.
- Produces:
  - `FuelLogScreen({required AppUser me, required String aircraftId, DateTime Function() now = DateTime.now})`
  - `CurrentFuelTile({required AppUser me, required Aircraft aircraft})` :
    `ListTile` clé `current-fuel`, titre « Carburant : 40 L » (ou
    « inconnu »), icône `Icons.local_gas_station`, appui → `FuelLogScreen`
  - `String fuelSummary(Flight f)` : « Carburant : départ 40 L · ajouté 20 L
    · rangé 35 L », plus « (prévu 30 L) » ou « (prévu inconnu) » si
    `fuelGap(f)`.

- [ ] **Step 1 : tests qui échouent.**

`flight_texts_test.dart` :

```dart
  test('fuelSummary : sans écart, avec écart, prévu inconnu', () {
    Flight f(int? exp, int start) => testFlight(isClosed: true, actualFlightMinutes: 60,
        fuelStartExpected: exp, fuelStart: start, fuelAdded: 20, fuelEnd: 35);
    expect(fuelSummary(f(40, 40)), 'Carburant : départ 40 L · ajouté 20 L · rangé 35 L');
    expect(fuelSummary(f(30, 40)), 'Carburant : départ 40 L · ajouté 20 L · rangé 35 L (prévu 30 L)');
    expect(fuelSummary(f(null, 40)), 'Carburant : départ 40 L · ajouté 20 L · rangé 35 L (prévu inconnu)');
  });
```

`test/features/fuel/fuel_log_screen_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/fuel/fuel_log_screen.dart';

import '../../support/fakes.dart';

void main() {
  final me = testUser(); // aide de test/support/fakes.dart
  FakeFlightApi seeded() => FakeFlightApi()
    ..directory = [member('u1', 'JDU', 'eleve')]
    ..aircraft = [
      Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true, 'fuelLiters': 20}),
    ]
    ..flights = [
      testFlight(id: 'old', start: DateTime(2026, 10, 1, 9), isClosed: true, actualFlightMinutes: 60,
          fuelStartExpected: 40, fuelStart: 40, fuelAdded: 20, fuelEnd: 45),
      testFlight(id: 'new', start: DateTime(2026, 10, 2, 9), isClosed: true, actualFlightMinutes: 120,
          fuelStartExpected: 45, fuelStart: 30, fuelAdded: 0, fuelEnd: 20),
      testFlight(id: 'legacy', start: DateTime(2026, 9, 1, 9), isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'other', aircraftId: 'a2', isClosed: true, actualFlightMinutes: 60,
          fuelStart: 1, fuelAdded: 1, fuelEnd: 1),
    ];

  Widget host(FakeFlightApi api) => AppServices(
        auth: FakeAuthService(), users: FakeUserRepository(), flights: api,
        child: MaterialApp(home: FuelLogScreen(me: me, aircraftId: 'a1')),
      );

  testWidgets('titre, carburant actuel, consommation, vols du plus récent au plus ancien',
      (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(find.text('Suivi carburant · F-JABC'), findsOneWidget);
    expect(find.text('Carburant actuel : 20 L'), findsOneWidget);
    // (40+20−45) + (30+0−20) = 25 L sur 3 h
    expect(find.text('Consommation estimée : 8,3 L/h (2 vols, 3 h 00)'), findsOneWidget);
    final lines = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
    final iNew = lines.indexWhere((l) => l.contains('Départ 30 L'));
    final iOld = lines.indexWhere((l) => l.contains('Départ 40 L'));
    expect(iNew, lessThan(iOld));
    expect(find.text('Écart au départ : prévu 45 L, réel 30 L'), findsOneWidget);
    expect(find.textContaining('Départ 1 L'), findsNothing); // autre appareil
  });

  testWidgets('aucun vol avec carburant : consommation masquée', (tester) async {
    await tester.pumpWidget(host(seeded()..flights = []));
    await tester.pumpAndSettle();
    expect(find.textContaining('Consommation estimée'), findsNothing);
    expect(find.text('Aucun vol avec carburant.'), findsOneWidget);
  });
}
```

`flight_screen_test.dart` :

```dart
  testWidgets('vol non clôturé : carburant actuel affiché, appui → Suivi carburant',
      (tester) async {
    // vol à venir 'f1' sur a1 ; appareil a1 à 40 L (mise en place du test
    // de consultation existant, appareils remplacés)
    expect(find.text('Carburant : 40 L'), findsOneWidget);
    await tester.tap(find.byKey(const Key('current-fuel')));
    await tester.pumpAndSettle();
    expect(find.text('Suivi carburant · F-JABC'), findsOneWidget);
  });

  testWidgets('vol clôturé : résumé carburant', (tester) async {
    // vol clôturé avec fuelStartExpected 30, fuelStart 40, fuelAdded 20, fuelEnd 35
    expect(find.text('Carburant : départ 40 L · ajouté 20 L · rangé 35 L (prévu 30 L)'),
        findsOneWidget);
  });
```

`aircraft_admin_screen_test.dart` :

```dart
  testWidgets('carburant affiché ; bouton Suivi carburant', (tester) async {
    // FakeAdminApi.aircraft = [appareil 'a1' F-JABC à 40 L] ; écran avec `me` admin,
    // AppServices avec `flights: FakeFlightApi()` (même appareil) pour l'écran ouvert
    expect(find.text('F-JABC · carburant 40 L'), findsOneWidget);
    await tester.tap(find.byTooltip('Suivi carburant'));
    await tester.pumpAndSettle();
    expect(find.text('Suivi carburant · F-JABC'), findsOneWidget);
  });
```

(L'implémenteur reprend la mise en place des tests voisins de chaque
fichier ; seules les données et les assertions ci-dessus sont nouvelles.)

- [ ] **Step 2 : vérifier l'échec** — `fvm flutter test` : échec.

- [ ] **Step 3 : implémenter.**

`flight_texts.dart` :

```dart
/// Plan 7 (spec §9.4) : carburant déclaré à la clôture.
String fuelSummary(Flight f) {
  final base = 'Carburant : départ ${fuelText(f.fuelStartLiters)} · '
      'ajouté ${fuelText(f.fuelAddedLiters)} · rangé ${fuelText(f.fuelEndLiters)}';
  return fuelGap(f) ? '$base (prévu ${fuelText(f.fuelStartExpectedLiters)})' : base;
}
```

`lib/features/fuel/fuel_log_screen.dart` :

```dart
// Écran « Suivi carburant » d'un appareil (spec §9.5), ouvert par tout
// utilisateur depuis le carburant affiché (CurrentFuelTile).
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/fuel.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_screen.dart';
import '../flight/flight_texts.dart';
import '../home/app_nav.dart';

const _gapColor = Color(0xFFEF6C00);

/// « Carburant : 40 L » ; un appui ouvre le suivi carburant de l'appareil.
class CurrentFuelTile extends StatelessWidget {
  const CurrentFuelTile({super.key, required this.me, required this.aircraft});
  final AppUser me;
  final Aircraft aircraft;

  @override
  Widget build(BuildContext context) => ListTile(
        key: const Key('current-fuel'),
        leading: const Icon(Icons.local_gas_station),
        title: Text('Carburant : ${fuelText(aircraft.fuelLiters)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => FuelLogScreen(me: me, aircraftId: aircraft.id))),
      );
}

class FuelLogScreen extends StatelessWidget {
  const FuelLogScreen({super.key, required this.me, required this.aircraftId});
  final AppUser me;
  final String aircraftId;

  @override
  Widget build(BuildContext context) {
    final api = AppServices.of(context).flights!;
    return StreamBuilder<List<Aircraft>>(
      stream: api.watchAircraft(),
      builder: (context, acSnap) {
        Aircraft? aircraft;
        for (final a in acSnap.data ?? const <Aircraft>[]) {
          if (a.id == aircraftId) aircraft = a;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text('Suivi carburant · ${aircraft?.registration ?? ''}'),
            actions: appNavActions(context, me),
          ),
          body: StreamBuilder<List<CrewMember>>(
            stream: api.watchDirectory(),
            builder: (context, dirSnap) {
              final dir = {for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m};
              return StreamBuilder<List<Flight>>(
                stream: api.watchAircraftFlights(aircraftId),
                builder: (context, snap) {
                  final flights = (snap.data ?? const <Flight>[])
                      .where((f) => f.isClosed && !f.deleted && f.hasFuel)
                      .toList()
                    ..sort((a, b) => b.start.compareTo(a.start));
                  final stats = fuelStats(flights);
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    Text('Carburant actuel : ${fuelText(aircraft?.fuelLiters)}',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (stats != null)
                      Text('Consommation estimée : ${formatLitersPerHour(stats.litersPerHour)} '
                          '(${stats.flights} vol${stats.flights > 1 ? 's' : ''}, '
                          '${formatDurationHm(stats.minutes)})'),
                    const Divider(),
                    if (flights.isEmpty) const Text('Aucun vol avec carburant.'),
                    for (final f in flights)
                      ListTile(
                        tileColor: fuelGap(f) ? _gapColor.withValues(alpha: 0.12) : null,
                        title: Text('${formatDay(f.start)} · ${crewText(f.crew, f.passengers, dir)}'),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Départ ${f.fuelStartLiters} L · +${f.fuelAddedLiters} L · '
                              'Rangé ${f.fuelEndLiters} L'),
                          if (fuelGap(f))
                            Text('Écart au départ : prévu ${fuelText(f.fuelStartExpectedLiters)}, '
                                'réel ${f.fuelStartLiters} L',
                                style: const TextStyle(color: _gapColor)),
                        ]),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => FlightScreen(me: me, flight: f))),
                      ),
                  ]);
                },
              );
            },
          ),
        );
      },
    );
  }
}
```

`flight_screen.dart` :
  - sous le `DropdownButtonFormField` de l'appareil, si `f == null || !f.isClosed`
    et que `_aircraftOf(_aircraftId)` n'est pas nul :
    `CurrentFuelTile(me: _me, aircraft: _aircraftOf(_aircraftId)!)` (il suit
    le changement d'appareil pendant la saisie) ;
  - dans l'en-tête d'un vol clôturé, après `closed-summary`, si `f.hasFuel` :
    `ListTile(key: const Key('closed-fuel'), title: Text(fuelSummary(f)))`.

`aircraft_admin_screen.dart` : sous-titre
`'${a.amphibious ? '${a.registration} · amphibie' : a.registration} · carburant ${fuelText(a.fuelLiters)}'` ;
si `me != null`, `trailing` devient une `Row(mainAxisSize: MainAxisSize.min)`
avec la puce « Inactif » éventuelle et un
`IconButton(tooltip: 'Suivi carburant', icon: const Icon(Icons.local_gas_station), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FuelLogScreen(me: me!, aircraftId: a.id))))`.
Mettre à jour les assertions existantes de sous-titre dans
`aircraft_admin_screen_test.dart` (« · carburant inconnu » ajouté).

- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze` :
  tout passe.

- [ ] **Step 5 : commit**

```bash
git add lib test
git commit -m "feat(app): current fuel display and fuel log screen with estimated consumption (plan 7)"
```

---

### Task 7 : correction admin du carburant (app)

**Files:**
- Modify: `lib/features/flight/flight_screen.dart`
- Test: `test/features/flight/flight_screen_test.dart`

**Interfaces:**
- Consumes: `fuelError` (Task 4), `adminUpdateFlight` (Task 3 : clés
  `fuelStart`, `fuelAdded`, `fuelEnd`).
- Produces: clés `correct-fuel-start`, `correct-fuel-added`,
  `correct-fuel-end`.

- [ ] **Step 1 : tests qui échouent** (reprendre la mise en place du test
  de correction admin d'un vol clôturé existant, `admin-correct`) :

```dart
  testWidgets('correction admin : carburant pré-rempli et envoyé', (tester) async {
    // vol clôturé avec fuelStart 40, fuelAdded 20, fuelEnd 35 ; admin
    await tester.tap(find.byKey(const Key('admin-correct')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('correct-fuel-end'))).controller!.text, '35');
    await tester.enterText(find.byKey(const Key('correct-fuel-end')), '22');
    await tester.tap(find.byKey(const Key('admin-save-correction')));
    await tester.pumpAndSettle();
    final p = finance.adminUpdated.values.single;
    expect([p['fuelStart'], p['fuelAdded'], p['fuelEnd']], [40, 20, 22]);
  });

  testWidgets('correction admin d\'un vol sans carburant : champs vides, rien envoyé', (tester) async {
    // vol clôturé sans valeurs carburant (avant le plan 7)
    await tester.tap(find.byKey(const Key('admin-correct')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-save-correction')));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated.values.single.containsKey('fuelEnd'), isFalse);
  });

  testWidgets('correction admin : carburant partiel ou hors bornes refusé', (tester) async {
    // vol clôturé sans valeurs carburant
    await tester.tap(find.byKey(const Key('admin-correct')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('correct-fuel-end')), '150');
    await tester.tap(find.byKey(const Key('admin-save-correction')));
    await tester.pumpAndSettle();
    expect(find.text('Carburant au départ invalide (0 à 100 L).'), findsOneWidget);
    expect(finance.adminUpdated, isEmpty);
  });
```

- [ ] **Step 2 : vérifier l'échec** — `fvm flutter test test/features/flight/flight_screen_test.dart` : échec.

- [ ] **Step 3 : implémenter** dans `flight_screen.dart` :
  - trois contrôleurs `_correctFuelStart`, `_correctFuelAdded`,
    `_correctFuelEnd`, pré-remplis dans `initState` avec
    `f.fuelStartLiters?.toString() ?? ''` (idem ajouté, rangé), libérés dans
    `dispose` ;
  - getter `bool get _correctFuelFilled` : au moins un des trois champs non
    vide ;
  - dans `_correctionError`, branche `f.isClosed`, après les atterrissages :

```dart
      if (_correctFuelFilled) {
        final err = fuelError(
          start: int.tryParse(_correctFuelStart.text.trim()),
          added: int.tryParse(_correctFuelAdded.text.trim()),
          end: int.tryParse(_correctFuelEnd.text.trim()),
        );
        if (err != null) return err;
      }
```

  - dans `_correctionPayload`, après les atterrissages :

```dart
    if (_correctFuelFilled) {
      payload['fuelStart'] = int.parse(_correctFuelStart.text.trim());
      payload['fuelAdded'] = int.parse(_correctFuelAdded.text.trim());
      payload['fuelEnd'] = int.parse(_correctFuelEnd.text.trim());
    }
```

  - dans le bloc « Clôture » de la correction, après les amerrissages, trois
    `TextField` (clés ci-dessus, libellés « Carburant au départ (L) »,
    « Carburant ajouté (L) », « Carburant à bord, appareil rangé (L) »,
    clavier numérique).

- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze` :
  tout passe.

- [ ] **Step 5 : commit**

```bash
git add lib/features/flight/flight_screen.dart test/features/flight/flight_screen_test.dart
git commit -m "feat(app): admin fuel correction on closed flights (plan 7)"
```

---

### Task 8 : docs, vérification complète, déploiement dev

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1 : vérification complète**

```bash
fvm flutter test && fvm flutter analyze
cd functions && npm test
cd functions && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int
```

Attendu : tout passe, `analyze` sans problème.

- [ ] **Step 2 : `CLAUDE.md`**
  - Documents de référence : ajouter « Plan 7, suivi carburant (terminé) :
    `docs/superpowers/plans/2026-10-02-ulmgap-07-carburant.md` ».
  - Section prod : `closeFlight` exige désormais les champs carburant ;
    déployer `closeFlight` et `adminUpdateFlight` **avec** l'app web. Aucune
    règle ni index nouveau.
  - Section dev : `closeFlight` et `adminUpdateFlight` redéployées (plan 7).

- [ ] **Step 3 : déploiement dev** (jamais prod)

```bash
cd functions && npm run build && npx firebase deploy --only functions:closeFlight,functions:adminUpdateFlight --project dev
```

(Noms exportés dans `functions/src/index.ts` : `closeFlight`,
`adminUpdateFlight` ; alias `dev` = `ulmgap-dev` dans `.firebaserc`.)

- [ ] **Step 4 : commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md, plan 7 (fuel tracking) done, deploy notes"
```
