# UlmGap, plan 8 : crédit instruction et baptême de l'air

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** créditer l'instructeur de 20 000 FCFA (réglable) pour chaque vol
d'instruction clôturé d'au moins 45 min, visible seulement dans son
historique de compte ; facturer hors app 70 000 FCFA (réglable) tout vol
« baptême de l'air ».

**Architecture :** comme aux plans 3, 4b et 7.
- Règles pures dans `functions/src/rules/` (miroir Dart dans `lib/core/`),
  écritures uniquement par les callables `createFlight`, `updateFlight`,
  `validateFlight`, `closeFlight`, `adminUpdateFlight`, `adminDeleteFlight`,
  `adminUpdatePricing`.
- Le crédit instruction est une transaction `instruction` écrite par
  `postMovement` dans la même transaction Firestore que la clôture ou la
  correction (règle absolue).

**Tech Stack :** inchangée.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §10 (et
§2.4, §2.5, §2.6, §4.3). Déjà à jour (commit `e5dd4d3`).

**Branche :** `feature/instruction-bapteme`, créée depuis `main`.

## Global Constraints

- Toujours `fvm flutter` / `fvm dart`, jamais `flutter` nu.
- Montants par défaut : `instructionCredit` = **20 000**, `baptismFee` =
  **70 000** (FCFA), dans `settings/pricing`, figés dans `pricingSnapshot` ;
  un snapshot sans ces champs prend les valeurs par défaut.
- Seuil du crédit instruction : `actualFlightMinutes` **≥ 45**.
- Vol d'instruction possible seulement avec **exactement un instructeur et
  un autre membre avec compte** dans `crew` (donc 2 membres avec compte, dont
  un seul de profil `instructeur`).
- Baptême : mode `baptism`, `billedTo: off_app`, montant `baptismFee` quelle
  que soit la durée, aucun débit de solde, aucun contrôle de crédit.
- Libellés et messages (exacts) :
  - transaction `instruction`, motif à la clôture : `Crédit instruction` ;
    motif en correction/suppression admin : `Régularisation crédit instruction` ;
  - refus serveur : `Vol d'instruction : il faut un instructeur et un autre membre avec compte.` ;
    `Baptême de l'air réservé à un vol avec un passager sans compte.` ;
  - interface : `Vol d'instruction`, `Baptême de l'air`,
    `Passager sans compte · Baptême de l'air`,
    `Baptême de l'air : 70 000 FCFA, facturé hors app` (montant formaté),
    `Crédit instruction`, mode `Baptême de l'air`.
- **Aucune mention du crédit instruction** à la clôture, dans l'aperçu ou sur
  la fiche du vol : seulement dans l'historique du compte. La fiche dit
  « Vol d'instruction (XXX) ».
- Ni règle Firestore, ni index, ni champ du contrat du pont modifiés.
- TDD. Textes de l'interface en français. Ne jamais déployer en prod.
- Tests : `fvm flutter test && fvm flutter analyze` ; `cd functions && npm
  test` ; intégration : `cd functions && JAVA_HOME=/opt/android-studio/jbr
  PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int` (l'émulateur
  peut afficher « An unexpected error has occurred » en s'arrêtant et sortir
  en 2 sans `not ok` : juger sur `# fail` et `not ok`).

## Review Focus

1. **Seuil exact** : 45 min donne le crédit, 44 non (Task 1 et Task 3).
2. **Changement d'instructeur ou de durée en correction admin** : retrait chez
   l'ancien, crédit chez le nouveau, rien si inchangé (Task 4).
3. **Baptême sur un payeur sans crédit** : création acceptée (pas de
   contrôle de crédit), clôture sans débit (Task 2 et Task 3).
4. **Passager retiré** : le baptême disparaît et le mode est recalculé
   (Task 2 côté serveur, Task 6 côté app).
5. **Ancien snapshot de tarifs** (vol validé avant ce plan) : crédit et
   baptême aux valeurs par défaut (Task 1 et Task 3).

---

### Task 1 : règles pures et validation (serveur)

