# UlmGap, plan 12 : vol technique

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** un vol au profit de l'association (« Vol technique », motif
obligatoire) n'est facturé à personne : ni compte, ni caisse (spec §12).

**Architecture :** calqué sur le baptême (plans 8-9) : drapeau dans
`FlightInput` (`technical`, `technicalReason`), mode de tarification
`technical` imposé par `planFlight`, branche dédiée dans `closingBill`
(miroir Dart, cas partagés `test/fixtures/pricing_cases.json`),
`billedTo: "association"`. La régularisation existante (`adjustments`) ne
touche que `billedTo: "account"` : passer un vol clôturé en technique
rembourse donc le payeur sans code nouveau.

**Tech Stack :** inchangée.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §12
(révision du 2026-10-14), plus §4.3-§4.5, §10.

**Branche :** `feature/vol-technique` (déjà créée depuis `main`).

## Global Constraints

- Toujours `fvm flutter` / `fvm dart`. TDD. Textes en français. Jamais de
  déploiement en prod.
- Champs du vol : `technical` (bool, défaut `false`), `technicalReason`
  (string, obligatoire si `technical`, 80 caractères au maximum, `null`
  sinon). `pricingMode: "technical"`, prioritaire sur `standard`,
  `fuel_only`, `baptism` ; `custom` impossible.
- Clôture d'un vol technique : `billedAmount: 0`, `billedTo:
  "association"`, aucun mouvement de compte ni de caisse, aucun crédit
  d'instruction.
- Messages serveur (exacts) :
  - « Vol technique : réservé aux instructeurs et aux admins. »
    (`permission-denied`) ;
  - « Motif du vol technique obligatoire. » ;
  - « Vol technique : incompatible avec un vol d'instruction. » ;
  - « Vol technique : incompatible avec un baptême de l'air. » ;
  - « Aucun montant pour un vol technique. ».
- Libellés app : case « Vol technique », champ « Motif (obligatoire) »,
  mode « Vol technique », fiche « Vol technique — <motif> », aperçu et
  résumé de clôture « Vol technique : non facturé (association) »,
  payeur du relevé « association », total « Vols techniques : N vols,
  <durée> », marque « T » (bulle « Vol technique ») au suivi carburant.
- Pas de contrôle de crédit pour un vol technique. Matrice, conflits,
  amphibie : inchangés. Ni règle Firestore, ni index, ni contrat du pont.
- Tests : `fvm flutter test && fvm flutter analyze` ; `cd functions && npm
  test` ; intégration : `cd functions && JAVA_HOME=/opt/android-studio/jbr
  PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int` (juger sur
  `# fail` / `not ok`). Un fichier d'intégration qui touche la caisse
  appelle `resetCashbox` en `beforeEach` **et** `afterEach`.

## Review Focus

- **Correction admin d'un vol clôturé standard → technique** : le payeur
  est remboursé (`flight_adjustment` +montant), `billedTo` devient
  `association`, aucune ligne de caisse. → test Task 2.
- **Correction inverse (technique → standard)** : le payeur est débité du
  coût calculé, crédit disponible non contrôlé (vol clôturé). → test Task 2.
- **Créateur lâché d'un vol devenu technique à la validation** : sa
  modification garde la case ; un lâché qui coche la case sur son propre
  vol est refusé. → tests Task 2.
- **Vol technique avec un passager sans compte** : accepté, non facturé ;
  la case « Montant différent » n'apparaît pas à la clôture. → tests
  Tasks 1 et 4.
- **Compte du pilote à 0 FCFA** : un vol technique se crée (aucun contrôle
  de crédit). → test Task 2.

---

### Task 1 : règles pures (TypeScript + miroir Dart + cas partagés)

**Files:**
- Modify: `functions/src/rules/flights.ts:7` (`PricingMode`)
- Modify: `functions/src/rules/pricing.ts` (`closingBill`, types `billedTo`)
- Modify: `functions/src/flights/validation.ts` (`FlightInput`, `ReviewChanges`, `validateFlightInput`, `validateReviewChanges`)
- Modify: `lib/core/pricing.dart` (`closingBill`)
- Modify: `test/fixtures/pricing_cases.json` (section `closing`)
- Test: `functions/src/flights/validation.test.ts`, `functions/src/rules/pricing.test.ts` (fixtures), `test/core/pricing_test.dart` (fixtures)