**Files:**
- Modify: `functions/src/rules/pricing.ts`, `functions/src/rules/pricing.test.ts`
- Modify: `functions/src/rules/flights.ts`, `functions/src/rules/flights.test.ts`
- Modify: `functions/src/finance/pricing-store.ts`, `functions/src/finance/validation.ts`
  (+ son test s'il existe : `functions/src/finance/validation.test.ts`)
- Modify: `functions/src/flights/validation.ts`, `functions/src/flights/validation.test.ts`

**Interfaces:**
- Produces:
  - `Pricing` gagne `instructionCredit: number`, `baptismFee: number` ;
    `DEFAULT_PRICING` : 20 000 et 70 000.
  - `pricingWithDefaults(p: Partial<Pricing> | null | undefined): Pricing`
    (fusion champ par champ sur `DEFAULT_PRICING`, cartes par catégorie
    comprises).
  - `INSTRUCTION_MIN_MINUTES = 45`.
  - `closingBill` accepte `mode: "standard" | "fuel_only" | "baptism"` ; en
    `baptism`, rend `{ billedAmount: pricing.baptismFee, billedTo: "off_app", pricingMode: "baptism" }`
    sans regarder durée, `shortFlightAmount` ni `customAmount`.
  - `instructionCreditDue(a: { instruction: boolean; actualMinutes: number; crew: Person[]; pricing: Pricing }): { uid: string; amount: number } | null`.
  - `instructionAdjustments(before: { uid: string | null; amount: number }, after: { uid: string | null; amount: number }): { uid: string; amount: number }[]`
    (+after à after.uid, −before à before.uid, regroupés par uid dans
    l'ordre d'apparition, montants nuls omis).
  - Dans `rules/flights.ts` : `PricingMode` gagne `"baptism"` ;
    `isInstructionEligible(crew: Person[]): boolean`.
  - `FlightInput` gagne `instruction: boolean` et `baptism: boolean`
    (défaut `false`, lus par `validateFlightInput`) ; `ReviewChanges` gagne
    `instruction?: boolean`, `baptism?: boolean`.
  - `validatePricing` exige `instructionCredit` et `baptismFee` (entiers de
    0 à 1 000 000) ; `readPricing` les fusionne sur les défauts.

- [ ] **Step 1 : tests qui échouent.** Dans `rules/pricing.test.ts` (tests
  écrits en ligne, **pas** dans `test/fixtures/pricing_cases.json`, que la
  Task 5 complète quand le miroir Dart existe) :

```ts
test("closingBill baptism : baptismFee hors app, quelle que soit la durée", () => {
  const p = { ...DEFAULT_PRICING, baptismFee: 70_000 };
  for (const actualMinutes of [20, 60, 200]) {
    assert.deepEqual(
      closingBill({ mode: "baptism", actualMinutes, category: "EXT", pricing: p, hasPassenger: true,
        shortFlightAmount: 5_000, customAmount: 9_000 }),
      { billedAmount: 70_000, billedTo: "off_app", pricingMode: "baptism" });
  }
});

test("pricingWithDefaults : snapshot ancien sans les nouveaux champs", () => {
  const old = { ...DEFAULT_PRICING } as Partial<Pricing>;
  delete old.instructionCredit;
  delete old.baptismFee;
  const p = pricingWithDefaults(old);
  assert.equal(p.instructionCredit, 20_000);
  assert.equal(p.baptismFee, 70_000);
  assert.deepEqual(pricingWithDefaults(null), DEFAULT_PRICING);
  assert.equal(pricingWithDefaults({ ...DEFAULT_PRICING, instructionCredit: 15_000 }).instructionCredit, 15_000);
});

const ins = { uid: "i", profile: "instructeur" as const };
const stu = { uid: "s", profile: "eleve" as const };

test("instructionCreditDue : seuil 45 min, instructeur crédité", () => {
  const p = DEFAULT_PRICING;
  assert.deepEqual(instructionCreditDue({ instruction: true, actualMinutes: 45, crew: [stu, ins], pricing: p }),
    { uid: "i", amount: 20_000 });
  assert.equal(instructionCreditDue({ instruction: true, actualMinutes: 44, crew: [stu, ins], pricing: p }), null);
  assert.equal(instructionCreditDue({ instruction: false, actualMinutes: 90, crew: [stu, ins], pricing: p }), null);
  assert.equal(instructionCreditDue({ instruction: true, actualMinutes: 90, crew: [ins], pricing: p }), null);
  assert.equal(instructionCreditDue({ instruction: true, actualMinutes: 90,
    crew: [ins, { uid: "j", profile: "instructeur" }], pricing: p }), null);
});

test("instructionAdjustments : retrait, ajout, changement d'instructeur, inchangé", () => {
  assert.deepEqual(instructionAdjustments({ uid: null, amount: 0 }, { uid: "i", amount: 20_000 }),
    [{ uid: "i", amount: 20_000 }]);
  assert.deepEqual(instructionAdjustments({ uid: "i", amount: 20_000 }, { uid: null, amount: 0 }),
    [{ uid: "i", amount: -20_000 }]);
  assert.deepEqual(instructionAdjustments({ uid: "i", amount: 20_000 }, { uid: "j", amount: 20_000 }),
    [{ uid: "i", amount: -20_000 }, { uid: "j", amount: 20_000 }]);
  assert.deepEqual(instructionAdjustments({ uid: "i", amount: 20_000 }, { uid: "i", amount: 20_000 }), []);
});
```

  Dans `rules/flights.test.ts` :

```ts
test("isInstructionEligible : exactement un instructeur et un autre membre avec compte", () => {
  assert.equal(isInstructionEligible([{ uid: "s", profile: "eleve" }, { uid: "i", profile: "instructeur" }]), true);
  assert.equal(isInstructionEligible([{ uid: "i", profile: "instructeur" }, { uid: "l", profile: "lache_toute_mission" }]), true);
  assert.equal(isInstructionEligible([{ uid: "i", profile: "instructeur" }]), false);
  assert.equal(isInstructionEligible([{ uid: "i", profile: "instructeur" }, { uid: "j", profile: "instructeur" }]), false);
  assert.equal(isInstructionEligible([{ uid: "s", profile: "eleve" }, { uid: "l", profile: "lache_solo" }]), false);
});
```

  Dans `flights/validation.test.ts` :

```ts
test("validateFlightInput : instruction et baptism booléens, faux par défaut", () => {
  const v = validateFlightInput(ok);
  assert.equal(v.instruction, false);
  assert.equal(v.baptism, false);
  const w = validateFlightInput({ ...ok, crew: ["u1"], passengers: ["Paul"], instruction: true, baptism: true });
  assert.equal(w.instruction, true);
  assert.equal(w.baptism, true);
  assert.throws(() => validateFlightInput({ ...ok, instruction: "oui" }), ValidationError);
});

test("validateFlightInput : baptême sans passager refusé", () => {
  assert.throws(() => validateFlightInput({ ...ok, baptism: true }),
    (e: unknown) => e instanceof ValidationError &&
      e.message === "Baptême de l'air réservé à un vol avec un passager sans compte.");
});

test("validateReviewChanges : instruction et baptism facultatifs", () => {
  const { changes } = validateReviewChanges({ flightId: "f1", changes: { instruction: true, baptism: false } });
  assert.equal(changes.instruction, true);
  assert.equal(changes.baptism, false);
  assert.equal(validateReviewChanges({ flightId: "f1" }).changes.instruction, undefined);
});
```

  Mettre à jour les attentes existantes qui comparent la sortie complète de
  `validateFlightInput` avec `deepEqual` (ajouter `instruction: false, baptism: false`).
  Pour `validatePricing` : un test qui accepte les deux nouveaux champs, et
  refuse leur absence ou une valeur négative (dans le fichier de test qui
  couvre déjà `validatePricing` ; le créer à côté de `finance/validation.ts`
  s'il n'existe pas).

- [ ] **Step 2 : vérifier l'échec** — `cd functions && npm test`.

- [ ] **Step 3 : implémenter.**
  - `rules/pricing.ts` : champs et défauts ; `pricingWithDefaults` ;
    `INSTRUCTION_MIN_MINUTES` ; branche `baptism` en tête de `closingBill`
    (type `mode` élargi, type de retour `pricingMode` élargi à `"baptism"`) ;

```ts
/** Spec §10.1 : crédit dû à l'instructeur à la clôture, ou null. */
export function instructionCreditDue(a: {
  instruction: boolean; actualMinutes: number; crew: Person[]; pricing: Pricing;
}): { uid: string; amount: number } | null {
  if (!a.instruction || a.actualMinutes < INSTRUCTION_MIN_MINUTES || !isInstructionEligible(a.crew)) {
    return null;
  }
  const instructor = a.crew.find((p) => p.profile === "instructeur")!;
  return { uid: instructor.uid, amount: a.pricing.instructionCredit };
}
```

    (`Person` et `isInstructionEligible` importés de `./flights`) et
    `instructionAdjustments` écrit sur le modèle de `adjustments`.
  - `rules/flights.ts` :

```ts
/** Spec §10.1 : exactement un instructeur et un autre membre avec compte. */
export function isInstructionEligible(crew: Person[]): boolean {
  return crew.length === 2 && crew.filter((p) => p.profile === "instructeur").length === 1;
}
```

  - `pricing-store.ts` (`readPricing`) : `instructionCredit` et `baptismFee`
    fusionnés sur les défauts (ou réécrire `readPricing` avec
    `pricingWithDefaults(snap.data())`).
  - `finance/validation.ts` : `instructionCredit: intInRange(d.instructionCredit, "instructionCredit", 0, 1_000_000)`,
    idem `baptismFee`.
  - `flights/validation.ts` : `bool` importé de `../admin/validation` ;
    `validateFlightInput` lit `instruction: bool(d.instruction, "Vol d'instruction", false)`,
    `baptism: bool(d.baptism, "Baptême de l'air", false)` et refuse
    `baptism` sans passager avec le message exact ;
    `validateReviewChanges` lit les deux en facultatif.

- [ ] **Step 4 : vérifier** — `npm test` : tout passe. Lancer aussi
  l'intégration : `createFlight` et la suite doivent rester verts (champs
  par défaut à `false`, rien d'autre ne change encore).

- [ ] **Step 5 : commit**

```bash
git add functions/src
git commit -m "feat(functions): instruction credit and baptism pure rules, pricing fields, input validation (plan 8)"
```

---

### Task 2 : création, modification, validation (`planFlight`)

**Files:**
- Modify: `functions/src/flights/core.ts` (`planFlight`, `checkCredit` appelé ou non)
- Modify: `functions/src/flights/actions.ts` (`validateFlight` : input)
- Modify: `functions/src/flights/edit.ts` (`previousMode` : ignorer `baptism`)
- Test: `functions/src/flights/edit.int.test.ts`, `functions/src/flights/actions.int.test.ts`

**Interfaces:**
- Consumes: `FlightInput.instruction/baptism`, `isInstructionEligible`,
  `PricingMode` élargi (Task 1).
- Produces: champs `flights.instruction` (bool) ; `pricingMode: "baptism"`
  écrit par `planFlight` quand `input.baptism`.

- [ ] **Step 1 : tests qui échouent** (`edit.int.test.ts`, mêmes aides que
  les tests voisins : `seedUser`, `seedAircraft`, `draft`, `createFlight`,
  `updateFlight`, `getFlight` local s'il existe, sinon le définir comme dans
  `close.int.test.ts`) :

```ts
test("vol d'instruction : enregistré avec un instructeur et un élève", async () => {
  const ins = await seedUser({ profile: "instructeur" });
  const stu = await seedUser({ profile: "eleve" });
  const a = await seedAircraft();
  const { id } = await createFlight(ins, { ...draft(a, [stu.uid, ins.uid]), instruction: true });
  assert.equal((await db.collection("flights").doc(id).get()).get("instruction"), true);
});

test("vol d'instruction hors condition : refusé", async () => {
  const ins = await seedUser({ profile: "instructeur" });
  const ins2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  for (const crew of [[ins.uid], [ins.uid, ins2.uid]]) {
    await assert.rejects(createFlight(ins, { ...draft(a, crew), instruction: true }),
      (e) => code(e) === "invalid-argument" &&
        (e as Error).message === "Vol d'instruction : il faut un instructeur et un autre membre avec compte.");
  }
});

test("baptême : mode baptism, pas de contrôle de crédit (solde nul)", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await createFlight(pilot, { ...draft(a, [pilot.uid], { passengers: ["Paul"] }), baptism: true });
  const f = (await db.collection("flights").doc(id).get()).data()!;
  assert.equal(f.pricingMode, "baptism");
  assert.equal(f.instruction, false);
});

test("baptême retiré avec le passager : mode recalculé", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const d = draft(a, [pilot.uid], { passengers: ["Paul"] });
  const { id } = await createFlight(pilot, { ...d, baptism: true });
  await updateFlight(pilot, { flightId: id, ...d, passengers: [] });
  assert.equal((await db.collection("flights").doc(id).get()).get("pricingMode"), "standard");
});
```

  Dans `actions.int.test.ts` (validation d'une demande par l'instructeur,
  mise en place des tests de validation existants) :

```ts
test("validation : l'instructeur coche le vol d'instruction", async () => {
  // demande créée par un élève avec l'instructeur dans l'équipage (comme le
  // test de validation existant), puis :
  await validateFlight(ins, { flightId: id, changes: { instruction: true } });
  assert.equal((await db.collection("flights").doc(id).get()).get("instruction"), true);
});
```

  (L'implémenteur reprend concrètement la mise en place du test de
  validation existant du fichier ; le test doit être complet.)

- [ ] **Step 2 : vérifier l'échec** — intégration.

- [ ] **Step 3 : implémenter.**
  - `planFlight` : après `const d = a.decide(crew)` :

```ts
  // Spec §10.1 : vol d'instruction réservé à un instructeur + un autre membre.
  if (a.input.instruction && !isInstructionEligible(crew)) {
    throw new HttpsError("invalid-argument",
      "Vol d'instruction : il faut un instructeur et un autre membre avec compte.");
  }
```

    puis le mode : `const pricingMode: PricingMode = a.input.baptism ? "baptism" : (a.forcedMode ?? resolvePricingMode({...}))` ;
    le contrôle de crédit ne s'applique que si `pricingMode !== "baptism"`
    (`checkCredit` garde son type `"standard" | "fuel_only"`) ; ajouter
    `instruction: a.input.instruction` aux `fields`. Mettre à jour le
    commentaire « `pricingMode` vaut toujours standard ou fuel_only ».
  - `resolvePricingMode` : un `previous: "baptism"` est traité comme tout
    mode autre que `fuel_only` (rien à changer si la fonction ne teste que
    `=== "fuel_only"` ; le vérifier).
  - `actions.ts` (`validateFlight`) : l'input reprend
    `instruction: changes.instruction ?? (f.get("instruction") === true)` et
    `baptism: changes.baptism ?? (f.get("pricingMode") === "baptism")` ; si le
    vol n'a plus de passager, `baptism` vaut `false`.
  - `edit.ts` : rien d'autre (l'input complet vient du client).
  - **Autres appelants de `FlightInput`** (correction admin, scripts de
    seed) : compléter `instruction`/`baptism` là où un `FlightInput` est
    construit à la main, pour que `tsc` passe (`admin-edit.ts` reçoit
    l'input via `validateFlightInput`, rien à faire).

- [ ] **Step 4 : vérifier** — `npm test` et l'intégration complète.

- [ ] **Step 5 : commit**

```bash
git add functions/src
git commit -m "feat(functions): instruction flag and baptism mode in create/update/validate (plan 8)"
```

---

### Task 3 : clôture (`closeFlight`)

**Files:**
- Modify: `functions/src/flights/close.ts`
- Modify: `functions/src/finance/ledger.ts` (`MovementType` + `"instruction"`)
- Modify: `functions/src/notify/movements.ts`, `functions/src/rules/notifications.ts`
  (+ `rules/notifications.test.ts`)
- Test: `functions/src/flights/close.int.test.ts`

**Interfaces:**
- Consumes: `closingBill` (mode baptism), `instructionCreditDue`,
  `pricingWithDefaults` (Task 1) ; `flights.instruction`, `pricingMode` (Task 2).
- Produces: transaction `type: "instruction"`, `reason: "Crédit instruction"`,
  `flightId`, `amount` > 0 ; champs `flights.instructionCreditUid`,
  `instructionCreditAmount` (null sans crédit) ; `WrittenMovement.type` et
  `movementPush` acceptent `"instruction"` (libellé « Crédit instruction »).

- [ ] **Step 1 : tests qui échouent** (`close.int.test.ts` ; `seedPastFlight`,
  `FUEL`, `flightTx`, `getUser`, `getFlight` existent déjà) :

```ts
test("vol d'instruction de 45 min : instructeur crédité de 20 000, ligne « Crédit instruction »", async () => {
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: a, instruction: true });
  await closeFlight(stu, { ...FUEL, flightId: id, actualMinutes: 45, landings: 1, fuelEnd: 30 });
  assert.equal((await getUser(ins.uid)).balance, 20_000);
  const t = (await flightTx(id)).find((x) => x.type === "instruction")!;
  assert.equal(t.userUid, ins.uid);
  assert.equal(t.amount, 20_000);
  assert.equal(t.reason, "Crédit instruction");
  const f = await getFlight(id);
  assert.equal(f.instructionCreditUid, ins.uid);
  assert.equal(f.instructionCreditAmount, 20_000);
});

test("vol d'instruction de 44 min ou case décochée : pas de crédit", async () => {
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const short = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: a, instruction: true });
  await closeFlight(stu, { ...FUEL, flightId: short, actualMinutes: 44, landings: 1, shortFlightAmount: 8_000, fuelEnd: 32 });
  const plain = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: await seedAircraft(), instruction: false });
  await closeFlight(stu, { ...FUEL, flightId: plain, actualMinutes: 90, landings: 1, fuelEnd: 20 });
  assert.equal((await getUser(ins.uid)).balance, 0);
  assert.equal((await getFlight(short)).instructionCreditUid, null);
});

test("vol d'instruction figé avant le plan 8 : crédit par défaut (20 000)", async () => {
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const { instructionCredit: _i, baptismFee: _b, ...oldSnapshot } = DEFAULT_PRICING;
  const id = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: a, instruction: true,
    pricingSnapshot: oldSnapshot });
  await closeFlight(stu, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, fuelEnd: 25 });
  assert.equal((await getUser(ins.uid)).balance, 20_000);
});

test("baptême : 70 000 hors app quelle que soit la durée, aucun débit", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, passengers: ["Paul"], pricingMode: "baptism" });
  const r = await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 20, landings: 1, fuelEnd: 35 });
  assert.deepEqual(r, { billedAmount: 70_000, billedTo: "off_app" });
  assert.equal((await getUser(pilot.uid)).balance, 0);
  assert.equal((await flightTx(id)).length, 0);
  assert.equal((await getFlight(id)).pricingMode, "baptism");
});
```

  (`DEFAULT_PRICING` est déjà importé dans ce fichier ; `seedPastFlight`
  passe les champs supplémentaires à `seedFlight`.) Dans
  `rules/notifications.test.ts`, un cas `movementPush` de type
  `"instruction"` dont le texte commence par `Crédit instruction : +20 000 FCFA`.

- [ ] **Step 2 : vérifier l'échec.**

- [ ] **Step 3 : implémenter** dans `close.ts`.
  - Lire les membres d'équipage (profils) **avant toute écriture** :
    `const crewSnaps = await tx.getAll(...crew.map((u) => db.collection("users").doc(u)));`
    → `Person[]` (`profile` lu, `null` par défaut) ; réutiliser le document
    du payeur s'il est dans la liste n'est pas nécessaire (lecture double
    autorisée).
  - Tarifs : `const pricing = pricingWithDefaults(snapshot ?? await readPricing(tx, db));`
    (le snapshot peut être ancien).
  - Crédit : `const credit = instructionCreditDue({ instruction: f.get("instruction") === true, actualMinutes, crew: people, pricing });`
    si non nul, lire le compte de l'instructeur et son verrou
    (`flightLocks/user_<uid>`) **avant les écritures**, en évitant de relire
    deux fois le même verrou si l'instructeur est aussi le payeur (dans ce
    cas, partir du solde déjà diminué du débit : enchaîner les deux
    `postMovement` en passant `currentBalance` = solde après le débit).
  - `closingBill` reçoit `mode: f.get("pricingMode") as "standard" | "fuel_only" | "baptism"`.
  - Après le débit éventuel : `postMovement(tx, db, { uid: credit.uid, amount: credit.amount, type: "instruction", reason: "Crédit instruction", flightId: ref.id, by: me.uid, currentBalance })`,
    verrou touché ; le vol reçoit `instructionCreditUid: credit?.uid ?? null`,
    `instructionCreditAmount: credit?.amount ?? null`.
  - La transaction rend aussi le mouvement écrit ; après elle,
    `await notifyMovements(db, me.uid, [written])` s'il y en a un.
  - `ledger.ts` : `MovementType` + `"instruction"`. `notify/movements.ts` et
    `rules/notifications.ts` : type élargi, libellé `instruction: "Crédit instruction"`.