**Interfaces:**
- Produces :
  - `PricingMode = "standard" | "fuel_only" | "custom" | "baptism" | "technical"`
  - `type BilledTo = "account" | "off_app" | "association"` exporté de `rules/pricing.ts`
  - `closingBill({ mode: "standard" | "fuel_only" | "baptism" | "technical", ... })` →
    pour `technical` : `{ billedAmount: 0, billedTo: "association", pricingMode: "technical" }`,
    et `Error("Aucun montant pour un vol technique.")` si `shortFlightAmount` ou `customAmount` non nul.
  - `FlightInput` : `technical: boolean; technicalReason: string | null`
  - `ReviewChanges` : `technical?: boolean; technicalReason?: string`
  - Dart `closingBill(mode: 'technical', …)` : même résultat, `ArgumentError` même message.

- [ ] **Step 1 : cas partagés qui échouent** — ajouter à `closing` dans `test/fixtures/pricing_cases.json` :

```json
    { "name": "vol technique 90 min : non facturé (association)", "mode": "technical", "actualMinutes": 90,
      "category": "EXT", "hasPassenger": true,
      "expected": { "billedAmount": 0, "billedTo": "association", "pricingMode": "technical" } },
    { "name": "vol technique 30 min : non facturé, aucun montant requis", "mode": "technical", "actualMinutes": 30,
      "category": "GAP", "hasPassenger": false,
      "expected": { "billedAmount": 0, "billedTo": "association", "pricingMode": "technical" } },
    { "name": "vol technique avec montant différent : refus", "mode": "technical", "actualMinutes": 60,
      "category": "GAP", "hasPassenger": true, "customAmount": 9000,
      "expectedError": "Aucun montant pour un vol technique." },
    { "name": "vol technique avec montant à facturer : refus", "mode": "technical", "actualMinutes": 30,
      "category": "GAP", "hasPassenger": false, "shortFlightAmount": 5000,
      "expectedError": "Aucun montant pour un vol technique." }
```

(Vérifier que la boucle Dart de `test/core/pricing_test.dart` gère
`expectedError` comme la boucle TS ; sinon l'ajouter, même forme.)

Dans `functions/src/flights/validation.test.ts`, ajouter :

```ts
test("validateFlightInput : vol technique, motif obligatoire et nettoyé", () => {
  const base = { start: 1_000_000, end: 1_000_000 + 3_600_000, destination: "Lomé", aircraftId: "a1", crew: ["u1"] };
  const v = validateFlightInput({ ...base, technical: true, technicalReason: " Convoyage Wonga-Wongué " });
  assert.equal(v.technical, true);
  assert.equal(v.technicalReason, "Convoyage Wonga-Wongué");
  const plain = validateFlightInput(base);
  assert.equal(plain.technical, false);
  assert.equal(plain.technicalReason, null);
  // Motif ignoré sans la case.
  assert.equal(validateFlightInput({ ...base, technicalReason: "x" }).technicalReason, null);
  assert.throws(() => validateFlightInput({ ...base, technical: true }),
    (e) => e instanceof ValidationError && e.message === "Motif du vol technique obligatoire.");
  assert.throws(() => validateFlightInput({ ...base, technical: true, technicalReason: "x".repeat(81) }), ValidationError);
});

test("validateFlightInput : vol technique incompatible avec instruction et baptême ; passager accepté", () => {
  const base = {
    start: 1_000_000, end: 1_000_000 + 3_600_000, destination: "Lomé", aircraftId: "a1", crew: ["u1"],
    technical: true, technicalReason: "Essai moteur",
  };
  assert.throws(() => validateFlightInput({ ...base, instruction: true }),
    (e) => e instanceof ValidationError && e.message === "Vol technique : incompatible avec un vol d'instruction.");
  assert.throws(() => validateFlightInput({ ...base, passengers: ["Mécano"], baptism: true, baptismTier: "local" }),
    (e) => e instanceof ValidationError && e.message === "Vol technique : incompatible avec un baptême de l'air.");
  assert.equal(validateFlightInput({ ...base, passengers: ["Mécano"] }).passengers.length, 1);
});

test("validateReviewChanges : technical et technicalReason facultatifs", () => {
  const r = validateReviewChanges({ flightId: "f1", technical: true, technicalReason: " Convoyage " });
  assert.equal(r.changes.technical, true);
  assert.equal(r.changes.technicalReason, "Convoyage");
  assert.equal(validateReviewChanges({ flightId: "f1" }).changes.technical, undefined);
});
```

(Importer `validateReviewChanges` si absent ; adapter le nom de l'objet
rendu si `validateReviewChanges` ne rend pas `{ flightId, changes }` — il
le rend aujourd'hui, cf. `flights/actions.ts:34`.)

- [ ] **Step 2 : échec attendu** — `cd functions && npm test` et
  `fvm flutter test test/core/pricing_test.dart` : FAIL (mode inconnu,
  champs absents).

- [ ] **Step 3 : implémentation TypeScript**

`rules/flights.ts:7` :

```ts
export type PricingMode = "standard" | "fuel_only" | "custom" | "baptism" | "technical";
```

`rules/pricing.ts` : exporter `export type BilledTo = "account" | "off_app" | "association";`,
l'utiliser dans le type de retour de `closingBill` et dans les paramètres
de `adjustments` (`billedTo: BilledTo | null`), élargir `mode` à
`"standard" | "fuel_only" | "baptism" | "technical"` et `pricingMode` du
retour à `PricingMode` (importé de `./flights` — vérifier l'absence de
cycle : `flights.ts` n'importe pas `pricing.ts`), et ajouter en tête de
`closingBill` :

```ts
  // Spec §12.2 : vol technique, à la charge de l'association, jamais de montant saisi.
  if (a.mode === "technical") {
    if (a.shortFlightAmount != null || a.customAmount != null) {
      throw new Error("Aucun montant pour un vol technique.");
    }
    return { billedAmount: 0, billedTo: "association", pricingMode: "technical" };
  }
```

`flights/validation.ts` : ajouter à `FlightInput` :

```ts
  /** Spec §12 : vol au profit de l'association. */
  technical: boolean;
  /** Obligatoire si `technical`, sinon null. */
  technicalReason: string | null;
```

à `ReviewChanges` : `technical?: boolean; technicalReason?: string;`, et la
fonction :

```ts
export function technicalReason(v: unknown): string {
  const s = typeof v === "string" ? v.trim() : "";
  if (!s) throw new ValidationError("Motif du vol technique obligatoire.");
  if (s.length > 80) throw new ValidationError("Motif du vol technique trop long (80 caractères au maximum).");
  return s;
}
```

Dans `validateFlightInput`, ajouter au littéral `out` :
`technical: bool(d.technical, "Vol technique", false), technicalReason: null,`
puis, après le bloc baptême :

```ts
  if (out.technical) {
    out.technicalReason = technicalReason(d.technicalReason);
    if (out.instruction) throw new ValidationError("Vol technique : incompatible avec un vol d'instruction.");
    if (out.baptism) throw new ValidationError("Vol technique : incompatible avec un baptême de l'air.");
  }
```

Dans `validateReviewChanges` (à côté de `baptism`) :

```ts
  if (c.technical !== undefined) changes.technical = bool(c.technical, "Vol technique", false);
  if (c.technicalReason != null) changes.technicalReason = technicalReason(c.technicalReason);
```

Corriger la compilation des littéraux `FlightInput` existants
(`flights/actions.ts:41-53` notamment) en ajoutant
`technical: false, technicalReason: null` — la Task 2 y branchera la
logique.

- [ ] **Step 4 : miroir Dart** (`lib/core/pricing.dart`, en tête de `closingBill`)

```dart
  // Spec §12.2 : vol technique, à la charge de l'association.
  if (mode == 'technical') {
    if (shortFlightAmount != null || customAmount != null) {
      throw ArgumentError('Aucun montant pour un vol technique.');
    }
    return (billedAmount: 0, billedTo: 'association', pricingMode: 'technical');
  }
```

et mettre à jour le commentaire du typedef `BillLeg` (`'association'`
possible).

- [ ] **Step 5 : succès** — `cd functions && npm test` et `fvm flutter test && fvm flutter analyze`.

- [ ] **Step 6 : commit**

```bash
git add functions/src lib/core/pricing.dart test/fixtures/pricing_cases.json test/core/pricing_test.dart
git commit -m "feat: technical flight pure rules (mode, closing bill, validation)"
```

---

### Task 2 : Functions (planification, validation, clôture, correction admin)

**Files:**
- Modify: `functions/src/flights/core.ts` (`planFlight`, `PlanArgs`)
- Modify: `functions/src/flights/edit.ts` (`createFlight`, `updateFlight`)
- Modify: `functions/src/flights/actions.ts` (`validateFlight`)
- Modify: `functions/src/flights/close.ts`
- Modify: `functions/src/flights/admin-edit.ts`
- Test: `functions/src/flights/technical.int.test.ts` (nouveau)

**Interfaces:**
- Consumes : Task 1.
- Produces : `PlanArgs.mayMarkTechnical: boolean` (obligatoire) ;
  champs écrits par `planFlight` : `pricingMode: "technical"`,
  `technicalReason: string | null`, `technical: boolean`.

Règles à implémenter :
1. `planFlight` : si `a.input.technical && !a.mayMarkTechnical &&
   a.previousMode !== "technical"` → `HttpsError("permission-denied",
   "Vol technique : réservé aux instructeurs et aux admins.")`.
   `pricingMode = a.input.technical ? "technical" : a.input.baptism ?
   "baptism" : …` (inchangé ensuite). Contrôle de crédit sauté aussi pour
   `technical`. `fields` : `technical: a.input.technical`,
   `technicalReason: a.input.technical ? a.input.technicalReason : null`.
2. `createFlight` / `updateFlight` : passer `mayMarkTechnical:
   mayChoose(me)` ; `updateFlight` passe déjà `previousMode` (sinon
   l'ajouter : `f.get("pricingMode")`).
3. `validateFlight` (validateur = instructeur désigné ou admin) :
   `mayMarkTechnical: true` ; dans le littéral `input`,
   `technical: changes.technical ?? (f.get("pricingMode") === "technical")`,
   `technicalReason: changes.technicalReason ??
   (f.get("technicalReason") as string | null | undefined) ?? null` ; si
   `input.technical` et motif null → `invalid-argument` « Motif du vol
   technique obligatoire. ». Les incompatibilités (instruction, baptême)
   se vérifient comme dans `validateFlightInput` (même messages,
   `invalid-argument`) : extraire une fonction pure
   `checkTechnical(input: FlightInput): void` dans `validation.ts`,
   appelée par `validateFlightInput` et par `validateFlight`.
4. `closeFlight` : `mode` lu du vol peut valoir `"technical"` ; aucun
   crédit d'instruction pour un vol technique (`instruction` est forcément
   faux, mais forcer `instruction: false` dans l'appel à
   `instructionCreditDue` si `pricingMode === "technical"`) ; aucun
   mouvement quand `bill.billedTo !== "account"` (déjà le cas) ;
   `customAmount`/`shortFlightAmount` écrits tels quels (nuls).
5. `adminUpdateFlight` : `mayMarkTechnical: true` ; `mode` :
   `v.input.technical || v.input.baptism ? undefined : …` ; `billMode`
   élargi à `"technical"` ; `shortFlightAmount` stocké `null` pour un vol
   technique (comme le baptême) ; pour un vol technique, passer
   `customAmount: null` et `shortFlightAmount: null` à `closingBill` et
   stocker `customAmount: null` (un ancien montant différent ne survit
   pas au passage en technique) ; refuser `v.pricingMode` ou
   `v.customAmount` explicitement fournis avec `v.input.technical` :
   `invalid-argument` « Aucun montant pour un vol technique. ».
   `BilledTo` local remplacé par le type exporté de `rules/pricing.ts`.
6. `adminDeleteFlight` : rien à changer (rembourse seulement
   `billedTo === "account"`).

- [ ] **Step 1 : tests qui échouent** — `functions/src/flights/technical.int.test.ts`

```ts
// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Vol technique (spec §12) : droits, aucun contrôle de crédit, clôture non
// facturée, régularisation par correction admin, aucune ligne de caisse.
import { afterEach, beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import { at, code, db, draft, FUEL, H, resetCashbox, seedAircraft, seedFlight, seedUser } from "./testkit";
import { createFlight, updateFlight } from "./edit";
import { validateFlight } from "./actions";
import { closeFlight } from "./close";
import { adminUpdateFlight } from "./admin-edit";

beforeEach(resetCashbox);
afterEach(resetCashbox);

const flight = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;
const balance = async (uid: string) => (await db.collection("users").doc(uid).get()).get("balance") as number;
const txs = async (uid: string) =>
  (await db.collection("transactions").where("userUid", "==", uid).get()).docs.map((d) => d.data());
const cashLines = async () => (await db.collection("cashMovements").get()).size;
const TECH = { technical: true, technicalReason: "Convoyage Wonga-Wongué" };

test("instructeur : vol technique créé valide, sans contrôle de crédit (solde 0)", async () => {
  const instr = await seedUser({ profile: "instructeur", balance: 0 });
  const ac = await seedAircraft();
  const r = await createFlight(instr, draft(ac, [instr.uid], TECH));
  assert.equal(r.status, "valide");
  const f = await flight(r.id);
  assert.equal(f.pricingMode, "technical");
  assert.equal(f.technical, true);
  assert.equal(f.technicalReason, "Convoyage Wonga-Wongué");
});

test("lâché : cocher Vol technique est refusé", async () => {
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const ac = await seedAircraft();
  await assert.rejects(createFlight(lache, draft(ac, [lache.uid], TECH)),
    (e) => code(e) === "permission-denied" &&
      (e as Error).message === "Vol technique : réservé aux instructeurs et aux admins.");
});

test("vol devenu technique à la validation : le créateur lâché le modifie sans perdre la case", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const ac = await seedAircraft();
  // Demande d'un lâché avec un instructeur dans l'équipage.
  const lacheRich = await seedUser({ profile: "lache_toute_mission" });
  const r = await createFlight(lacheRich, draft(ac, [lacheRich.uid, instr.uid]));
  assert.equal(r.status, "demande");
  await validateFlight(instr, { flightId: r.id, ...TECH });
  assert.equal((await flight(r.id)).pricingMode, "technical");
  await updateFlight(lacheRich, { flightId: r.id, ...draft(ac, [lacheRich.uid, instr.uid], { ...TECH, destination: "Port-Gentil" }) });
  const f = await flight(r.id);
  assert.equal(f.pricingMode, "technical");
  assert.equal(f.destination, "Port-Gentil"); // redevenue demande (§3.3), toujours technique
});

test("vol technique avec un passager sans compte : accepté", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const ac = await seedAircraft();
  const r = await createFlight(instr, draft(ac, [instr.uid], { ...TECH, passengers: ["Mécano"] }));
  assert.equal((await flight(r.id)).pricingMode, "technical");
});

test("clôture d'un vol technique : 0, association, aucun mouvement de compte ni de caisse", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 50_000 });
  const ac = await seedAircraft();
  const id = await seedFlight({
    start: Date.now() - 2 * H, end: Date.now() - H, crew: [pilot.uid], aircraftId: ac,
    pricingMode: "technical", technical: true, technicalReason: "Essai moteur",
  });
  const r = await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 90, landings: 1 });
  assert.deepEqual(r, { billedAmount: 0, billedTo: "association" });
  assert.equal(await balance(pilot.uid), 50_000);
  assert.equal((await txs(pilot.uid)).length, 0);
  assert.equal(await cashLines(), 0);
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 90, landings: 1 }),
    (e) => code(e) === "failed-precondition"); // déjà clôturé
});

test("clôture d'un vol technique avec un montant : refus", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const ac = await seedAircraft();
  const id = await seedFlight({
    start: Date.now() - 2 * H, end: Date.now() - H, crew: [pilot.uid], aircraftId: ac,
    passengers: ["Mécano"], pricingMode: "technical", technical: true, technicalReason: "Essai",
  });
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, customAmount: 9_000 }),
    (e) => code(e) === "invalid-argument" && (e as Error).message === "Aucun montant pour un vol technique.");
});

test("correction admin : vol clôturé standard → technique rembourse le payeur ; l'inverse le débite", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP", balance: 100_000 });
  const ac = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedFlight({ start, end: start + H, crew: [pilot.uid], aircraftId: ac, pricingMode: "standard" });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1 });
  assert.equal(await balance(pilot.uid), 88_000); // GAP 60 min = 12 000

  const body = { flightId: id, start, end: start + H, destination: "Lomé", aircraftId: ac, crew: [pilot.uid] };
  await adminUpdateFlight(admin1, { ...body, ...TECH });
  let f = await flight(id);
  assert.equal(f.pricingMode, "technical");
  assert.equal(f.billedTo, "association");
  assert.equal(f.billedAmount, 0);
  assert.equal(await balance(pilot.uid), 100_000);
  assert.ok((await txs(pilot.uid)).some((t) => t.type === "flight_adjustment" && t.amount === 12_000));

  await adminUpdateFlight(admin1, body);
  f = await flight(id);
  assert.equal(f.pricingMode, "standard");
  assert.equal(f.billedTo, "account");
  assert.equal(await balance(pilot.uid), 88_000);
  assert.equal(await cashLines(), 0);
});

test("recette « ww » : vol passé non clôturé corrigé en technique par un admin, puis clôturé", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const ac = await seedAircraft();
  const start = Date.now() - 5 * H;
  const id = await seedFlight({ start, end: start + 2 * H, crew: [pilot.uid], aircraftId: ac, pricingMode: "standard" });
  await adminUpdateFlight(admin1, {
    flightId: id, start, end: start + 2 * H, destination: "Wonga-Wongué", aircraftId: ac, crew: [pilot.uid], ...TECH,
  });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 120, landings: 2 });
  assert.equal(await balance(pilot.uid), 0);
  assert.equal((await flight(id)).billedTo, "association");
  assert.equal(await cashLines(), 0);
});
```

`draft(ac, crew, o)` place `o`
après les champs par défaut : `{ ...TECH, destination }` écrase bien la
destination.

- [ ] **Step 2 : échec attendu** — intégration : `not ok` sur ces tests
  (mode `standard` écrit, crédit contrôlé, etc.).

- [ ] **Step 3 : implémentation** — règles 1 à 6 ci-dessus.

- [ ] **Step 4 : succès** — `cd functions && npm test` puis intégration
  complète : aucun `not ok` (anciens tests de vol, baptême, instruction,
  correction admin compris).

- [ ] **Step 5 : commit**

```bash
git add functions/src
git commit -m "feat(functions): technical flights (no credit check, unbilled closing, admin regularization)"
```

---

### Task 3 : app, données et libellés

**Files:**
- Modify: `lib/data/flight.dart` (`Flight`, `FlightDraft`)
- Modify: `lib/features/flight/flight_texts.dart`
- Test: `test/data/flight_test.dart`, `test/features/flight/flight_texts_test.dart`

**Interfaces:**
- Produces :
  - `Flight.technical` (bool, lu de `m['technical'] == true || pricingMode == 'technical'`), `Flight.technicalReason` (String?), getter `bool get isTechnical => pricingMode == 'technical';`
  - `FlightDraft({…, bool technical = false, String? technicalReason})` ; `toPayload()` envoie toujours `'technical'` et `'technicalReason': technical ? technicalReason?.trim() : null`.
  - `pricingModeLabel('technical') == 'Vol technique'` ; `flightPricingLabel('technical', null) == 'Vol technique'`.
  - `const technicalUnbilledText = 'Vol technique : non facturé (association)';`
  - `String technicalTitle(String? reason) => reason == null || reason.isEmpty ? 'Vol technique' : 'Vol technique — $reason';`
  - `billedToLabel` (ou équivalent existant) : `'association'` → `'association'`.

- [ ] **Step 1 : tests qui échouent**

`test/data/flight_test.dart` :

```dart
  test('vol technique : champs lus et payload', () {
    final f = Flight.fromMap('f1', {
      ...baseMap, // reprendre la carte minimale déjà utilisée dans ce fichier
      'pricingMode': 'technical', 'technical': true, 'technicalReason': 'Essai moteur',
      'billedTo': 'association',
    });
    expect(f.isTechnical, isTrue);
    expect(f.technicalReason, 'Essai moteur');
    final p = FlightDraft(
      start: DateTime(2026, 10, 20, 9), end: DateTime(2026, 10, 20, 10), destination: 'Lomé',
      aircraftId: 'a1', crew: const ['u1'], passengers: const [],
      technical: true, technicalReason: ' Convoyage ',
    ).toPayload();
    expect(p['technical'], isTrue);
    expect(p['technicalReason'], 'Convoyage');
    final q = FlightDraft(
      start: DateTime(2026, 10, 20, 9), end: DateTime(2026, 10, 20, 10), destination: 'Lomé',
      aircraftId: 'a1', crew: const ['u1'], passengers: const [], technicalReason: 'x',
    ).toPayload();
    expect(q['technical'], isFalse);
    expect(q['technicalReason'], isNull);
  });
```

(Adapter `baseMap` à la carte minimale existante du fichier.)

`test/features/flight/flight_texts_test.dart` :

```dart
  test('vol technique : libellés', () {
    expect(pricingModeLabel('technical'), 'Vol technique');
    expect(flightPricingLabel('technical', null), 'Vol technique');
    expect(technicalTitle('Essai moteur'), 'Vol technique — Essai moteur');
    expect(technicalTitle(null), 'Vol technique');
    expect(technicalUnbilledText, 'Vol technique : non facturé (association)');
  });
```

- [ ] **Step 2 : échec attendu** — `fvm flutter test test/data/flight_test.dart test/features/flight/flight_texts_test.dart`.

- [ ] **Step 3 : implémentation** — selon les Interfaces ci-dessus, en
  suivant le modèle des champs baptême (`baptismTier`, `isBaptism`).

- [ ] **Step 4 : succès** — `fvm flutter test && fvm flutter analyze`.

- [ ] **Step 5 : commit**

```bash
git add lib/data/flight.dart lib/features/flight/flight_texts.dart test
git commit -m "feat(app): technical flight data and labels"
```

---

### Task 4 : app, écrans (formulaire, fiche, clôture, relevé, suivi carburant)

**Files:**
- Modify: `lib/features/flight/flight_screen.dart` (formulaire, aperçu, fiche)
- Modify: `lib/features/flight/closing_dialog.dart`
- Modify: `lib/features/admin/billing_report_screen.dart` (tableau, totaux, CSV)
- Modify: `lib/features/fuel/fuel_log_screen.dart`
- Test: `test/features/flight/flight_screen_test.dart`, `test/features/flight/closing_dialog_test.dart`, `test/features/admin/billing_report_screen_test.dart`, `test/features/fuel/fuel_log_screen_test.dart`

**Interfaces:**
- Consumes : Task 3 (`Flight.isTechnical`, `technicalReason`, `FlightDraft.technical/technicalReason`, `technicalTitle`, `technicalUnbilledText`, `flightPricingLabel`), Task 1 (`closingBill` Dart `technical`).

Comportement attendu (spec §12) :
1. **Formulaire** (création, modification, validation, correction admin) :
   - case `CheckboxListTile` « Vol technique » (clé `Key('technical')`),
     visible si l'utilisateur connecté est instructeur ou admin, **ou** si
     le vol édité est déjà technique (créateur lâché, case conservée) ;
   - cochée : champ « Motif (obligatoire) » (clé `Key('technical-reason')`,
     80 caractères au maximum) ; l'enregistrement est bloqué avec
     « Motif du vol technique obligatoire. » si le motif est vide ;
   - cochée : la case « Vol d'instruction » et la case « Carburant
     seulement » sont masquées (et décochées) ; l'option « Baptême de
     l'air » de la fenêtre « Ajouter un passager sans compte » est
     masquée ; un baptême déjà saisi est retiré quand on coche la case ;
   - l'aperçu affiche `technicalUnbilledText` à la place du coût estimé et
     du crédit disponible ; aucun blocage pour crédit insuffisant ;
   - le `FlightDraft` envoyé porte `technical` et `technicalReason`.
2. **Fiche du vol** : ligne `technicalTitle(flight.technicalReason)` à la
   place de la tarification ; sur un vol clôturé technique, le résumé de
   facturation affiche `technicalUnbilledText`.
3. **Dialogue de clôture** : pour un vol technique, ni « Montant à
   facturer » (même sous 45 min) ni case « Montant différent » (même avec
   un passager) ; le montant affiché est `technicalUnbilledText` ; l'appel
   à `closeFlight` n'envoie aucun montant.
4. **Relevé des vols facturés** : mode `flightPricingLabel` («
   Vol technique »), montant 0, colonne payeur « association » ; une ligne
   de total supplémentaire « Vols techniques : N vols, <durée> » (durée au
   format déjà utilisé par le relevé pour le temps de vol, sur
   `actualFlightMinutes`) ; les vols techniques ne comptent ni dans
   « débité sur comptes » ni dans « facturé hors app » ; export CSV :
   même mode, payeur « association ».
5. **Suivi carburant** : sur la ligne d'un vol technique, une marque « T »
   (petit `Container`/`Chip` à côté de la date) avec `Tooltip` « Vol
   technique ».

- [ ] **Step 1 : tests qui échouent** (un par point, dans les fichiers de test listés ; reprendre les mises en place existantes de chaque fichier) :
  - formulaire, instructeur : la case `Key('technical')` est présente ;
    cochée sans motif → « Motif du vol technique obligatoire. » et aucun
    appel ; avec motif → `FakeFlightApi` reçoit un draft `technical: true`,
    `technicalReason: 'Convoyage'` ; la case « Vol d'instruction » n'est
    plus affichée ; l'aperçu contient « Vol technique : non facturé
    (association) » ;
  - formulaire, lâché : pas de case `Key('technical')` sur un vol neuf ;
    case présente et cochée sur un vol existant `pricingMode: 'technical'` ;
  - fiche : « Vol technique — Essai moteur » ;
  - clôture : vol technique de 30 min avec un passager → ni
    « Montant à facturer » ni « Montant différent » ; « Vol technique :
    non facturé (association) » affiché ; `FakeFinanceApi.closed.single`
    sans `customAmount` ni `shortFlightAmount` ;
  - relevé : une ligne « Vol technique », payeur « association », total
    « Vols techniques : 1 vol… » (adapter le pluriel : « 1 vol », « 2 vols ») ;
    les totaux « débité sur comptes » / « facturé hors app » n'incluent pas
    le vol technique ;
  - suivi carburant : `find.byTooltip('Vol technique')` trouve la marque
    sur la ligne du vol technique, et rien sur un vol standard.
- [ ] **Step 2 : échec attendu** — les tests ci-dessus échouent.
- [ ] **Step 3 : implémentation** — points 1 à 5.
- [ ] **Step 4 : succès** — `fvm flutter test && fvm flutter analyze`.
- [ ] **Step 5 : commit**

```bash
git add lib test
git commit -m "feat(app): technical flight in form, flight sheet, closing, billing report and fuel log"
```

---

### Task 5 : docs, vérification complète, déploiement dev

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1 : vérification complète** — les quatre suites (Flutter
  test, analyze, Functions unitaires, intégration) : tout vert.
- [ ] **Step 2 : `CLAUDE.md`** : plan 12 dans « Documents de référence »
  (`docs/superpowers/plans/2026-10-14-ulmgap-12-vol-technique.md`, spec
  §12) ; « État » : plan 12 sur la branche `feature/vol-technique`,
  Functions `createFlight`, `updateFlight`, `validateFlight`,
  `closeFlight`, `adminUpdateFlight` à redéployer en dev, app de dev à
  reconstruire ; recette « vol ww » (spec §12.4). Liste prod : ces
  Functions avec l'app web ; tout build installé antérieur au plan 12 ne
  sait ni afficher ni clôturer un vol technique.
- [ ] **Step 3 : commit**

```bash
git add CLAUDE.md
git commit -m "docs: plan 12 (technical flight) state and deployment notes"
```

- [ ] **Step 4 : déploiement dev** (contrôleur, après la revue finale ; jamais prod)

```bash
firebase deploy --project dev --only functions:createFlight,functions:updateFlight,functions:validateFlight,functions:closeFlight,functions:adminUpdateFlight
```