- [ ] **Step 4 : vérifier** — `npm test` et l'intégration complète.

- [ ] **Step 5 : commit**

```bash
git add functions/src
git commit -m "feat(functions): instruction credit and baptism billing at closing (plan 8)"
```

---

### Task 4 : correction et suppression admin

**Files:**
- Modify: `functions/src/flights/admin-edit.ts`
- Test: `functions/src/flights/admin-edit.int.test.ts`

**Interfaces:**
- Consumes: `instructionCreditDue`, `instructionAdjustments`,
  `pricingWithDefaults`, `closingBill` baptism (Task 1) ; champs de la Task 3.

- [ ] **Step 1 : tests qui échouent** (aides du fichier : `closedFlight`,
  `correction`, `balance`, `flightTx`, `getFlight`, `assertInvariant`) :

```ts
test("correction : vol d'instruction décoché → crédit repris", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [stu.uid, ins.uid], aircraftId: a, instruction: true },
    { actualMinutes: 90 });
  assert.equal(await balance(ins.uid), 20_000);
  await adminUpdateFlight(boss, await correction(id, { instruction: false }));
  assert.equal(await balance(ins.uid), 0);
  const t = (await flightTx(id)).filter((x) => x.type === "instruction");
  assert.deepEqual(t.map((x) => x.amount).sort((p, q) => p - q), [-20_000, 20_000]);
  assert.equal(t.find((x) => x.amount < 0)!.reason, "Régularisation crédit instruction");
  assert.equal((await getFlight(id)).instructionCreditUid, null);
});

test("correction : durée passée à 44 min → crédit repris ; repassée à 60 → recrédité", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [stu.uid, ins.uid], aircraftId: a, instruction: true },
    { actualMinutes: 90 });
  await adminUpdateFlight(boss, await correction(id, { actualMinutes: 44, shortFlightAmount: 8_000 }));
  assert.equal(await balance(ins.uid), 0);
  await adminUpdateFlight(boss, await correction(id, { actualMinutes: 60 }));
  assert.equal(await balance(ins.uid), 20_000);
});

test("correction : changement d'instructeur → retrait chez l'ancien, crédit chez le nouveau", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const ins2 = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [stu.uid, ins.uid], aircraftId: a, instruction: true },
    { actualMinutes: 90 });
  await adminUpdateFlight(boss, await correction(id, { crew: [stu.uid, ins2.uid] }));
  assert.equal(await balance(ins.uid), 0);
  assert.equal(await balance(ins2.uid), 20_000);
  assert.equal((await getFlight(id)).instructionCreditUid, ins2.uid);
});

test("correction sans changement : aucune nouvelle ligne instruction", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [stu.uid, ins.uid], aircraftId: a, instruction: true },
    { actualMinutes: 90 });
  await adminUpdateFlight(boss, await correction(id, { destination: "Kara" }));
  assert.equal((await flightTx(id)).filter((x) => x.type === "instruction").length, 1);
});

test("suppression d'un vol d'instruction clôturé : crédit repris", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [stu.uid, ins.uid], aircraftId: a, instruction: true },
    { actualMinutes: 90 });
  await adminDeleteFlight(boss, { flightId: id });
  assert.equal(await balance(ins.uid), 0);
  await assertInvariant(id);
});

test("correction : vol standard passé en baptême → débit remboursé, 70 000 hors app", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], passengers: ["Paul"], aircraftId: a },
    { actualMinutes: 90 });
  const before = await balance(pilot.uid);
  await adminUpdateFlight(boss, await correction(id, { baptism: true }));
  const f = await getFlight(id);
  assert.equal(f.pricingMode, "baptism");
  assert.equal(f.billedTo, "off_app");
  assert.equal(f.billedAmount, 70_000);
  assert.ok(await balance(pilot.uid) > before);
  await assertInvariant(id);
});
```

  (Vérifier que `assertInvariant` ignore les transactions `instruction` :
  il ne somme que `flight` et `flight_adjustment`, ce qui est voulu.)

- [ ] **Step 2 : vérifier l'échec.**

- [ ] **Step 3 : implémenter** dans `admin-edit.ts`.
  - Mode : si `input.baptism`, ignorer `v.pricingMode`/`custom` :
    `const mode = input.baptism ? undefined : (v.pricingMode ?? (...existant...))` ;
    `customAmount` vaut `null` en baptême. `billMode` est typé
    `"standard" | "fuel_only" | "baptism"` (valeur de `p.fields.pricingMode`).
    `computedCost` n'est appelé (pour `shortFlightAmount`) que si
    `billMode !== "baptism"` ; en baptême `shortFlightAmount` vaut `null`.
  - Tarifs : `const pricing = pricingWithDefaults(p.fields.pricingSnapshot as Pricing)`.
  - Vol clôturé, après `planFlight` et avant toute écriture : lire les
    profils de `input.crew` (`tx.getAll`), calculer
    `after = instructionCreditDue({ instruction: input.instruction, actualMinutes, crew: people, pricing })`,
    `before = { uid: f.get("instructionCreditUid") ?? null, amount: f.get("instructionCreditAmount") ?? 0 }`,
    `moves = instructionAdjustments(before, after ?? { uid: null, amount: 0 })`.
    Les uids de `moves` rejoignent ceux passés à `readAccounts` (un seul
    appel, dédoublonné). Écrire chaque mouvement avec
    `type: "instruction", reason: "Régularisation crédit instruction"` en
    enchaînant les soldes par compte (un compte peut recevoir une
    régularisation de vol puis une d'instruction : passer le solde déjà mis
    à jour). Le vol reçoit `instructionCreditUid/Amount` d'après `after`.
    Ajouter ces mouvements à `posted` (notifications).
  - `adminDeleteFlight` : si `instructionCreditUid`, lire son compte avec
    celui du payeur (un `readAccounts`), écrire
    `{ amount: -instructionCreditAmount, type: "instruction", reason: "Régularisation crédit instruction" }`
    (solde enchaîné si c'est aussi le payeur), notifier.

- [ ] **Step 4 : vérifier** — `npm test` et l'intégration complète.

- [ ] **Step 5 : commit**

```bash
git add functions/src
git commit -m "feat(functions): admin correction and deletion regularise instruction credit and baptism (plan 8)"
```

---

### Task 5 : app, modèles et règles (miroir Dart)

**Files:**
- Modify: `lib/core/pricing.dart`, `lib/core/flight_rules.dart`
- Modify: `lib/data/flight.dart` (`Flight`, `FlightDraft`), `lib/data/account_movement.dart` (commentaire du type)
- Modify: `lib/features/flight/flight_texts.dart` (`pricingModeLabel`)
- Modify: `lib/features/account/movements_list.dart` (`movementTypeLabel`, `movementTitle`)
- Modify: `test/fixtures/pricing_cases.json`, `test/fixtures/flight_rules.json`
- Modify: `functions/src/rules/flights.test.ts` (lecture du nouveau jeu de cas)
- Test: `test/core/pricing_test.dart`, `test/core/flight_rules_test.dart`,
  `test/data/flight_test.dart`, `test/features/account/account_screen_test.dart`
  (ou le test qui couvre `movementTitle`), `test/features/flight/flight_texts_test.dart`

**Interfaces:**
- Produces (Dart) :
  - `Pricing.instructionCredit`, `Pricing.baptismFee` (`fromMap` avec
    défauts 20 000 / 70 000, `toMap`), `defaultPricing` à jour.
  - `closingBill(mode: 'baptism', ...)` → `(billedAmount: pricing.baptismFee, billedTo: 'off_app', pricingMode: 'baptism')`.
  - `bool isInstructionEligible(List<RulePerson> crew)` dans `flight_rules.dart`.
  - `Flight.instruction` (bool, défaut false), `Flight.instructionCreditUid`
    (String?), `Flight.instructionCreditAmount` (int?) ; `bool get isBaptism => pricingMode == 'baptism'`.
  - `FlightDraft.instruction` et `FlightDraft.baptism` (bool, défaut
    false), envoyés **toujours** par `toPayload()` (`'instruction'`, `'baptism'`).
  - `pricingModeLabel('baptism') == 'Baptême de l\'air'`.
  - `movementTypeLabel('instruction') == 'Crédit instruction'` ; pour le
    type `instruction`, `movementTitle` = motif (repli « Crédit
    instruction ») + « — vol du … » : « Crédit instruction — vol du lundi
    12 octobre », « Régularisation crédit instruction — vol du lundi 12 octobre ».
  - `testFlight(...)` (fakes) accepte `bool instruction = false`,
    `String? instructionCreditUid`, `int? instructionCreditAmount`.

- [ ] **Step 1 : tests qui échouent.**
  - Fixtures partagées : ajouter à `pricing_cases.json` → `closing` le cas

```json
{"name": "baptême 20 min, montants saisis ignorés", "mode": "baptism", "actualMinutes": 20,
 "category": "EXT", "hasPassenger": true, "shortFlightAmount": 5000, "customAmount": 9000,
 "expected": {"billedAmount": 70000, "billedTo": "off_app", "pricingMode": "baptism"}}
```

    (si le chargeur des tests TS/Dart ne transmet pas `shortFlightAmount`/
    `customAmount`, l'adapter des deux côtés pour qu'il les transmette) ;
    et à `flight_rules.json` une section `"instruction"` :

```json
"instruction": [
  {"name": "instructeur + élève", "crew": [{"uid": "s", "profile": "eleve"}, {"uid": "i", "profile": "instructeur"}], "expected": true},
  {"name": "instructeur seul", "crew": [{"uid": "i", "profile": "instructeur"}], "expected": false},
  {"name": "deux instructeurs", "crew": [{"uid": "i", "profile": "instructeur"}, {"uid": "j", "profile": "instructeur"}], "expected": false},
  {"name": "sans instructeur", "crew": [{"uid": "s", "profile": "eleve"}, {"uid": "l", "profile": "lache_solo"}], "expected": false}
]
```

    lue par `test/core/flight_rules_test.dart` **et**
    `functions/src/rules/flights.test.ts` (boucle sur `fx.instruction`).
  - `pricing_test.dart` : `Pricing.fromMap({})` donne 20 000 / 70 000 ;
    `toMap()` contient `instructionCredit` et `baptismFee`.
  - `flight_test.dart` : lecture de `instruction`, `instructionCreditUid`,
    `instructionCreditAmount`, `isBaptism` ; `FlightDraft(...).toPayload()`
    contient `'instruction': false, 'baptism': false` par défaut.
  - `flight_texts_test.dart` : `pricingModeLabel('baptism')`.
  - Test de `movementTitle` (dans le fichier qui le couvre déjà) : les deux
    libellés ci-dessus.

- [ ] **Step 2 : vérifier l'échec** — `fvm flutter test` et `cd functions && npm test`.

- [ ] **Step 3 : implémenter** (miroirs exacts du serveur ; `RulePerson` a
  déjà `profile` en code texte).

- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze` et
  `npm test`.

- [ ] **Step 5 : commit**

```bash
git add lib test functions/src
git commit -m "feat(app): pricing, rules and models for instruction credit and baptism (plan 8)"
```

---

### Task 6 : formulaire de vol (instruction, passager baptême, aperçu)

**Files:**
- Modify: `lib/features/flight/flight_screen.dart`
- Test: `test/features/flight/flight_screen_test.dart`

**Interfaces:**
- Consumes: `isInstructionEligible`, `FlightDraft.instruction/baptism`,
  `Flight.instruction/isBaptism`, `pricingModeLabel` (Task 5).
- Produces: clés `f-instruction` (case), `passenger-baptism` (case de la
  fenêtre passager), `passenger-baptism-toggle` (case sur la ligne du
  passager).

- [ ] **Step 1 : tests qui échouent** (mises en place des tests voisins :
  `host`, `api()`, `FakeFinanceApi`, `testUser`, `member`) :
  1. Création par un instructeur avec un élève dans l'équipage : la case
     `f-instruction` (« Vol d'instruction ») est visible ; cochée puis
     « Enregistrer » → `api.created.single['instruction'] == true`.
  2. Équipage d'un seul instructeur, ou de deux instructeurs : case absente.
     Un élève retiré de l'équipage après avoir coché : la case disparaît et
     le payload contient `instruction: false`.
  3. Fenêtre « Passager sans compte » : nom + case `passenger-baptism`
     (« Baptême de l'air ») ; cochée → la ligne affiche « Passager sans
     compte · Baptême de l'air », l'aperçu affiche « Mode : Baptême de
     l'air » et « Baptême de l'air : 70 000 FCFA, facturé hors app », sans
     « Coût estimé » ni « Crédit disponible », et la case « Carburant
     seulement » est absente ; « Enregistrer » → payload `baptism: true`
     même avec un solde nul (pas d'erreur « Crédit insuffisant »).
  4. Case `passenger-baptism-toggle` sur la ligne du passager : décocher →
     aperçu revenu au mode normal ; retirer le passager → payload
     `baptism: false`.
  5. Vol existant d'instruction (consultation) : « Vol d'instruction
     (INS) » affiché (trigramme de l'instructeur) ; **aucune** mention de
     crédit instruction (`find.textContaining('Crédit instruction')` →
     rien).
  6. Validation par l'instructeur : cocher `f-instruction` → les `changes`
     envoyés à `validate` contiennent `instruction: true` (et `baptism`).
  7. Vol existant en baptême ouvert en modification : la case
     `passenger-baptism-toggle` est cochée.

  Écrire ces tests en entier (aucun « ... »), en reprenant la mise en place
  des tests de création, de modification, de validation et de consultation
  existants.

- [ ] **Step 2 : vérifier l'échec.**

- [ ] **Step 3 : implémenter.**
  - État : `bool _instruction`, `bool _baptism`, initialisés depuis le vol
    (`f.instruction`, `f.isBaptism`).
  - `bool get _instructionEligible => isInstructionEligible([for (final u in _crew) RulePerson(u, _profile(u)?.code)]);`
    la case n'est affichée que si `_instructionEligible` (sous l'équipage),
    modifiable si `_fieldsEditable` ; `_draft()` envoie
    `instruction: _instruction && _instructionEligible`.
  - `_PassengerDialog` rend `({String name, bool baptism})` ; case
    « Baptême de l'air » sous le nom. Ligne du passager : sous-titre
    « Passager sans compte · Baptême de l'air » si baptême ; une case
    `passenger-baptism-toggle` (ou `CheckboxListTile` compacte) modifiable
    si `_crewEditable`. Retirer le passager remet `_baptism = false`.
  - `_pricingMode` : `if (_passenger != null && _baptism) return 'baptism';`
    en tête ; `_showFuelChoice` faux en baptême ; `_estimatedCost` null en
    baptême (donc pas de lignes coût/crédit, pas d'erreur de crédit) ;
    l'aperçu ajoute « Baptême de l'air : ${formatFcfa(_pricingForCost.baptismFee)}, facturé hors app ».
  - `_draft()` : `baptism: _passenger != null && _baptism`.
  - Validation (`_Mode.validate`) : `changes` reçoit aussi
    `'instruction': d.instruction, 'baptism': d.baptism`.
  - Consultation : ListTile « Vol d'instruction (${_short(instructeur)}) »
    quand `f.instruction` (instructeur = membre de profil instructeur).

- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze`.

- [ ] **Step 5 : commit**

```bash
git add lib/features/flight/flight_screen.dart test/features/flight/flight_screen_test.dart
git commit -m "feat(app): instruction checkbox and baptism passenger in the flight form (plan 8)"
```

---

### Task 7 : clôture, correction admin, Tarifs

**Files:**
- Modify: `lib/features/flight/closing_dialog.dart`, `lib/features/flight/flight_screen.dart`
  (correction admin), `lib/features/admin/pricing_admin_screen.dart`
- Test: `test/features/flight/closing_dialog_test.dart`,
  `test/features/flight/flight_screen_test.dart`,
  `test/features/admin/pricing_admin_screen_test.dart`

**Interfaces:**
- Consumes: `closingBill` baptism, `Pricing.baptismFee/instructionCredit` (Task 5).
- Produces: clés `instructionCredit`, `baptismFee` (champs Tarifs).

- [ ] **Step 1 : tests qui échouent.**
  1. Dialogue de clôture en mode `baptism` (vol de 20 min) : pas de champ
     `closing-short-amount`, pas de case `closing-custom-check`, texte
     « Montant : 70 000 FCFA facturé hors app » ; « Clôturer » rend un
     résultat sans `shortFlightAmount` ni `customAmount`.
  2. Dialogue de clôture d'un vol d'instruction : aucun texte contenant
     « instruction » (le dialogue ne reçoit d'ailleurs pas l'information).
  3. Correction admin d'un vol clôturé : la case `f-instruction` et la case
     `passenger-baptism-toggle` sont modifiables ; le payload
     d'`adminUpdateFlight` contient `instruction` et `baptism` ; en baptême,
     pas de « Montant différent » dans la correction.
  4. Tarifs : champs « Crédit instruction » (`instructionCredit`) et
     « Baptême de l'air » (`baptismFee`) pré-remplis (20 000 / 70 000),
     modifiés puis enregistrés → `updatedPricing.instructionCredit/baptismFee`.

- [ ] **Step 2 : vérifier l'échec.**

- [ ] **Step 3 : implémenter.**
  - `ClosingDialog` : en `mode == 'baptism'`, `_needsShortAmount` faux, pas
    de case « Montant différent », aperçu = `closingBill(mode: 'baptism', …)`
    (indépendant de la catégorie : l'afficher même si `category == null`) ;
    texte « Montant : 70 000 FCFA facturé hors app ».
  - Correction admin : `_correctNeedsShortAmount` faux en baptême ; case
    « Montant différent » masquée en baptême ; `_correctionPayload` part de
    `_draft()` (qui porte déjà `instruction` et `baptism`) et n'envoie pas
    `pricingMode` en baptême.
  - Tarifs : deux `TextFormField` (format des montants comme
    `fuelHourlyRate`), passés au `Pricing` enregistré.

- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze`.

- [ ] **Step 5 : commit**

```bash
git add lib test
git commit -m "feat(app): baptism closing, admin correction and pricing fields (plan 8)"
```

---

### Task 8 : docs, vérification complète, déploiement dev

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1 : vérification complète** (les trois suites des Global
  Constraints) : tout passe.
- [ ] **Step 2 : `CLAUDE.md`** (en français, sections existantes) :
  référence au plan 8 (`docs/superpowers/plans/2026-10-05-ulmgap-08-instruction-bapteme.md`,
  spec §10) ; en prod : déployer toutes les Functions (version du plan 8)
  avec l'app web, `adminUpdatePricing` exigeant désormais les deux nouveaux
  tarifs ; en dev : Functions redéployées ; mention de la branche non
  fusionnée.
- [ ] **Step 3 : déploiement dev** (jamais prod) :

```bash
cd functions && npm run build && npx firebase deploy --only functions:createFlight,functions:updateFlight,functions:validateFlight,functions:closeFlight,functions:adminUpdateFlight,functions:adminDeleteFlight,functions:adminUpdatePricing --project dev
```

  (Noms exportés à vérifier dans `functions/src/index.ts` ; en cas d'échec,
  ne pas réessayer avec d'autres options : rapporter l'erreur.)
- [ ] **Step 4 : commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md, plan 8 (instruction credit, baptism) done, deploy notes"
```
