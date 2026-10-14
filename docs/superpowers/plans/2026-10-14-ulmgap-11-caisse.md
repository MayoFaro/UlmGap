# UlmGap, plan 11 : suivi de caisse

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** tenir dans l'app la caisse unique de l'association (spec §11) :
Crédit carburant (caisse + compte), dépenses et recettes, corrections
d'opération, écart de caisse, reprise de l'historique Excel, clôture de la
reprise.

**Architecture :** comme aux plans précédents. Règles pures dans
`functions/src/rules/cash.ts` ; écritures par des Functions callables
(`europe-west1`) qui lisent puis écrivent `cashbox/main` dans chaque
transaction (sérialisation, comme `flightLocks`) ; historique non modifiable
`cashMovements`. Côté app : `CashApi` (nouveau service injecté dans
`AppServices`), écran « Caisse » pour les instructeurs et les admins.

**Tech Stack :** inchangée (Flutter 3.32.8 via fvm, Firestore, Functions
Node 22, `firebase-functions` 7, `firebase-admin` 13, `node:test`).

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §11
(révision du 2026-10-14), plus §2.6, §4.5, §5 (Pilotes, navigation).

**Branche :** `feature/caisse`, créée depuis `main`.

## Global Constraints

- Toujours `fvm flutter` / `fvm dart`. TDD : chaque changement commence par
  un test qui échoue. Textes de l'interface en français. **Jamais de
  déploiement en prod** ; la recette se fait sur `ulmgap-dev`.
- Règle absolue : le solde de caisse (`cashbox/main.balance`) n'est jamais
  modifié sans sa ligne `cashMovements`, dans la même transaction ; idem
  pour `users.balance` et `transactions` (`postMovement`).
- `kind` ∈ `fuel_credit` (entrée) / `fuel_purchase` (sortie) /
  `maintenance` (sortie) / `off_app_income` (entrée) / `cash_gap` (±) /
  `opening` (entrée, import seulement). `amount` entier signé.
- `date` : chaîne `AAAA-MM-JJ`, jour du club (Africa/Libreville, UTC+1),
  jamais dans le futur ; défaut : aujourd'hui.
- Libellés : « Crédit carburant XXX » (XXX = `shortName`), « Achat
  carburant », « Maintenance », « Recette hors app », « Écart de caisse »,
  « Fond initial ». Le type `credit` d'un compte s'affiche « Crédit
  carburant ».
- Droits : instructeurs et admins pour tout, sauf `cash_gap` (création et
  correction), correction du Fond initial et « Reprise terminée » : **admins
  seulement**.
- Après « Reprise terminée », `correctAccount` est refusée : « La reprise
  est terminée : corrigez le crédit carburant concerné. »
- Montants sans plafond. Note : 200 caractères au maximum ; obligatoire
  pour `maintenance`, `off_app_income` (« Objet obligatoire. ») et
  `cash_gap` (« Motif obligatoire pour un écart de caisse. »).
- L'Excel et le CSV d'import restent **hors du dépôt** (`.gitignore`).
- Tests : `fvm flutter test && fvm flutter analyze` ; `cd functions && npm
  test` ; intégration : `cd functions && JAVA_HOME=/opt/android-studio/jbr
  PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int` (juger sur
  `# fail` / `not ok`).

## Review Focus

- **État global entre fichiers de tests d'intégration** : `cashbox/main`
  (et `migrationClosedAt`) est un document unique ; un test qui clôt la
  reprise ne doit pas faire échouer `correctAccount` dans
  `accounts.int.test.ts`. → `resetCashbox()` (Task 3) en `beforeEach` des
  deux fichiers.
- **Opérations simultanées** : deux opérations de caisse en parallèle
  doivent laisser un solde égal à la somme des montants, et des
  `balanceAfter` enchaînés. → test « deux opérations simultanées » (Task 4).
- **Corrections successives** : la deuxième correction part du montant
  juste laissé par la première, pas du montant d'origine ; une ligne de
  correction n'est pas corrigeable. → tests Task 4.
- **Correction d'un Crédit carburant après d'autres mouvements du compte** :
  l'écart s'applique au solde actuel de l'adhérent. → test Task 4.
- **Barre de navigation à 360 px** avec la nouvelle icône « Caisse » : pas
  de débordement. → test Task 8.

---

### Task 1 : branche, spec, `.gitignore`, règles pures de la caisse

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md` (§11)
- Modify: `.gitignore`
- Create: `functions/src/rules/cash.ts`
- Test: `functions/src/rules/cash.test.ts`

**Interfaces:**
- Produces :
  - `type CashKind = "fuel_credit" | "fuel_purchase" | "maintenance" | "off_app_income" | "cash_gap" | "opening"`
  - `CASH_KINDS: readonly CashKind[]`
  - `cashSign(kind: CashKind): 1 | -1 | 0`
  - `signedCashAmount(kind: CashKind, input: number, allowZero: boolean): number` (lève `ValidationError`)
  - `clubDayString(ms: number): string` (`AAAA-MM-JJ`)
  - `isValidCashDay(day: string, nowMs: number): boolean`
  - `formatCashDay(day: string): string` (`JJ/MM/AAAA`)

- [ ] **Step 1 : branche**

```bash
git checkout -b feature/caisse main
```

- [ ] **Step 2 : précisions de la spec (décidées en planification)**

Dans §11.2, ligne `date` du tableau, remplacer le contenu par :
`Jour de l'opération, chaîne « AAAA-MM-JJ » (jour du club, Africa/Libreville) : aujourd'hui par défaut, jamais dans le futur`.

Dans §11.4, remplacer le deuxième point par :

```markdown
- La correction est une **nouvelle ligne** du même `kind`, `correctsId` =
  ligne d'origine, `amount` = écart, **même `date` que la ligne d'origine**
  (elle reste dans la même période), note « Correction » ou « Correction :
  motif ». On ne corrige qu'une ligne d'origine, jamais une ligne de
  correction. Corriger un Écart de caisse ou le Fond initial : admins
  seulement.
```

et, dans le point « Crédit carburant », remplacer « Correction crédit
carburant du 12 oct. » par « Correction crédit carburant du 12/10/2026 ».

Dans §11.6, remplacer le point « Administration » par :

```markdown
- **Reprise** : sur l'écran Caisse, pour les admins, bouton « Reprise
  terminée » avec confirmation, tant que la reprise est en cours ; ensuite
  « Reprise terminée le 20/10/2026 ».
```

- [ ] **Step 3 : `.gitignore`** (ajouter à la fin)

```gitignore
# Données financières (caisse) : jamais dans le dépôt (spec §11.7).
docs/*.xlsx
docs/*.csv
docs/.~lock*
```

Vérifier : `git status --short docs` ne montre plus l'Excel ni son verrou.

- [ ] **Step 4 : test qui échoue** — `functions/src/rules/cash.test.ts`

```ts
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import {
  CASH_KINDS, cashSign, clubDayString, formatCashDay, isValidCashDay, signedCashAmount,
} from "./cash";

test("cashSign : entrées, sorties, écart", () => {
  assert.equal(cashSign("fuel_credit"), 1);
  assert.equal(cashSign("off_app_income"), 1);
  assert.equal(cashSign("opening"), 1);
  assert.equal(cashSign("fuel_purchase"), -1);
  assert.equal(cashSign("maintenance"), -1);
  assert.equal(cashSign("cash_gap"), 0);
  assert.equal(CASH_KINDS.length, 6);
});

test("signedCashAmount : saisie positive, signe selon le type", () => {
  assert.equal(signedCashAmount("fuel_credit", 50_000, false), 50_000);
  assert.equal(signedCashAmount("fuel_purchase", 474_000, false), -474_000);
  assert.equal(signedCashAmount("maintenance", 10_000, false), -10_000);
  assert.equal(signedCashAmount("cash_gap", -3_000, false), -3_000);
  assert.equal(signedCashAmount("cash_gap", 3_000, false), 3_000);
});

test("signedCashAmount : zéro seulement pour une correction, jamais -0", () => {
  assert.throws(() => signedCashAmount("maintenance", 0, false), ValidationError);
  assert.throws(() => signedCashAmount("cash_gap", 0, false), ValidationError);
  assert.ok(Object.is(signedCashAmount("maintenance", 0, true), 0));
  assert.equal(signedCashAmount("cash_gap", 0, true), 0);
});

test("signedCashAmount : négatif hors écart, décimal, non-nombre refusés", () => {
  assert.throws(() => signedCashAmount("fuel_purchase", -10, false), ValidationError);
  assert.throws(() => signedCashAmount("fuel_credit", 10.5, false), ValidationError);
  assert.throws(() => signedCashAmount("fuel_credit", Number.NaN, false), ValidationError);
});

test("clubDayString : jour à l'heure du club (UTC+1)", () => {
  assert.equal(clubDayString(Date.UTC(2026, 9, 14, 22, 59)), "2026-10-14");
  assert.equal(clubDayString(Date.UTC(2026, 9, 14, 23, 30)), "2026-10-15");
});

test("isValidCashDay : format, date réelle, pas de futur", () => {
  const now = Date.UTC(2026, 9, 14, 12);
  assert.equal(isValidCashDay("2026-10-14", now), true);
  assert.equal(isValidCashDay("2025-03-05", now), true);
  assert.equal(isValidCashDay("2026-10-15", now), false); // demain
  assert.equal(isValidCashDay("2026-02-30", now), false);
  assert.equal(isValidCashDay("14/10/2026", now), false);
  assert.equal(isValidCashDay("1999-12-31", now), false); // avant 2000
});

test("formatCashDay : JJ/MM/AAAA", () => {
  assert.equal(formatCashDay("2026-10-12"), "12/10/2026");
});
```

- [ ] **Step 5 : échec attendu**

Run: `cd functions && npm test`
Expected: FAIL à la compilation, `Cannot find module './cash'`.

- [ ] **Step 6 : implémentation** — `functions/src/rules/cash.ts`

```ts
// Caisse (spec §11) : types d'opération, signes, jour du club. Module pur,
// sans Firestore.
import { ValidationError } from "../admin/validation";
import { clubDay } from "./club-day";

export type CashKind =
  "fuel_credit" | "fuel_purchase" | "maintenance" | "off_app_income" | "cash_gap" | "opening";

export const CASH_KINDS: readonly CashKind[] = [
  "fuel_credit", "fuel_purchase", "maintenance", "off_app_income", "cash_gap", "opening",
];

/** +1 : entrée, −1 : sortie, 0 : les deux (écart de caisse). */
export function cashSign(kind: CashKind): 1 | -1 | 0 {
  if (kind === "fuel_purchase" || kind === "maintenance") return -1;
  if (kind === "cash_gap") return 0;
  return 1;
}

/**
 * Montant signé d'une saisie : positive pour une entrée ou une sortie,
 * signée pour un écart. Zéro n'est accepté que pour une correction
 * (montant juste nul = opération annulée).
 */
export function signedCashAmount(kind: CashKind, input: number, allowZero: boolean): number {
  if (!Number.isInteger(input)) throw new ValidationError("Montant invalide.");
  if (input === 0) {
    if (!allowZero) throw new ValidationError("Montant invalide (non nul).");
    return 0;
  }
  const sign = cashSign(kind);
  if (sign === 0) return input;
  if (input < 0) throw new ValidationError("Montant invalide (positif).");
  return sign * input;
}

/** « AAAA-MM-JJ » du jour du club. */
export function clubDayString(ms: number): string {
  return new Date(clubDay(ms) * 86_400_000).toISOString().slice(0, 10);
}

/** Jour réel « AAAA-MM-JJ », depuis 2000, au plus aujourd'hui (jour du club). */
export function isValidCashDay(day: string, nowMs: number): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < "2000-01-01") return false;
  const ms = Date.parse(`${day}T00:00:00Z`);
  if (Number.isNaN(ms) || new Date(ms).toISOString().slice(0, 10) !== day) return false;
  return day <= clubDayString(nowMs);
}

/** « 12/10/2026 » */
export function formatCashDay(day: string): string {
  const [y, m, d] = day.split("-");
  return `${d}/${m}/${y}`;
}
```

- [ ] **Step 7 : succès**

Run: `cd functions && npm test`
Expected: PASS (tous les tests unitaires).

- [ ] **Step 8 : commit**

```bash
git add .gitignore docs/superpowers/specs/2026-09-25-ulmgap-app-design.md functions/src/rules/cash.ts functions/src/rules/cash.test.ts
git commit -m "feat(functions): cash box pure rules (kinds, signs, club day)"
```

---

### Task 2 : validation des saisies de caisse et date du Crédit carburant

**Files:**
- Create: `functions/src/finance/cash-validation.ts`
- Test: `functions/src/finance/cash-validation.test.ts`
- Modify: `functions/src/finance/validation.ts` (`validateCredit`)
- Modify: `functions/src/finance/validation.test.ts:82-103`

**Interfaces:**
- Consumes : Task 1 (`CashKind`, `signedCashAmount`, `isValidCashDay`, `clubDayString`).
- Produces :
  - `cashDay(v: unknown, nowMs: number): string`
  - `validateAddCashMovement(data: unknown, nowMs: number): { kind: CashKind; amount: number; date: string; note: string | null }` (`amount` signé)
  - `validateCashCorrection(data: unknown): { movementId: string; amount: number; note: string | null }` (`amount` = saisie brute, signée côté Function d'après le `kind`)
  - `validateCredit(data: unknown, nowMs?: number): { userUid; amount; reason; date: string }`

- [ ] **Step 1 : test qui échoue** — `functions/src/finance/cash-validation.test.ts`

```ts
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import { cashDay, validateAddCashMovement, validateCashCorrection } from "./cash-validation";

const NOW = Date.UTC(2026, 9, 14, 12);

test("cashDay : défaut aujourd'hui, jour passé accepté, futur refusé", () => {
  assert.equal(cashDay(undefined, NOW), "2026-10-14");
  assert.equal(cashDay(null, NOW), "2026-10-14");
  assert.equal(cashDay("2026-10-01", NOW), "2026-10-01");
  assert.throws(() => cashDay("2026-10-15", NOW), ValidationError);
  assert.throws(() => cashDay(20261014, NOW), ValidationError);
});

test("validateAddCashMovement : achat carburant, note facultative, montant débité", () => {
  assert.deepEqual(
    validateAddCashMovement({ kind: "fuel_purchase", amount: 220_000 }, NOW),
    { kind: "fuel_purchase", amount: -220_000, date: "2026-10-14", note: null },
  );
});

test("validateAddCashMovement : maintenance et recette exigent un objet", () => {
  assert.throws(() => validateAddCashMovement({ kind: "maintenance", amount: 10_000 }, NOW),
    (e) => e instanceof ValidationError && e.message === "Objet obligatoire.");
  assert.throws(() => validateAddCashMovement({ kind: "off_app_income", amount: 70_000, note: "  " }, NOW),
    (e) => e instanceof ValidationError && e.message === "Objet obligatoire.");
  assert.deepEqual(
    validateAddCashMovement({ kind: "maintenance", amount: 10_000, note: " Nettoyage ", date: "2026-10-09" }, NOW),
    { kind: "maintenance", amount: -10_000, date: "2026-10-09", note: "Nettoyage" },
  );
});

test("validateAddCashMovement : écart de caisse signé, motif obligatoire", () => {
  assert.throws(() => validateAddCashMovement({ kind: "cash_gap", amount: -5_000 }, NOW),
    (e) => e instanceof ValidationError && e.message === "Motif obligatoire pour un écart de caisse.");
  assert.deepEqual(
    validateAddCashMovement({ kind: "cash_gap", amount: -5_000, note: "Comptage" }, NOW),
    { kind: "cash_gap", amount: -5_000, date: "2026-10-14", note: "Comptage" },
  );
});

test("validateAddCashMovement : Crédit carburant et Fond initial refusés ici ; type inconnu", () => {
  for (const kind of ["fuel_credit", "opening", "autre", undefined]) {
    assert.throws(() => validateAddCashMovement({ kind, amount: 1_000, note: "x" }, NOW),
      (e) => e instanceof ValidationError && e.message === "Type d'opération invalide.", String(kind));
  }
});

test("validateAddCashMovement : montant nul, négatif hors écart, chaîne, note trop longue", () => {
  for (const bad of [
    { kind: "fuel_purchase", amount: 0 },
    { kind: "fuel_purchase", amount: -1 },
    { kind: "fuel_purchase", amount: "1000" },
    { kind: "fuel_purchase", amount: 1_000, note: "x".repeat(201) },
  ]) {
    assert.throws(() => validateAddCashMovement(bad, NOW), ValidationError, JSON.stringify(bad));
  }
});

test("validateCashCorrection : identifiant, montant entier (zéro accepté), note facultative", () => {
  assert.deepEqual(validateCashCorrection({ movementId: "m1", amount: 0 }),
    { movementId: "m1", amount: 0, note: null });
  assert.deepEqual(validateCashCorrection({ movementId: "m1", amount: 25_000, note: " Faute de frappe " }),
    { movementId: "m1", amount: 25_000, note: "Faute de frappe" });
  for (const bad of [{ amount: 1 }, { movementId: "a/b", amount: 1 }, { movementId: "m1", amount: 1.5 }]) {
    assert.throws(() => validateCashCorrection(bad), ValidationError, JSON.stringify(bad));
  }
});
```

Dans `functions/src/finance/validation.test.ts`, remplacer les deux tests
nominaux de `validateCredit` (lignes 82 à 98) par :

```ts
const NOW = Date.UTC(2026, 9, 14, 12);

test("validateCredit : cas nominal, avec et sans motif, date par défaut", () => {
  assert.deepEqual(
    validateCredit({ userUid: "u1", amount: 50_000 }, NOW),
    { userUid: "u1", amount: 50_000, reason: null, date: "2026-10-14" },
  );
  assert.deepEqual(
    validateCredit({ userUid: "u1", amount: 50_000, reason: " Versement caisse ", date: "2026-10-12" }, NOW),
    { userUid: "u1", amount: 50_000, reason: "Versement caisse", date: "2026-10-12" },
  );
});

test("validateCredit : aucun plafond, 1 000 000 accepté ; date future refusée", () => {
  assert.deepEqual(
    validateCredit({ userUid: "u1", amount: 1_000_000 }, NOW),
    { userUid: "u1", amount: 1_000_000, reason: null, date: "2026-10-14" },
  );
  assert.throws(() => validateCredit({ userUid: "u1", amount: 1_000, date: "2026-10-15" }, NOW), ValidationError);
});
```

- [ ] **Step 2 : échec attendu**

Run: `cd functions && npm test`
Expected: FAIL à la compilation (`./cash-validation` introuvable, `validateCredit` sans second paramètre).

- [ ] **Step 3 : implémentation** — `functions/src/finance/cash-validation.ts`

```ts
// Validation (pure) des opérations de caisse (spec §11.3, §11.4).
import { obj, ValidationError } from "../admin/validation";
import { CashKind, clubDayString, isValidCashDay, signedCashAmount } from "../rules/cash";

const ADDABLE: readonly CashKind[] = ["fuel_purchase", "maintenance", "off_app_income", "cash_gap"];

/** Jour de l'opération : aujourd'hui par défaut, jamais dans le futur. */
export function cashDay(v: unknown, nowMs: number): string {
  if (v === undefined || v === null) return clubDayString(nowMs);
  if (typeof v !== "string" || !isValidCashDay(v, nowMs)) {
    throw new ValidationError("Date invalide (au plus aujourd'hui).");
  }
  return v;
}

function note(v: unknown, missing: string | null): string | null {
  if (v !== undefined && v !== null && typeof v !== "string") throw new ValidationError("Note invalide.");
  const s = typeof v === "string" ? v.trim() : "";
  if (s.length > 200) throw new ValidationError("Note trop longue (200 caractères au maximum).");
  if (missing && !s) throw new ValidationError(missing);
  return s || null;
}

function missingNote(kind: CashKind): string | null {
  if (kind === "cash_gap") return "Motif obligatoire pour un écart de caisse.";
  if (kind === "maintenance" || kind === "off_app_income") return "Objet obligatoire.";
  return null;
}

/** Achat carburant, maintenance, recette hors app, écart de caisse (montant signé en sortie). */
export function validateAddCashMovement(data: unknown, nowMs: number):
  { kind: CashKind; amount: number; date: string; note: string | null } {
  const d = obj(data);
  const kind = d.kind as CashKind;
  if (!ADDABLE.includes(kind)) throw new ValidationError("Type d'opération invalide.");
  if (typeof d.amount !== "number") throw new ValidationError("Montant invalide.");
  return {
    kind,
    amount: signedCashAmount(kind, d.amount, false),
    date: cashDay(d.date, nowMs),
    note: note(d.note, missingNote(kind)),
  };
}

/** Correction : montant juste saisi (signé d'après le type de la ligne, côté Function). */
export function validateCashCorrection(data: unknown):
  { movementId: string; amount: number; note: string | null } {
  const d = obj(data);
  const movementId = typeof d.movementId === "string" ? d.movementId.trim() : "";
  if (!movementId || movementId.includes("/")) throw new ValidationError("Opération manquante.");
  if (typeof d.amount !== "number" || !Number.isInteger(d.amount)) {
    throw new ValidationError("Montant invalide.");
  }
  return { movementId, amount: d.amount, note: note(d.note, null) };
}
```

Dans `functions/src/finance/validation.ts`, ajouter l'import
`import { cashDay } from "./cash-validation";` et remplacer `validateCredit` par :

```ts
/**
 * Crédit carburant d'un compte par un instructeur ou un admin (spec §11.3).
 * Aucun plafond (décision utilisateur) : un montant entier positif est
 * toujours accepté, y compris 1 000 000. Date : aujourd'hui par défaut.
 */
export function validateCredit(data: unknown, nowMs = Date.now()):
  { userUid: string; amount: number; reason: string | null; date: string } {
  const d = obj(data);
  const userUid = accountUid(d.userUid);
  const amount = amountInt(d.amount);
  if (amount <= 0) throw new ValidationError("Montant invalide.");
  return { userUid, amount, reason: optionalReason(d.reason), date: cashDay(d.date, nowMs) };
}
```

- [ ] **Step 4 : succès**

Run: `cd functions && npm test`
Expected: PASS.

- [ ] **Step 5 : commit**

```bash
git add functions/src/finance/cash-validation.ts functions/src/finance/cash-validation.test.ts functions/src/finance/validation.ts functions/src/finance/validation.test.ts
git commit -m "feat(functions): validation of cash operations and fuel credit date"
```

---

### Task 3 : registre de caisse, Crédit carburant et fin des corrections de solde

**Files:**
- Create: `functions/src/finance/cash-ledger.ts`
- Modify: `functions/src/finance/ledger.ts` (paramètre `id` facultatif)
- Modify: `functions/src/finance/accounts.ts`
- Modify: `functions/src/flights/testkit.ts` (`resetCashbox`)
- Test: `functions/src/finance/accounts.int.test.ts`

**Interfaces:**
- Consumes : Task 1 (`CashKind`), Task 2 (`validateCredit(data, nowMs)`).
- Produces :
  - `cashboxRef(db: Db): DocumentReference` (`cashbox/main`)
  - `readCashbox(tx: Tx, db: Db): Promise<{ balance: number; migrationClosed: boolean }>`
  - `postCashMovement(tx, db, a: { kind: CashKind; amount: number; date: string; userUid: string | null; transactionId: string | null; note: string | null; correctsId: string | null; by: string; currentBalance: number }): { id: string; balanceAfter: number }`
  - `postMovement(..., a: { ...; id?: string })` : `id` impose l'identifiant de la ligne `transactions`.
  - testkit : `resetCashbox(): Promise<void>` (supprime `cashbox/main` et toutes les lignes `cashMovements`).

- [ ] **Step 1 : `resetCashbox` dans le testkit** (`functions/src/flights/testkit.ts`, à la fin)

```ts
/** Caisse vide, reprise en cours : `cashbox/main` est un document global (plan 11). */
export async function resetCashbox(): Promise<void> {
  const lines = await db.collection("cashMovements").get();
  await Promise.all(lines.docs.map((d) => d.ref.delete()));
  await db.collection("cashbox").doc("main").delete();
}
```

- [ ] **Step 2 : tests qui échouent** — dans `functions/src/finance/accounts.int.test.ts`

Ajouter `beforeEach` à l'import de `node:test`, `resetCashbox` à l'import du
testkit, puis, sous les helpers :

```ts
beforeEach(resetCashbox);

const cashbox = async () => (await db.collection("cashbox").doc("main").get()).data();
const cashLines = async () => (await db.collection("cashMovements").get()).docs.map((d) => ({ id: d.id, ...d.data() }));
```

Ajouter les tests :

```ts
test("Crédit carburant : caisse + et compte +, lignes jumelles dans la même opération", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const target = await seedUser({ profile: "eleve", balance: 100_000 });

  await creditAccount(instr, { userUid: target.uid, amount: 50_000, reason: "Espèces", date: "2026-10-12" });

  assert.equal((await cashbox())!.balance, 50_000);
  const [line] = await cashLines();
  const [tx] = await userTx(target.uid);
  assert.equal(line.kind, "fuel_credit");
  assert.equal(line.amount, 50_000);
  assert.equal(line.date, "2026-10-12");
  assert.equal(line.userUid, target.uid);
  assert.equal(line.note, "Espèces");
  assert.equal(line.correctsId, null);
  assert.equal(line.imported, false);
  assert.equal(line.by, instr.uid);
  assert.equal(line.balanceAfter, 50_000);
  assert.equal(line.transactionId, (await db.collection("transactions")
    .where("userUid", "==", target.uid).get()).docs[0].id);
  assert.equal(tx.type, "credit");
  assert.equal(tx.amount, 50_000);
});

test("Crédit carburant sans date : jour du club", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const target = await seedUser({ profile: "eleve" });
  await creditAccount(instr, { userUid: target.uid, amount: 1_000 });
  const [line] = await cashLines();
  assert.equal(line.date, clubDayString(Date.now()));
});

test("Crédit carburant refusé (compte introuvable) : caisse intacte", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await assert.rejects(creditAccount(admin1, { userUid: "inconnu-xyz", amount: 10_000 }),
    (e) => code(e) === "not-found");
  assert.equal(await cashbox(), undefined);
  assert.equal((await cashLines()).length, 0);
});

test("Corriger le solde : sans effet sur la caisse ; refusé une fois la reprise terminée", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const target = await seedUser({ profile: "eleve", balance: 0 });
  await correctAccount(admin1, { userUid: target.uid, newBalance: 20_000, reason: "Reprise acompte LCM" });
  assert.equal(await cashbox(), undefined);

  await db.collection("cashbox").doc("main").set({ balance: 0, migrationClosedAt: new Date() });
  await assert.rejects(
    correctAccount(admin1, { userUid: target.uid, newBalance: 30_000, reason: "Autre" }),
    (e) => code(e) === "failed-precondition" &&
      (e as Error).message === "La reprise est terminée : corrigez le crédit carburant concerné.",
  );
  assert.equal((await getUser(target.uid)).balance, 20_000);
});
```

Importer `clubDayString` depuis `../rules/cash`.

- [ ] **Step 3 : échec attendu**

Run: `cd functions && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`
Expected: `not ok` sur les quatre nouveaux tests (aucune ligne de caisse ; correction acceptée après la reprise).

- [ ] **Step 4 : `postMovement` avec identifiant imposé** (`functions/src/finance/ledger.ts`)

Ajouter `id?: string;` au paramètre `a` (après `currentBalance`) et
remplacer `tx.create(db.collection("transactions").doc(), {` par :

```ts
  const ref = a.id ? db.collection("transactions").doc(a.id) : db.collection("transactions").doc();
  tx.create(ref, {
```

- [ ] **Step 5 : registre de caisse** — `functions/src/finance/cash-ledger.ts`

```ts
// Caisse (spec §11.2) : règle absolue, comme ledger.ts pour les comptes.
// Toute écriture de `cashbox/main.balance` s'accompagne d'une ligne
// `cashMovements` dans la même transaction. L'appelant a lu la caisse
// (readCashbox) avant toute écriture : la lecture de `cashbox/main`
// sérialise les opérations de caisse.
import * as admin from "firebase-admin";
import type { CashKind } from "../rules/cash";

type Db = FirebaseFirestore.Firestore;
type Tx = FirebaseFirestore.Transaction;
const { FieldValue } = admin.firestore;

export const cashboxRef = (db: Db) => db.collection("cashbox").doc("main");

/** Document absent : caisse vide, reprise en cours. */
export async function readCashbox(tx: Tx, db: Db): Promise<{ balance: number; migrationClosed: boolean }> {
  const s = await tx.get(cashboxRef(db));
  return {
    balance: (s.get("balance") as number | undefined) ?? 0,
    migrationClosed: s.get("migrationClosedAt") != null,
  };
}

export function postCashMovement(tx: Tx, db: Db, a: {
  kind: CashKind;
  amount: number;
  date: string;
  userUid: string | null;
  transactionId: string | null;
  note: string | null;
  correctsId: string | null;
  by: string;
  currentBalance: number;
}): { id: string; balanceAfter: number } {
  const balanceAfter = a.currentBalance + a.amount;
  tx.set(cashboxRef(db), { balance: balanceAfter, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  const ref = db.collection("cashMovements").doc();
  tx.create(ref, {
    kind: a.kind,
    amount: a.amount,
    date: a.date,
    userUid: a.userUid,
    transactionId: a.transactionId,
    note: a.note,
    correctsId: a.correctsId,
    imported: false,
    by: a.by,
    at: FieldValue.serverTimestamp(),
    balanceAfter,
  });
  return { id: ref.id, balanceAfter };
}
```

- [ ] **Step 6 : `accounts.ts`** — remplacer `applyMovement`, `creditAccount` et `correctAccount` par :

```ts
/** Crédit carburant (spec §11.3) : caisse + et compte +, dans une seule transaction. */
export async function creditAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const { userUid, amount, reason, date } = asInvalid(() => validateCredit(data));
  const ref = db.collection("users").doc(userUid);
  const lockRef = db.collection("flightLocks").doc(`user_${userUid}`);

  const written = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compte introuvable.");
    await tx.get(lockRef);
    const cash = await readCashbox(tx, db);
    const transactionId = db.collection("transactions").doc().id;
    const balanceAfter = postMovement(tx, db, {
      id: transactionId,
      uid: userUid,
      amount,
      type: "credit",
      reason,
      flightId: null,
      by: me.uid,
      currentBalance: (snap.get("balance") as number | undefined) ?? 0,
    });
    postCashMovement(tx, db, {
      kind: "fuel_credit", amount, date, userUid, transactionId, note: reason,
      correctsId: null, by: me.uid, currentBalance: cash.balance,
    });
    tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
    return { uid: userUid, amount, balanceAfter, type: "credit" as const };
  });
  await notifyMovements(db, me.uid, [written]);
  return { balance: written.balanceAfter };
}

/**
 * Correction : nouveau solde saisi, écart calculé sur le solde lu dans la
 * transaction. Sans effet sur la caisse (reprise de l'existant, spec §11.5) ;
 * refusée une fois la reprise terminée.
 */
export async function correctAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const { userUid, newBalance, reason } = asInvalid(() => validateCorrection(data));
  const ref = db.collection("users").doc(userUid);
  const lockRef = db.collection("flightLocks").doc(`user_${userUid}`);

  const written = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compte introuvable.");
    await tx.get(lockRef);
    if ((await readCashbox(tx, db)).migrationClosed) {
      throw new HttpsError("failed-precondition",
        "La reprise est terminée : corrigez le crédit carburant concerné.");
    }
    const currentBalance = (snap.get("balance") as number | undefined) ?? 0;
    if (newBalance === currentBalance) {
      throw new HttpsError("failed-precondition", `Le solde est déjà de ${formatFcfa(currentBalance)}.`);
    }
    const amount = newBalance - currentBalance;
    const balanceAfter = postMovement(tx, db, {
      uid: userUid, amount, type: "correction", reason, flightId: null, by: me.uid, currentBalance,
    });
    tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
    return { uid: userUid, amount, balanceAfter, type: "correction" as const };
  });
  await notifyMovements(db, me.uid, [written]);
  return { balance: written.balanceAfter };
}
```

Imports : ajouter `import { postCashMovement, readCashbox } from "./cash-ledger";`.
Mettre à jour le commentaire d'en-tête du fichier (Crédit carburant, caisse).

- [ ] **Step 7 : succès**

Run: `cd functions && npm test && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`
Expected: aucun `not ok` (anciens tests de `accounts.int.test.ts` compris).

- [ ] **Step 8 : commit**

```bash
git add functions/src/finance functions/src/flights/testkit.ts
git commit -m "feat(functions): fuel credit feeds the cash box; balance correction closed after migration"
```

---

### Task 4 : opérations, corrections et clôture de la reprise

**Files:**
- Create: `functions/src/finance/cash.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/finance/cash.int.test.ts`

**Interfaces:**
- Consumes : Task 1, Task 2 (`validateAddCashMovement`, `validateCashCorrection`), Task 3 (`readCashbox`, `postCashMovement`, `cashboxRef`, `postMovement` avec `id`, `resetCashbox`).
- Produces (callables) :
  - `addCashMovement({ kind, amount, date?, note? }) → { id: string; balance: number }`
  - `correctCashMovement({ movementId, amount, note? }) → { id: string; balance: number }`
  - `closeMigration() → void`

- [ ] **Step 1 : tests qui échouent** — `functions/src/finance/cash.int.test.ts`

```ts
// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Caisse (spec §11) : opérations, corrections, écart, reprise.
import { beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import { code, db, resetCashbox, seedUser } from "../flights/testkit";
import { creditAccount } from "./accounts";
import { addCashMovement, closeMigration, correctCashMovement } from "./cash";

beforeEach(resetCashbox);

const balance = async () => ((await db.collection("cashbox").doc("main").get()).get("balance") as number) ?? 0;
const line = async (id: string) => (await db.collection("cashMovements").doc(id).get()).data()!;
const userBalance = async (uid: string) => (await db.collection("users").doc(uid).get()).get("balance") as number;
const fuelCreditLine = async (uid: string) =>
  (await db.collection("cashMovements").where("userUid", "==", uid).where("correctsId", "==", null).get()).docs[0];

test("achat carburant par un instructeur : sortie de caisse, ligne non modifiable", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await addCashMovement(instr, { kind: "off_app_income", amount: 100_000, note: "Baptême" });
  const r = await addCashMovement(instr, { kind: "fuel_purchase", amount: 30_000, date: "2026-10-12" });
  assert.equal(r.balance, 70_000);
  assert.equal(await balance(), 70_000);
  const l = await line(r.id);
  assert.equal(l.kind, "fuel_purchase");
  assert.equal(l.amount, -30_000);
  assert.equal(l.date, "2026-10-12");
  assert.equal(l.balanceAfter, 70_000);
  assert.equal(l.by, instr.uid);
});

test("écart de caisse : refusé à un instructeur, accepté pour un admin", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await assert.rejects(addCashMovement(instr, { kind: "cash_gap", amount: -2_000, note: "Comptage" }),
    (e) => code(e) === "permission-denied");
  const r = await addCashMovement(admin1, { kind: "cash_gap", amount: -2_000, note: "Comptage" });
  assert.equal(r.balance, -2_000);
});

test("un lâché : aucune opération de caisse", async () => {
  const lache = await seedUser({ profile: "lache_toute_mission" });
  await assert.rejects(addCashMovement(lache, { kind: "fuel_purchase", amount: 1_000 }),
    (e) => code(e) === "permission-denied");
});

test("deux opérations simultanées : solde et balanceAfter enchaînés", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const [a, b] = await Promise.all([
    addCashMovement(instr, { kind: "off_app_income", amount: 70_000, note: "Baptême A" }),
    addCashMovement(instr, { kind: "off_app_income", amount: 90_000, note: "Baptême B" }),
  ]);
  assert.equal(await balance(), 160_000);
  assert.deepEqual([a.balance, b.balance].sort((x, y) => x - y), [70_000, 160_000]);
});

test("correction d'une dépense : écart en ligne de correction, même date ; successives ; zéro annule", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const r = await addCashMovement(instr, { kind: "maintenance", amount: 86_000, note: "Roue", date: "2026-07-21" });
  const c1 = await correctCashMovement(instr, { movementId: r.id, amount: 68_000, note: "Faute de frappe" });
  const l1 = await line(c1.id);
  assert.equal(l1.kind, "maintenance");
  assert.equal(l1.amount, 18_000);
  assert.equal(l1.correctsId, r.id);
  assert.equal(l1.date, "2026-07-21");
  assert.equal(l1.note, "Correction : Faute de frappe");
  assert.equal(await balance(), -68_000);

  const c2 = await correctCashMovement(instr, { movementId: r.id, amount: 0 });
  assert.equal((await line(c2.id)).amount, 68_000);
  assert.equal((await line(c2.id)).note, "Correction");
  assert.equal(await balance(), 0);

  await assert.rejects(correctCashMovement(instr, { movementId: r.id, amount: 0 }),
    (e) => code(e) === "failed-precondition");
  await assert.rejects(correctCashMovement(instr, { movementId: c1.id, amount: 1_000 }),
    (e) => code(e) === "failed-precondition" &&
      (e as Error).message === "Corrigez l'opération d'origine, pas une correction.");
});

test("correction d'un Crédit carburant : caisse et compte régularisés, sur le solde actuel du compte", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const pilot = await seedUser({ profile: "eleve", balance: 0 });
  await creditAccount(instr, { userUid: pilot.uid, amount: 50_000, date: "2026-10-12" });
  await addCashMovement(instr, { kind: "fuel_purchase", amount: 10_000 });
  await db.collection("users").doc(pilot.uid).update({ balance: 38_000 }); // un vol entre-temps
  const original = await fuelCreditLine(pilot.uid);

  await correctCashMovement(instr, { movementId: original.id, amount: 5_000 });

  assert.equal(await balance(), 5_000 - 10_000);
  assert.equal(await userBalance(pilot.uid), 38_000 - 45_000);
  const txs = (await db.collection("transactions").where("userUid", "==", pilot.uid).get()).docs.map((d) => d.data());
  const fix = txs.find((t) => t.amount === -45_000)!;
  assert.equal(fix.type, "credit");
  assert.equal(fix.reason, "Correction crédit carburant du 12/10/2026");
});

test("Fond initial et écart : correction réservée aux admins", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const gap = await addCashMovement(admin1, { kind: "cash_gap", amount: 5_000, note: "Comptage" });
  await assert.rejects(correctCashMovement(instr, { movementId: gap.id, amount: 4_000 }),
    (e) => code(e) === "permission-denied");
  const opening = db.collection("cashMovements").doc();
  await opening.set({ kind: "opening", amount: 1_000, date: "2025-03-05", correctsId: null, userUid: null });
  await assert.rejects(correctCashMovement(instr, { movementId: opening.id, amount: 2_000 }),
    (e) => code(e) === "permission-denied");
  await correctCashMovement(admin1, { movementId: opening.id, amount: 2_000 });
});

test("opération introuvable : not-found", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await assert.rejects(correctCashMovement(instr, { movementId: "absent", amount: 1 }),
    (e) => code(e) === "not-found");
});

test("Reprise terminée : admin seulement, une seule fois, solde conservé", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await addCashMovement(instr, { kind: "off_app_income", amount: 70_000, note: "Baptême" });
  await assert.rejects(closeMigration(instr), (e) => code(e) === "permission-denied");
  await closeMigration(admin1);
  const box = (await db.collection("cashbox").doc("main").get()).data()!;
  assert.ok(box.migrationClosedAt);
  assert.equal(box.balance, 70_000);
  await assert.rejects(closeMigration(admin1),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "La reprise est déjà terminée.");
});
```

- [ ] **Step 2 : échec attendu**

Run: `cd functions && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`
Expected: FAIL à la compilation, `Cannot find module './cash'`.

- [ ] **Step 3 : implémentation** — `functions/src/finance/cash.ts`

```ts
// Caisse (spec §11.3, §11.4) : opérations, corrections d'une opération
// (jamais d'un solde), clôture de la reprise.
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin, requireStaff } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { CashKind, formatCashDay, signedCashAmount } from "../rules/cash";
import { formatFcfa } from "../rules/pricing";
import { notifyMovements, WrittenMovement } from "../notify/movements";
import { cashboxRef, postCashMovement, readCashbox } from "./cash-ledger";
import { validateAddCashMovement, validateCashCorrection } from "./cash-validation";
import { postMovement } from "./ledger";

export interface CashResult { id: string; balance: number }

const ADMIN_ONLY: readonly CashKind[] = ["cash_gap", "opening"];

export async function addCashMovement(caller: Caller | undefined, data: unknown): Promise<CashResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const m = asInvalid(() => validateAddCashMovement(data, Date.now()));
  if (m.kind === "cash_gap" && !me.isAdmin) {
    throw new HttpsError("permission-denied", "Écart de caisse : réservé aux administrateurs.");
  }
  return db.runTransaction(async (tx) => {
    const cash = await readCashbox(tx, db);
    const r = postCashMovement(tx, db, {
      ...m, userUid: null, transactionId: null, correctsId: null, by: me.uid, currentBalance: cash.balance,
    });
    return { id: r.id, balance: r.balanceAfter };
  });
}

export async function correctCashMovement(caller: Caller | undefined, data: unknown): Promise<CashResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const c = asInvalid(() => validateCashCorrection(data));
  const origRef = db.collection("cashMovements").doc(c.movementId);

  const { result, written } = await db.runTransaction(async (tx) => {
    // Lectures d'abord : ligne d'origine, ses corrections, caisse, compte.
    const orig = await tx.get(origRef);
    if (!orig.exists) throw new HttpsError("not-found", "Opération introuvable.");
    if (orig.get("correctsId")) {
      throw new HttpsError("failed-precondition", "Corrigez l'opération d'origine, pas une correction.");
    }
    const kind = orig.get("kind") as CashKind;
    if (ADMIN_ONLY.includes(kind) && !me.isAdmin) {
      throw new HttpsError("permission-denied", "Réservé aux administrateurs.");
    }
    const target = asInvalid(() => signedCashAmount(kind, c.amount, true));
    const corrections = await tx.get(db.collection("cashMovements").where("correctsId", "==", origRef.id));
    const current = (orig.get("amount") as number) +
      corrections.docs.reduce((s, d) => s + (d.get("amount") as number), 0);
    const delta = target - current;
    if (delta === 0) {
      throw new HttpsError("failed-precondition", `Le montant est déjà de ${formatFcfa(Math.abs(current))}.`);
    }
    const cash = await readCashbox(tx, db);
    const date = orig.get("date") as string;
    const userUid = kind === "fuel_credit" ? (orig.get("userUid") as string | null) ?? null : null;
    let user: FirebaseFirestore.DocumentSnapshot | null = null;
    const lockRef = userUid ? db.collection("flightLocks").doc(`user_${userUid}`) : null;
    if (userUid && lockRef) {
      user = await tx.get(db.collection("users").doc(userUid));
      if (!user.exists) throw new HttpsError("not-found", "Compte de l'adhérent introuvable.");
      await tx.get(lockRef);
    }

    // Écritures : compte de l'adhérent (Crédit carburant), puis caisse.
    let transactionId: string | null = null;
    let written: WrittenMovement | null = null;
    if (userUid && user && lockRef) {
      transactionId = db.collection("transactions").doc().id;
      const balanceAfter = postMovement(tx, db, {
        id: transactionId,
        uid: userUid,
        amount: delta,
        type: "credit",
        reason: `Correction crédit carburant du ${formatCashDay(date)}`,
        flightId: null,
        by: me.uid,
        currentBalance: (user.get("balance") as number | undefined) ?? 0,
      });
      tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
      written = { uid: userUid, amount: delta, balanceAfter, type: "credit" };
    }
    const r = postCashMovement(tx, db, {
      kind, amount: delta, date, userUid, transactionId,
      note: c.note ? `Correction : ${c.note}` : "Correction",
      correctsId: origRef.id, by: me.uid, currentBalance: cash.balance,
    });
    return { result: { id: r.id, balance: r.balanceAfter }, written };
  });
  if (written) await notifyMovements(db, me.uid, [written]);
  return result;
}

/** « Reprise terminée » (spec §11.5) : irréversible. */
export async function closeMigration(caller: Caller | undefined): Promise<void> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(cashboxRef(db));
    if (s.get("migrationClosedAt") != null) {
      throw new HttpsError("failed-precondition", "La reprise est déjà terminée.");
    }
    tx.set(cashboxRef(db), {
      balance: (s.get("balance") as number | undefined) ?? 0,
      migrationClosedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

export const addCashMovementFn = onCall((req) => addCashMovement(req.auth as Caller | undefined, req.data));
export const correctCashMovementFn = onCall((req) => correctCashMovement(req.auth as Caller | undefined, req.data));
export const closeMigrationFn = onCall((req) => closeMigration(req.auth as Caller | undefined));
```

Dans `functions/src/index.ts`, après la ligne de `creditAccount` :

```ts
export {
  addCashMovementFn as addCashMovement,
  correctCashMovementFn as correctCashMovement,
  closeMigrationFn as closeMigration,
} from "./finance/cash";
```

- [ ] **Step 4 : succès**

Run: `cd functions && npm test && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int`
Expected: aucun `not ok`.

- [ ] **Step 5 : commit**

```bash
git add functions/src/finance/cash.ts functions/src/finance/cash.int.test.ts functions/src/index.ts
git commit -m "feat(functions): cash operations, operation corrections, migration closing"
```

---

### Task 5 : règles Firestore de la caisse

**Files:**
- Modify: `firestore.rules`
- Test: `functions/src/security/firestore-rules.int.test.ts`

- [ ] **Step 1 : test qui échoue** (à la fin du fichier ; ajouter dans le
  `beforeEach` existant, après `transactions/t2` :
  `await setDoc(doc(db, "users/adm"), { active: true, isAdmin: true, profile: null });`
  `await setDoc(doc(db, "cashbox/main"), { balance: 0 });`
  `await setDoc(doc(db, "cashMovements/c1"), { kind: "fuel_purchase", amount: -1 });`)

```ts
test("caisse : lecture réservée aux instructeurs et aux admins, aucune écriture client", async () => {
  for (const path of ["cashbox/main", "cashMovements/c1"]) {
    await assertFails(getDoc(doc(as("eleve"), path)));
    await assertSucceeds(getDoc(doc(as("instr"), path)));
    await assertSucceeds(getDoc(doc(as("adm"), path)));
  }
  await assertSucceeds(getDocs(collection(as("instr"), "cashMovements")));
  await assertFails(getDocs(collection(as("eleve"), "cashMovements")));
  await assertFails(setDoc(doc(as("adm"), "cashbox/main"), { balance: 1 }));
  await assertFails(setDoc(doc(as("adm"), "cashMovements/new"), { amount: 1 }));
});
```

- [ ] **Step 2 : échec attendu**

Run: l'intégration (commande des Global Constraints).
Expected: `not ok` sur ce test (lecture instructeur refusée).

- [ ] **Step 3 : règles** — dans `firestore.rules`, après le bloc `transactions` :

```
    // Caisse (spec §11) : instructeurs et admins, lecture seule.
    match /cashbox/{id} { allow read: if isStaff(); }
    match /cashMovements/{id} { allow read: if isStaff(); }
```

Mettre à jour le tableau §7.2 de la spec : ligne `cashbox`, `cashMovements`
— lecture « Instructeurs et admins », écriture client ✗.

- [ ] **Step 4 : succès** — intégration complète, aucun `not ok`.

- [ ] **Step 5 : commit**

```bash
git add firestore.rules functions/src/security/firestore-rules.int.test.ts docs/superpowers/specs/2026-09-25-ulmgap-app-design.md
git commit -m "feat(rules): cash box readable by instructors and admins only"
```

---

### Task 6 : import de l'historique Excel

**Files:**
- Create: `functions/src/admin/import-cashbox.ts`
- Create: `functions/scripts/import-cashbox.js`
- Test: `functions/src/admin/import-cashbox.test.ts` (analyse du CSV)
- Test: `functions/src/admin/import-cashbox.int.test.ts` (écriture)
- Create (hors dépôt) : `docs/caisse-import.csv`

**Interfaces:**
- Consumes : Task 1 (`CASH_KINDS`, `cashSign`, `isValidCashDay`), Task 3 (`cashboxRef`, `resetCashbox`).
- Produces :
  - `parseCashCsv(text: string, nowMs?: number): CashImportRow[]` avec `CashImportRow = { date: string; kind: CashKind; amount: number; note: string }`
  - `importCashbox(db: Db, rows: CashImportRow[]): Promise<{ count: number; balance: number }>`

- [ ] **Step 1 : tests qui échouent**

`functions/src/admin/import-cashbox.test.ts` :

```ts
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { parseCashCsv } from "./import-cashbox";

const NOW = Date.UTC(2026, 9, 14, 12);
const HEAD = "date;kind;amount;note";

test("parseCashCsv : lignes signées, BOM, CRLF, lignes vides, point-virgule dans la note", () => {
  const rows = parseCashCsv(`﻿${HEAD}\r\n2025-03-05;opening;10000000;Fond initial\r\n\r\n` +
    "2026-10-12;fuel_purchase;-220000;ESSENCE\n2026-10-06;fuel_credit;20000;acompte LCM; espèces\n", NOW);
  assert.deepEqual(rows, [
    { date: "2025-03-05", kind: "opening", amount: 10_000_000, note: "Fond initial" },
    { date: "2026-10-12", kind: "fuel_purchase", amount: -220_000, note: "ESSENCE" },
    { date: "2026-10-06", kind: "fuel_credit", amount: 20_000, note: "acompte LCM; espèces" },
  ]);
});

test("parseCashCsv : erreurs avec numéro de ligne", () => {
  const bad: [string, string][] = [
    ["x;y;z;w\n", "En-tête attendu : date;kind;amount;note"],
    [`${HEAD}\n2026-13-01;maintenance;-1;x\n`, "Ligne 2 : date invalide."],
    [`${HEAD}\n2026-10-01;autre;-1;x\n`, "Ligne 2 : type inconnu (autre)."],
    [`${HEAD}\n2026-10-01;maintenance;12,5;x\n`, "Ligne 2 : montant invalide."],
    [`${HEAD}\n2026-10-01;maintenance;1000;x\n`, "Ligne 2 : signe incohérent avec maintenance."],
    [`${HEAD}\n2026-10-01;maintenance;-1000;\n`, "Ligne 2 : libellé d'origine manquant."],
  ];
  for (const [text, message] of bad) assert.throws(() => parseCashCsv(text, NOW), { message });
});
```

`functions/src/admin/import-cashbox.int.test.ts` :

```ts
// Lancé par `npm run test:int` (émulateur Firestore).
import { beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import { db, resetCashbox } from "../flights/testkit";
import { importCashbox } from "./import-cashbox";

beforeEach(resetCashbox);

test("import : lignes triées par date, solde recalculé, reprise en cours", async () => {
  const r = await importCashbox(db, [
    { date: "2026-10-12", kind: "fuel_purchase", amount: -220_000, note: "ESSENCE" },
    { date: "2025-03-05", kind: "opening", amount: 10_000_000, note: "Fond initial" },
    { date: "2025-03-05", kind: "maintenance", amount: -500_000, note: "RESERVOIR" },
  ]);
  assert.deepEqual(r, { count: 3, balance: 9_280_000 });
  const box = (await db.collection("cashbox").doc("main").get()).data()!;
  assert.equal(box.balance, 9_280_000);
  assert.equal(box.migrationClosedAt, null);
  const lines = (await db.collection("cashMovements").orderBy("at").get()).docs.map((d) => d.data());
  assert.deepEqual(lines.map((l) => l.note), ["Fond initial", "RESERVOIR", "ESSENCE"]);
  assert.deepEqual(lines.map((l) => l.balanceAfter), [10_000_000, 9_500_000, 9_280_000]);
  for (const l of lines) {
    assert.equal(l.imported, true);
    assert.equal(l.by, "import");
    assert.equal(l.userUid, null);
    assert.equal(l.correctsId, null);
  }
});

test("import refusé si la caisse contient déjà une opération", async () => {
  await db.collection("cashMovements").doc().set({ kind: "fuel_purchase", amount: -1 });
  await assert.rejects(importCashbox(db, [{ date: "2025-03-05", kind: "opening", amount: 1, note: "x" }]),
    { message: "La caisse contient déjà des opérations : import refusé." });
});
```

- [ ] **Step 2 : échec attendu** — `cd functions && npm test` : FAIL (`./import-cashbox` introuvable).

- [ ] **Step 3 : implémentation** — `functions/src/admin/import-cashbox.ts`

```ts
// Import unique de l'historique de caisse (spec §11.7) : CSV normalisé
// « date;kind;amount;note », montants signés. Aucun compte d'adhérent n'est
// touché. Utilisé par scripts/import-cashbox.js.
import * as admin from "firebase-admin";
import { cashboxRef } from "../finance/cash-ledger";
import { CASH_KINDS, CashKind, cashSign, isValidCashDay } from "../rules/cash";

type Db = FirebaseFirestore.Firestore;
export interface CashImportRow { date: string; kind: CashKind; amount: number; note: string }

const HEADER = "date;kind;amount;note";

export function parseCashCsv(text: string, nowMs = Date.now()): CashImportRow[] {
  const lines = text.replace(/^﻿/, "").split(/\r?\n/);
  if (lines[0]?.trim() !== HEADER) throw new Error(`En-tête attendu : ${HEADER}`);
  const rows: CashImportRow[] = [];
  lines.forEach((line, i) => {
    if (i === 0 || line.trim() === "") return;
    const n = i + 1;
    const [date = "", kind = "", amount = "", ...rest] = line.split(";");
    const note = rest.join(";").trim();
    if (!isValidCashDay(date.trim(), nowMs)) throw new Error(`Ligne ${n} : date invalide.`);
    if (!CASH_KINDS.includes(kind.trim() as CashKind)) throw new Error(`Ligne ${n} : type inconnu (${kind.trim()}).`);
    const k = kind.trim() as CashKind;
    const value = Number(amount.trim());
    if (!/^-?\d+$/.test(amount.trim()) || value === 0) throw new Error(`Ligne ${n} : montant invalide.`);
    const sign = cashSign(k);
    if (sign !== 0 && Math.sign(value) !== sign) throw new Error(`Ligne ${n} : signe incohérent avec ${k}.`);
    if (!note) throw new Error(`Ligne ${n} : libellé d'origine manquant.`);
    rows.push({ date: date.trim(), kind: k, amount: value, note });
  });
  return rows;
}

export async function importCashbox(db: Db, rows: CashImportRow[]): Promise<{ count: number; balance: number }> {
  if (rows.length === 0 || rows.length > 400) throw new Error("Entre 1 et 400 lignes.");
  const existing = await db.collection("cashMovements").limit(1).get();
  if (!existing.empty) throw new Error("La caisse contient déjà des opérations : import refusé.");
  // Tri stable par date : l'ordre du fichier départage un même jour.
  const sorted = rows.map((r, i) => ({ r, i }))
    .sort((a, b) => a.r.date.localeCompare(b.r.date) || a.i - b.i)
    .map((x) => x.r);
  const batch = db.batch();
  const base = Date.now();
  let balance = 0;
  sorted.forEach((r, i) => {
    balance += r.amount;
    batch.create(db.collection("cashMovements").doc(), {
      kind: r.kind, amount: r.amount, date: r.date, userUid: null, transactionId: null,
      note: r.note, correctsId: null, imported: true, by: "import",
      // Ordre de saisie strictement croissant (tri date puis `at` dans l'app).
      at: admin.firestore.Timestamp.fromMillis(base + i),
      balanceAfter: balance,
    });
  });
  batch.set(cashboxRef(db), {
    balance, migrationClosedAt: null, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { count: sorted.length, balance };
}
```

`functions/scripts/import-cashbox.js` :

```js
// Import unique de l'historique de caisse (spec §11.7). Usage :
//   node scripts/import-cashbox.js --project ulmgap-dev --file ../docs/caisse-import.csv [--dry-run]
// --dry-run : analyse le fichier et affiche le total, sans rien écrire.
// Identifiants : gcloud auth application-default login (compte propriétaire du projet).
const fs = require("fs");
const admin = require("firebase-admin");

const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project");
const file = arg("file");
const dryRun = process.argv.includes("--dry-run");
if (!["ulmgap-dev", "ulmgap-prod"].includes(projectId) || !file) {
  console.error("Usage : --project ulmgap-dev|ulmgap-prod --file <caisse.csv> [--dry-run]");
  process.exit(1);
}

// Module compilé : lancer `npm run build` avant ce script.
const { importCashbox, parseCashCsv } = require("../lib/admin/import-cashbox");
const rows = parseCashCsv(fs.readFileSync(file, "utf8"));
const total = rows.reduce((s, r) => s + r.amount, 0);
console.log(`${rows.length} opérations lues, solde calculé : ${total} FCFA.`);
if (dryRun) process.exit(0);

admin.initializeApp({ projectId });
importCashbox(admin.firestore(), rows)
  .then(({ count, balance }) => console.log(`${count} opérations importées dans ${projectId}. Solde : ${balance} FCFA.`))
  .catch((e) => { console.error(e.message); process.exit(1); });
```

- [ ] **Step 4 : succès** — `npm test` puis intégration : aucun `not ok`.

- [ ] **Step 5 : CSV d'import (hors dépôt)** — `docs/caisse-import.csv`

Construire le fichier depuis `docs/caisse Ulmgap.xlsx` (dates en numéro de
série Excel : jour 45658 = 2025-01-01), une ligne par opération, montants
signés, selon §11.7 :
- les trois lignes sans date (fond initial, RESERVOIR, réparation Rotax) : `2025-03-05` ;
- fond initial : `opening` ; RESERVOIR et ESSENCE : `fuel_purchase` ;
- réparation Rotax, huile, pièces Loravia et St Ex, batterie, roue,
  lettres d'immatriculation, flexible et filtre citerne, travaux citerne
  roulante, cadenas et déménagement, nettoyage : `maintenance` ;
- CREDIT VOLS ULM, « vol », acomptes LCM et CNL, LCM : `fuel_credit` ;
- **« vol ww » exclu** ; note = libellé d'origine tel quel.

Vérifier : `cd functions && npm run build && node scripts/import-cashbox.js --project ulmgap-dev --file ../docs/caisse-import.csv --dry-run`
Expected: `25 opérations lues, solde calculé : 3638000 FCFA.` (2 290 000 + 1 348 000).
Vérifier aussi que `git status --short docs` ne montre pas le CSV.
**Faire relire le CSV par l'utilisateur avant tout import.**

- [ ] **Step 6 : commit** (sans le CSV)

```bash
git add functions/src/admin/import-cashbox.ts functions/src/admin/import-cashbox.test.ts functions/src/admin/import-cashbox.int.test.ts functions/scripts/import-cashbox.js
git commit -m "feat(functions): one-shot cash history import script"
```

---

### Task 7 : app, modèle et service de caisse

**Files:**
- Create: `lib/core/cash.dart`
- Create: `lib/data/cash_movement.dart`
- Create: `lib/data/cash_api.dart`
- Modify: `lib/data/services.dart`, `lib/main.dart`
- Modify: `lib/data/finance_api.dart` (`credit` avec `date`)
- Modify: `lib/features/account/movements_list.dart:14` (libellé `credit`)
- Modify: `test/support/fakes.dart` (`FakeCashApi`, `FakeFinanceApi.credit`)
- Test: `test/core/cash_test.dart`, `test/features/account/*` (libellé)

**Interfaces:**
- Produces (Dart) :
  - `enum CashKind { fuelCredit, fuelPurchase, maintenance, offAppIncome, cashGap, opening }` avec `code`, `label`, `icon`, `sign`, `static CashKind? fromCode(String)`, `static const filters`
  - `String cashDayCode(DateTime d)` (`AAAA-MM-JJ`)
  - `int effectiveAmount(CashMovement original, List<CashMovement> all)`
  - `List<CashMovement> cashPeriod(List<CashMovement> all, DateTime from, DateTime to, Set<CashKind> kinds)`
  - `({int entries, int exits}) cashTotals(Iterable<CashMovement> ms)` (`exits` ≤ 0)
  - `String cashTitle(CashMovement m, Map<String, String> shortNames)`
  - `class CashMovement { id, kindCode, amount, date, userUid, note, correctsId, imported, by, at; CashKind? kind; DateTime day; bool isCorrection }`
  - `class Cashbox { balance, migrationClosedAt; bool migrationClosed; static const empty }`
  - `abstract class CashApi { watchCashbox(); watchMovements(); add({kind, amount, date, note}); correct(id, {amount, note}); closeMigration(); }`
  - `FinanceApi.credit(String uid, int amount, String? reason, {DateTime? date})`
  - `AppServices.cash` (`CashApi?`)

- [ ] **Step 1 : test qui échoue** — `test/core/cash_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/cash.dart';
import 'package:ulmgap/data/cash_movement.dart';

CashMovement m(String id, String kind, int amount, String date,
        {String? correctsId, String? userUid, int at = 0}) =>
    CashMovement.fromMap(id, {
      'kind': kind, 'amount': amount, 'date': date, 'correctsId': correctsId,
      'userUid': userUid, 'by': 'x', 'at': DateTime.fromMillisecondsSinceEpoch(at),
    });

void main() {
  test('types : codes, libellés, sens ; cinq filtres sans le Fond initial', () {
    expect(CashKind.fromCode('fuel_credit'), CashKind.fuelCredit);
    expect(CashKind.fromCode('inconnu'), isNull);
    expect(CashKind.fuelPurchase.label, 'Achat carburant');
    expect(CashKind.cashGap.sign, 0);
    expect(CashKind.filters, isNot(contains(CashKind.opening)));
    expect(CashKind.filters.length, 5);
  });

  test('cashDayCode', () {
    expect(cashDayCode(DateTime(2026, 3, 5, 18)), '2026-03-05');
  });

  test('montant juste : origine + corrections', () {
    final all = [
      m('a', 'maintenance', -86000, '2026-07-21'),
      m('c1', 'maintenance', 18000, '2026-07-21', correctsId: 'a'),
      m('b', 'maintenance', -1000, '2026-07-21'),
    ];
    expect(effectiveAmount(all[0], all), -68000);
    expect(effectiveAmount(all[2], all), -1000);
  });

  test('période : bornes [from, to[, filtre, tri date puis saisie décroissants', () {
    final all = [
      m('old', 'maintenance', -1, '2026-09-30'),
      m('a', 'fuel_credit', 10, '2026-10-01', at: 1),
      m('b', 'fuel_purchase', -5, '2026-10-01', at: 2),
      m('c', 'opening', 100, '2026-10-31'),
      m('next', 'fuel_credit', 1, '2026-11-01'),
    ];
    final from = DateTime(2026, 10, 1), to = DateTime(2026, 11, 1);
    expect(cashPeriod(all, from, to, {}).map((e) => e.id), ['c', 'b', 'a']);
    expect(cashPeriod(all, from, to, {CashKind.fuelCredit}).map((e) => e.id), ['a']);
  });

  test('totaux : selon le sens du type ; écart selon son signe ; corrections comprises', () {
    final t = cashTotals([
      m('a', 'fuel_credit', 50000, '2026-10-01'),
      m('c', 'fuel_credit', -20000, '2026-10-01', correctsId: 'a'),
      m('b', 'fuel_purchase', -10000, '2026-10-01'),
      m('g1', 'cash_gap', 3000, '2026-10-01'),
      m('g2', 'cash_gap', -1000, '2026-10-01'),
    ]);
    expect(t.entries, 33000);
    expect(t.exits, -11000);
  });

  test('titre : Crédit carburant XXX, sans adhérent pour une ligne importée', () {
    expect(cashTitle(m('a', 'fuel_credit', 1, '2026-10-01', userUid: 'u1'), {'u1': 'LCM'}),
        'Crédit carburant LCM');
    expect(cashTitle(m('a', 'fuel_credit', 1, '2026-10-01'), {}), 'Crédit carburant');
    expect(cashTitle(m('a', 'maintenance', -1, '2026-10-01'), {}), 'Maintenance');
  });

  test('Cashbox : document absent → vide, reprise en cours', () {
    expect(Cashbox.fromMap(null).balance, 0);
    expect(Cashbox.fromMap(null).migrationClosed, isFalse);
    expect(Cashbox.fromMap({'balance': 5, 'migrationClosedAt': DateTime(2026, 10, 20)}).migrationClosed,
        isTrue);
  });
}
```

Dans le test du libellé d'historique (`grep -rn "movementTypeLabel\|'Crédit'" test/features/account`),
attendre `'Crédit carburant'` pour le type `credit`.

- [ ] **Step 2 : échec attendu** — `fvm flutter test test/core/cash_test.dart` : FAIL (fichiers absents).

- [ ] **Step 3 : implémentation**

`lib/data/cash_movement.dart` :

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/cash.dart';

DateTime _date(Object? v) => v is Timestamp
    ? v.toDate()
    : v is DateTime
        ? v
        : DateTime.fromMillisecondsSinceEpoch(0);

/// Ligne de `cashMovements` (spec §11.2), jamais modifiée.
class CashMovement {
  const CashMovement({
    required this.id,
    required this.kindCode,
    required this.amount,
    required this.date,
    required this.userUid,
    required this.note,
    required this.correctsId,
    required this.imported,
    required this.by,
    required this.at,
  });

  final String id;
  final String kindCode;
  final int amount; // signé : positif = entrée
  final String date; // « AAAA-MM-JJ », jour de l'opération
  final String? userUid;
  final String? note;
  final String? correctsId;
  final bool imported;
  final String by; // uid ou 'import'
  final DateTime at;

  CashKind? get kind => CashKind.fromCode(kindCode);

  /// Minuit (heure locale) du jour de l'opération.
  DateTime get day => DateTime.parse(date);
  bool get isCorrection => correctsId != null;

  factory CashMovement.fromMap(String id, Map<String, dynamic> m) => CashMovement(
        id: id,
        kindCode: (m['kind'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        date: (m['date'] as String?) ?? '1970-01-01',
        userUid: m['userUid'] as String?,
        note: m['note'] as String?,
        correctsId: m['correctsId'] as String?,
        imported: m['imported'] == true,
        by: (m['by'] as String?) ?? '',
        at: _date(m['at']),
      );
}

/// `cashbox/main` : solde et état de la reprise (spec §11.2).
class Cashbox {
  const Cashbox({required this.balance, required this.migrationClosedAt});
  final int balance;
  final DateTime? migrationClosedAt;
  bool get migrationClosed => migrationClosedAt != null;

  static const empty = Cashbox(balance: 0, migrationClosedAt: null);

  factory Cashbox.fromMap(Map<String, dynamic>? m) => m == null
      ? empty
      : Cashbox(
          balance: (m['balance'] as num?)?.toInt() ?? 0,
          migrationClosedAt: m['migrationClosedAt'] == null ? null : _date(m['migrationClosedAt']),
        );
}
```

`lib/core/cash.dart` :

```dart
// Caisse (spec §11) : types d'opération, libellés, icônes, période et
// totaux. Miroir de functions/src/rules/cash.ts.
import 'package:flutter/material.dart';

import '../data/cash_movement.dart';

enum CashKind {
  fuelCredit('fuel_credit', 'Crédit carburant', Icons.payments, 1),
  fuelPurchase('fuel_purchase', 'Achat carburant', Icons.local_gas_station, -1),
  maintenance('maintenance', 'Maintenance', Icons.build, -1),
  offAppIncome('off_app_income', 'Recette hors app', Icons.receipt_long, 1),
  cashGap('cash_gap', 'Écart de caisse', Icons.balance, 0),
  opening('opening', 'Fond initial', Icons.savings, 1);

  const CashKind(this.code, this.label, this.icon, this.sign);
  final String code;
  final String label;
  final IconData icon;

  /// 1 : entrée, −1 : sortie, 0 : les deux (écart de caisse).
  final int sign;

  static CashKind? fromCode(String code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }

  /// Puces de filtre de l'écran Caisse (le Fond initial n'en a pas).
  static const filters = [fuelCredit, fuelPurchase, maintenance, offAppIncome, cashGap];
}

String _two(int n) => n.toString().padLeft(2, '0');

/// « 2026-10-14 » (jour de [d], heure locale).
String cashDayCode(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Montant juste actuel d'une opération : son montant + ses corrections.
int effectiveAmount(CashMovement original, List<CashMovement> all) => all
    .where((m) => m.correctsId == original.id)
    .fold(original.amount, (s, m) => s + m.amount);

/// Opérations dont le jour tombe dans [from, to[, des types [kinds] (vide :
/// toutes), de la plus récente à la plus ancienne (jour, puis saisie).
List<CashMovement> cashPeriod(
    List<CashMovement> all, DateTime from, DateTime to, Set<CashKind> kinds) {
  final out = all
      .where((m) => !m.day.isBefore(from) && m.day.isBefore(to))
      .where((m) => kinds.isEmpty || kinds.contains(m.kind))
      .toList()
    ..sort((a, b) {
      final byDay = b.date.compareTo(a.date);
      return byDay != 0 ? byDay : b.at.compareTo(a.at);
    });
  return out;
}

/// Entrées (≥ 0) et sorties (≤ 0) : selon le sens du type, corrections
/// comprises ; un écart de caisse selon son signe.
({int entries, int exits}) cashTotals(Iterable<CashMovement> ms) {
  var entries = 0, exits = 0;
  for (final m in ms) {
    final sign = m.kind?.sign ?? 0;
    final isEntry = sign == 1 || (sign == 0 && m.amount > 0);
    if (isEntry) {
      entries += m.amount;
    } else {
      exits += m.amount;
    }
  }
  return (entries: entries, exits: exits);
}

/// « Crédit carburant LCM », « Maintenance »…
String cashTitle(CashMovement m, Map<String, String> shortNames) {
  final label = m.kind?.label ?? m.kindCode;
  final uid = m.userUid;
  if (m.kind == CashKind.fuelCredit && uid != null) return '$label ${shortNames[uid] ?? '?'}';
  return label;
}
```

`lib/data/cash_api.dart` :

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/cash.dart';
import 'cash_movement.dart';
import 'finance_api.dart' show financeFailureFrom;

/// Caisse (spec §11) : lecture réservée aux instructeurs et aux admins,
/// écritures par les Functions.
abstract class CashApi {
  Stream<Cashbox> watchCashbox();

  /// Toutes les opérations (quelques centaines par an) : filtres et tri
  /// dans l'app (cashPeriod), sans index.
  Stream<List<CashMovement>> watchMovements();

  /// [amount] positif pour une entrée ou une sortie, signé pour un écart.
  Future<void> add({required CashKind kind, required int amount, required DateTime date, String? note});

  /// [amount] : montant juste (positif, signé pour un écart ; 0 annule).
  Future<void> correct(String movementId, {required int amount, String? note});

  Future<void> closeMigration();
}

class FirebaseCashApi implements CashApi {
  FirebaseCashApi({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  Future<Object?> _call(String name, Map<String, dynamic> payload) async {
    try {
      return (await _fn.httpsCallable(name).call(payload)).data;
    } on FirebaseFunctionsException catch (e) {
      throw financeFailureFrom(e.code, e.message ?? e.code, e.details) ?? e;
    }
  }

  @override
  Stream<Cashbox> watchCashbox() =>
      _db.collection('cashbox').doc('main').snapshots().map((s) => Cashbox.fromMap(s.data()));

  @override
  Stream<List<CashMovement>> watchMovements() => _db
      .collection('cashMovements')
      .snapshots()
      .map((q) => q.docs.map((d) => CashMovement.fromMap(d.id, d.data())).toList());

  @override
  Future<void> add({required CashKind kind, required int amount, required DateTime date, String? note}) =>
      _call('addCashMovement', {
        'kind': kind.code,
        'amount': amount,
        'date': cashDayCode(date),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<void> correct(String movementId, {required int amount, String? note}) =>
      _call('correctCashMovement', {
        'movementId': movementId,
        'amount': amount,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<void> closeMigration() => _call('closeMigration', {});
}
```

`FinanceApi.credit` : signature `Future<int> credit(String uid, int amount, String? reason, {DateTime? date});`
et, dans `FirebaseFinanceApi.credit`, ajouter au payload
`if (date != null) 'date': cashDayCode(date),` (import `../core/cash.dart`).

`AppServices` : champ `final CashApi? cash;` (doc : « Plan 11 : caisse ;
null en test si l'écran n'en a pas besoin »), paramètre `this.cash`, et
`cash != old.cash` dans `updateShouldNotify`. `main.dart` : `cash: FirebaseCashApi(),`.

`movements_list.dart` : `'credit' => 'Crédit carburant',`.

Dans `test/features/instructors/instructors_screen_test.dart`, test
« crédit : appel avec le bon montant et SnackBar » : l'attente devient
`{'uid': 'u1', 'amount': 12000, 'reason': null, 'date': null}` (le
dialogue n'envoie la date qu'à la Task 9).

`test/support/fakes.dart` : `FakeFinanceApi.credit` reçoit `{DateTime? date}`
et l'enregistre (`'date': date`) ; ajouter :

```dart
class FakeCashApi implements CashApi {
  Cashbox cashbox = Cashbox.empty;
  List<CashMovement> movements = [];
  Object? failWith;
  final added = <Map<String, dynamic>>[];
  final corrected = <Map<String, dynamic>>[];
  int migrationClosings = 0;

  void _fail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<Cashbox> watchCashbox() => Stream.value(cashbox);

  @override
  Stream<List<CashMovement>> watchMovements() => Stream.value(movements);

  @override
  Future<void> add({required CashKind kind, required int amount, required DateTime date, String? note}) async {
    _fail();
    added.add({'kind': kind, 'amount': amount, 'date': date, 'note': note});
  }

  @override
  Future<void> correct(String movementId, {required int amount, String? note}) async {
    _fail();
    corrected.add({'id': movementId, 'amount': amount, 'note': note});
  }

  @override
  Future<void> closeMigration() async {
    _fail();
    migrationClosings++;
  }
}
```

- [ ] **Step 4 : succès** — `fvm flutter test && fvm flutter analyze` : tout vert, aucun problème.

- [ ] **Step 5 : commit**

```bash
git add lib test
git commit -m "feat(app): cash box model, CashApi service, fuel credit label and date"
```

---

### Task 8 : écran « Caisse » et icône de navigation

**Files:**
- Create: `lib/features/cash/cash_screen.dart`
- Create: `lib/features/cash/cash_dialogs.dart`
- Modify: `lib/features/home/app_nav.dart`
- Test: `test/features/cash/cash_screen_test.dart`
- Test: `test/features/home/home_shell_test.dart` (360 px, 5 icônes)

**Interfaces:**
- Consumes : Task 7 (tout), `PeriodSelector` / `initialPeriod`
  (`lib/features/logbook/period_selector.dart`), `signedFcfa`
  (`lib/features/account/movements_list.dart`), `sortedByProfile`
  (`lib/core/profiles.dart`), `AmountInputFormatter`, `parseAmount`,
  `formatFcfa`, `formatAmountInput` (`lib/core/money.dart`),
  `formatShortDate` (`lib/core/formats.dart`), `FlightFailure`.
- Produces : `CashScreen({required AppUser me, DateTime Function() now = DateTime.now})`,
  `CashOperationDialog({required bool isAdmin, required List<AppUser> accounts, required DateTime Function() now})`,
  `CashMovementDialog({required CashMovement movement, required List<CashMovement> all, required String title, required Map<String,String> shortNames, required bool isAdmin})`,
  `AppDestination.cash`.

- [ ] **Step 1 : tests qui échouent** — `test/features/cash/cash_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/cash.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/cash_movement.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/cash/cash_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 14, 10);
final instr = testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS');
final adm = testUser(uid: 'adm', profile: null, isAdmin: true, shortName: 'ADM');

CashMovement line(String id, String kind, int amount, String date,
        {String? userUid, String? correctsId, String? note}) =>
    CashMovement.fromMap(id, {
      'kind': kind, 'amount': amount, 'date': date, 'userUid': userUid,
      'correctsId': correctsId, 'note': note, 'by': 'ins', 'at': DateTime(2026, 10, 14),
    });

Widget host(AppUser me, FakeCashApi cash, FakeFinanceApi finance) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: finance,
      cash: cash,
      child: MaterialApp(home: CashScreen(me: me, now: () => now)),
    );

FakeFinanceApi accounts() => FakeFinanceApi()
  ..accounts = [
    testUser(uid: 'lcm', shortName: 'LCM', balance: 70000),
    testUser(uid: 'cnl', shortName: 'CNL', balance: -20000),
  ];

void main() {
  testWidgets('en-tête : caisse, avoirs adhérents, disponible', (tester) async {
    final cash = FakeCashApi()..cashbox = const Cashbox(balance: 3638000, migrationClosedAt: null);
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    expect(find.text('Caisse : 3 638 000 FCFA'), findsOneWidget);
    expect(find.text('Avoirs adhérents : 50 000 FCFA'), findsOneWidget);
    expect(find.text('Disponible : 3 588 000 FCFA'), findsOneWidget);
  });

  testWidgets('liste du mois, titres, mention Correction, totaux ; filtre par puce', (tester) async {
    final cash = FakeCashApi()
      ..movements = [
        line('a', 'fuel_credit', 50000, '2026-10-12', userUid: 'lcm'),
        line('c', 'fuel_credit', -20000, '2026-10-12', userUid: 'lcm', correctsId: 'a', note: 'Correction'),
        line('b', 'fuel_purchase', -220000, '2026-10-12', note: 'ESSENCE'),
        line('old', 'maintenance', -1000, '2026-09-30'),
      ];
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    expect(find.text('Crédit carburant LCM'), findsNWidgets(2));
    expect(find.text('Achat carburant'), findsWidgets); // puce + ligne
    expect(find.textContaining('Correction'), findsOneWidget);
    expect(find.text('Entrées : +30 000 FCFA · Sorties : −220 000 FCFA'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget); // puce seulement : hors période

    await tester.tap(find.widgetWithText(FilterChip, 'Achat carburant'));
    await tester.pump();
    expect(find.text('Crédit carburant LCM'), findsNothing);
    expect(find.text('Entrées : +0 FCFA · Sorties : −220 000 FCFA'), findsOneWidget);
  });

  testWidgets('période vide : message', (tester) async {
    await tester.pumpWidget(host(instr, FakeCashApi(), accounts()));
    await tester.pump();
    expect(find.text('Aucune opération sur cette période.'), findsOneWidget);
  });

  testWidgets('+ Opération : dépense de maintenance envoyée ; écart absent pour un instructeur',
      (tester) async {
    final cash = FakeCashApi();
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.text('Opération'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Écart de caisse'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Maintenance'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('cash-amount')), '10000');
    await tester.tap(find.text('Valider'));
    await tester.pump();
    expect(find.text('Objet obligatoire.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cash-note')), 'Nettoyage ULM');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(cash.added.single['kind'], CashKind.maintenance);
    expect(cash.added.single['amount'], 10000);
    expect(cash.added.single['note'], 'Nettoyage ULM');
    expect(find.text('Opération enregistrée.'), findsOneWidget);
  });

  testWidgets('+ Opération : Crédit carburant passe par finance.credit avec la date', (tester) async {
    final finance = accounts();
    await tester.pumpWidget(host(instr, FakeCashApi(), finance));
    await tester.pump();
    await tester.tap(find.text('Opération'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cash-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('LCM').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cash-amount')), '20000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(finance.credited.single['uid'], 'lcm');
    expect(finance.credited.single['amount'], 20000);
    expect(finance.credited.single['date'], DateTime(2026, 10, 14));
  });

  testWidgets('appui sur une ligne : détail et correction au montant juste', (tester) async {
    final cash = FakeCashApi()
      ..movements = [line('b', 'maintenance', -86000, '2026-10-12', note: 'Roue')];
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.textContaining('Roue').first);
    await tester.pumpAndSettle();
    expect(find.text('Montant juste : 86 000 FCFA'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cash-correct-amount')), '68000');
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(cash.corrected.single, {'id': 'b', 'amount': 68000, 'note': null});
  });

  testWidgets('écart de caisse : pas de correction pour un instructeur', (tester) async {
    final cash = FakeCashApi()..movements = [line('g', 'cash_gap', -2000, '2026-10-12', note: 'Comptage')];
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.textContaining('Comptage').first);
    await tester.pumpAndSettle();
    expect(find.text('Corriger'), findsNothing);
  });

  testWidgets('admin : Reprise terminée avec confirmation, puis date affichée', (tester) async {
    final cash = FakeCashApi();
    await tester.pumpWidget(host(adm, cash, accounts()));
    await tester.pump();
    await tester.tap(find.text('Reprise terminée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(cash.migrationClosings, 1);

    cash.cashbox = Cashbox(balance: 0, migrationClosedAt: DateTime(2026, 10, 20));
    await tester.pumpWidget(host(adm, cash, accounts()));
    await tester.pump();
    expect(find.text('Reprise terminée le 20/10/2026'), findsOneWidget);
  });

  testWidgets('instructeur : pas de bouton Reprise terminée', (tester) async {
    await tester.pumpWidget(host(instr, FakeCashApi(), accounts()));
    await tester.pump();
    expect(find.text('Reprise terminée'), findsNothing);
  });
}
```

Dans `test/features/home/home_shell_test.dart`, test « admin sur 360 px » :
ajouter `cash: FakeCashApi(),` au `host` et `'Caisse'` à la liste des
icônes vérifiées ; ajouter un test « Caisse : visible pour un instructeur,
absente pour un élève » (`find.byTooltip('Caisse')`).

- [ ] **Step 2 : échec attendu** — `fvm flutter test test/features/cash test/features/home` : FAIL.

- [ ] **Step 3 : implémentation**

`lib/features/home/app_nav.dart` : `AppDestination.cash` (après
`instructors`), `AppDestination.cash => CashScreen(me: user),` et, après
l'icône « Pilotes » (même condition `user.isInstructor || user.isAdmin`) :

```dart
      IconButton(
        tooltip: 'Caisse',
        icon: const Icon(Icons.point_of_sale),
        onPressed: go(AppDestination.cash),
      ),
```

`lib/features/cash/cash_screen.dart` :

```dart
// Écran « Caisse » (spec §11.6), instructeurs et admins : en-tête (caisse,
// avoirs adhérents, disponible), reprise (admins), période, filtres,
// totaux et opérations.
import 'package:flutter/material.dart';

import '../../core/cash.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../data/app_user.dart';
import '../../data/cash_movement.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';
import '../account/movements_list.dart' show signedFcfa;
import '../home/app_nav.dart';
import '../logbook/period_selector.dart';
import 'cash_dialogs.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key, required this.me, this.now = DateTime.now});
  final AppUser me;
  final DateTime Function() now;

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  late DateTime _from;
  late DateTime _to;
  final _kinds = <CashKind>{};

  @override
  void initState() {
    super.initState();
    final p = initialPeriod(widget.now());
    _from = p.from;
    _to = p.to;
  }

  Future<void> _closeMigration() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reprise terminée'),
        content: const Text('Après cela, « Corriger le solde » ne sera plus possible : '
            'seules les corrections d\'opération resteront. Irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppServices.of(context).cash!.closeMigration();
      messenger.showSnackBar(const SnackBar(content: Text('Reprise terminée.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e is FlightFailure ? e.message : 'Opération incertaine : vérifiez la caisse.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final cash = services.cash!;
    final me = widget.me;
    return StreamBuilder<List<AppUser>>(
      stream: services.finance!.watchAccounts(),
      builder: (context, accSnap) {
        final accounts = accSnap.data ?? const <AppUser>[];
        final names = {for (final a in accounts) a.uid: a.shortName};
        return Scaffold(
          appBar: AppBar(
            title: const Text('Caisse'),
            actions: appNavActions(context, me, current: AppDestination.cash),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Opération'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  CashOperationDialog(isAdmin: me.isAdmin, accounts: accounts, now: widget.now),
            ),
          ),
          body: StreamBuilder<Cashbox>(
            stream: cash.watchCashbox(),
            builder: (context, boxSnap) {
              final box = boxSnap.data ?? Cashbox.empty;
              final holdings = accounts.fold(0, (s, a) => s + a.balance);
              return StreamBuilder<List<CashMovement>>(
                stream: cash.watchMovements(),
                builder: (context, mvSnap) {
                  final all = mvSnap.data ?? const <CashMovement>[];
                  final shown = cashPeriod(all, _from, _to, _kinds);
                  final totals = cashTotals(shown);
                  final closedAt = box.migrationClosedAt;
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Caisse : ${formatFcfa(box.balance)}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          Text('Avoirs adhérents : ${formatFcfa(holdings)}'),
                          Text('Disponible : ${formatFcfa(box.balance - holdings)}'),
                          if (me.isAdmin)
                            closedAt == null
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton(
                                        onPressed: _closeMigration,
                                        child: const Text('Reprise terminée')),
                                  )
                                : Text('Reprise terminée le ${formatShortDate(closedAt)}'),
                        ]),
                      ),
                      PeriodSelector(
                        now: widget.now,
                        onChanged: (from, to) => setState(() {
                          _from = from;
                          _to = to;
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(spacing: 8, children: [
                          for (final k in CashKind.filters)
                            FilterChip(
                              avatar: Icon(k.icon, size: 18),
                              label: Text(k.label),
                              selected: _kinds.contains(k),
                              onSelected: (on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                            ),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Entrées : +${formatFcfa(totals.entries)}'
                            ' · Sorties : ${formatFcfa(totals.exits)}'),
                      ),
                      if (shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucune opération sur cette période.'),
                        ),
                      for (final m in shown) _CashTile(m, all: all, names: names, isAdmin: me.isAdmin),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _CashTile extends StatelessWidget {
  const _CashTile(this.m, {required this.all, required this.names, required this.isAdmin});
  final CashMovement m;
  final List<CashMovement> all;
  final Map<String, String> names;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final title = cashTitle(m, names);
    // La note d'une correction commence toujours par « Correction » (serveur).
    final subtitle = [
      formatShortDate(m.day),
      if (m.note != null && m.note!.isNotEmpty) m.note!,
    ].join(' · ');
    return ListTile(
      leading: Icon(m.kind?.icon ?? Icons.help_outline),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        signedFcfa(m.amount),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: m.amount < 0 ? Theme.of(context).colorScheme.error : Colors.green.shade700,
        ),
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => CashMovementDialog(
            movement: m, all: all, title: title, shortNames: names, isAdmin: isAdmin),
      ),
    );
  }
}
```

(`formatFcfa` d'un négatif affiche déjà « −220 000 FCFA », signe U+2212.)

`lib/features/cash/cash_dialogs.dart` :

```dart
// Dialogues de la caisse (spec §11.6) : nouvelle opération, détail et
// correction d'une opération (montant juste).
import 'package:flutter/material.dart';

import '../../core/cash.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../core/profiles.dart';
import '../../data/app_user.dart';
import '../../data/cash_movement.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';

const _uncertain = 'Opération incertaine : vérifiez la caisse avant de réessayer.';

Widget _error(BuildContext context, String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );

class CashOperationDialog extends StatefulWidget {
  const CashOperationDialog({super.key, required this.isAdmin, required this.accounts, required this.now});
  final bool isAdmin;
  final List<AppUser> accounts;
  final DateTime Function() now;

  @override
  State<CashOperationDialog> createState() => _CashOperationDialogState();
}

class _CashOperationDialogState extends State<CashOperationDialog> {
  CashKind _kind = CashKind.fuelCredit;
  String? _account;
  late DateTime _date = dayOf(widget.now());
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _noteLabel => switch (_kind) {
        CashKind.cashGap => 'Motif (obligatoire)',
        CashKind.maintenance || CashKind.offAppIncome => 'Objet (obligatoire)',
        _ => 'Note (facultative)',
      };

  String? _check(int? amount, String note) {
    if (amount == null || amount == 0 || (_kind != CashKind.cashGap && amount < 0)) {
      return _kind == CashKind.cashGap ? 'Montant invalide (non nul).' : 'Montant invalide (positif).';
    }
    if (_kind == CashKind.fuelCredit && _account == null) return 'Choisissez l\'adhérent.';
    if (_kind == CashKind.cashGap && note.isEmpty) return 'Motif obligatoire pour un écart de caisse.';
    if ((_kind == CashKind.maintenance || _kind == CashKind.offAppIncome) && note.isEmpty) {
      return 'Objet obligatoire.';
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = parseAmount(_amount.text);
    final note = _note.text.trim();
    final error = _check(amount, note);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final services = AppServices.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      if (_kind == CashKind.fuelCredit) {
        await services.finance!.credit(_account!, amount!, note.isEmpty ? null : note, date: _date);
      } else {
        await services.cash!.add(kind: _kind, amount: amount!, date: _date, note: note.isEmpty ? null : note);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Opération enregistrée.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is FlightFailure ? e.message : _uncertain;
      });
    }
  }

  Future<void> _pickDate() async {
    final today = dayOf(widget.now());
    final picked = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: today);
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [
      CashKind.fuelCredit, CashKind.fuelPurchase, CashKind.maintenance, CashKind.offAppIncome,
      if (widget.isAdmin) CashKind.cashGap,
    ];
    final accounts = sortedByProfile(widget.accounts, (a) => a.profile, (a) => a.displayName);
    return AlertDialog(
      title: const Text('Nouvelle opération'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in kinds)
              ChoiceChip(
                avatar: Icon(k.icon, size: 18),
                label: Text(k.label),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ]),
          if (_kind == CashKind.fuelCredit)
            DropdownButtonFormField<String>(
              key: const Key('cash-account'),
              value: _account,
              decoration: const InputDecoration(labelText: 'Adhérent'),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.uid, child: Text('${a.shortName} · ${a.displayName}')),
              ],
              onChanged: (v) => setState(() => _account = v),
            ),
          TextField(
            key: const Key('cash-amount'),
            controller: _amount,
            keyboardType: TextInputType.numberWithOptions(signed: _kind == CashKind.cashGap),
            inputFormatters: const [AmountInputFormatter()],
            decoration: InputDecoration(
                labelText: _kind == CashKind.cashGap ? 'Montant (signé)' : 'Montant'),
          ),
          TextButton.icon(
            key: const Key('cash-date'),
            icon: const Icon(Icons.event),
            label: Text('Date : ${formatShortDate(_date)}'),
            onPressed: _pickDate,
          ),
          TextField(
            key: const Key('cash-note'),
            controller: _note,
            maxLength: 200,
            decoration: InputDecoration(labelText: _noteLabel),
          ),
          _error(context, _error),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Valider')),
      ],
    );
  }
}

class CashMovementDialog extends StatefulWidget {
  const CashMovementDialog({
    super.key,
    required this.movement,
    required this.all,
    required this.title,
    required this.shortNames,
    required this.isAdmin,
  });
  final CashMovement movement;
  final List<CashMovement> all;
  final String title;
  final Map<String, String> shortNames;
  final bool isAdmin;

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _submitting = false;

  CashMovement get m => widget.movement;
  int get _current => effectiveAmount(m, widget.all);
  bool get _isGap => m.kind == CashKind.cashGap;

  bool get _canCorrect =>
      !m.isCorrection &&
      m.kind != null &&
      (widget.isAdmin || (m.kind != CashKind.cashGap && m.kind != CashKind.opening));

  @override
  void initState() {
    super.initState();
    _amount.text = formatAmountInput(_isGap ? _current : _current.abs());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _correct() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || (!_isGap && amount < 0)) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    if ((_isGap ? amount : amount * (m.kind!.sign)) == _current) {
      setState(() => _error = 'Le montant est déjà de ${formatFcfa(_current.abs())}.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final note = _note.text.trim();
      await AppServices.of(context).cash!.correct(m.id, amount: amount, note: note.isEmpty ? null : note);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Correction enregistrée.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is FlightFailure ? e.message : _uncertain;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final by = m.by == 'import' ? 'Import' : (widget.shortNames[m.by] ?? m.by);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Date : ${formatShortDate(m.day)}'),
          Text('Montant : ${formatFcfa(m.amount)}'),
          if (m.note != null && m.note!.isNotEmpty) Text('Note : ${m.note}'),
          Text('Saisie : $by, le ${formatShortDate(m.at)}'),
          if (m.isCorrection) const Text('Correction d\'une opération.'),
          if (!m.isCorrection) Text('Montant juste : ${formatFcfa(_current.abs())}'),
          if (_canCorrect) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('cash-correct-amount'),
              controller: _amount,
              keyboardType: TextInputType.numberWithOptions(signed: _isGap),
              inputFormatters: const [AmountInputFormatter()],
              decoration: const InputDecoration(labelText: 'Montant juste (0 annule)'),
            ),
            TextField(
              key: const Key('cash-correct-note'),
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
            ),
          ],
          _error(context, _error),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        if (_canCorrect)
          FilledButton(onPressed: _submitting ? null : _correct, child: const Text('Corriger')),
      ],
    );
  }
}
```

- [ ] **Step 4 : succès** — `fvm flutter test && fvm flutter analyze` : tout vert, aucun problème.

- [ ] **Step 5 : commit**

```bash
git add lib/features/cash lib/features/home/app_nav.dart test/features/cash test/features/home
git commit -m "feat(app): Caisse screen (header, migration, period, filters, totals, operations, corrections)"
```

---

### Task 9 : écran Pilotes — Crédit carburant daté, correction de solde masquée après la reprise

**Files:**
- Modify: `lib/features/instructors/credit_dialog.dart`
- Modify: `lib/features/instructors/instructors_screen.dart`
- Test: `test/features/instructors/instructors_screen_test.dart`

**Interfaces:**
- Consumes : Task 7 (`AppServices.cash`, `Cashbox`, `FinanceApi.credit(..., date:)`).

- [ ] **Step 1 : tests qui échouent** — dans `instructors_screen_test.dart`

Remplacer partout `'Créditer / corriger'` par `'Crédit carburant / corriger'`
et le tooltip `'Créditer'` par `'Crédit carburant'`. Changer `host` :

```dart
Widget host(FakeFinanceApi finance, {FakeCashApi? cash}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: finance,
      cash: cash ?? FakeCashApi(),
      child: const MaterialApp(home: InstructorsScreen()),
    );
```

Dans le test « crédit : appel avec le bon montant et SnackBar », l'attente
devient :

```dart
    final today = DateTime.now();
    expect(finance.credited.single,
        {'uid': 'u1', 'amount': 12000, 'reason': null,
         'date': DateTime(today.year, today.month, today.day)});
```

Ajouter :

```dart
  testWidgets('reprise terminée : plus de puce « Corriger »', (tester) async {
    final finance = FakeFinanceApi()..accounts = [_account('u1', 'Jean Dupont', balance: 0)];
    final cash = FakeCashApi()
      ..cashbox = Cashbox(balance: 0, migrationClosedAt: DateTime(2026, 10, 20));
    await tester.pumpWidget(host(finance, cash: cash));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crédit carburant / corriger'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Corriger'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Crédit carburant'), findsOneWidget);
    expect(find.byKey(const Key('credit-date')), findsOneWidget);
  });

  testWidgets('reprise en cours : puce « Corriger » présente', (tester) async {
    final finance = FakeFinanceApi()..accounts = [_account('u1', 'Jean Dupont', balance: 0)];
    await tester.pumpWidget(host(finance));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crédit carburant / corriger'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Corriger'), findsOneWidget);
  });
```

(import `package:ulmgap/data/cash_movement.dart`). Le titre du dialogue
devient lui aussi « Crédit carburant / corriger » : là où le test tape ce
texte pour ouvrir le dialogue, utiliser `find.text(...).last` si deux
widgets le portent.

- [ ] **Step 2 : échec attendu** — `fvm flutter test test/features/instructors` : FAIL.

- [ ] **Step 3 : implémentation**

`credit_dialog.dart` :
- titre `'Crédit carburant / corriger'`, puce `'Crédit carburant'` ;
- envelopper le contenu dans un `StreamBuilder<Cashbox>` sur
  `AppServices.of(context).cash?.watchCashbox() ?? Stream.value(Cashbox.empty)` ;
  la puce « Corriger » n'est affichée que si `!box.migrationClosed` ; si la
  reprise se termine pendant que le mode « Corriger » est actif, revenir au
  mode crédit (`final mode = box.migrationClosed ? _Mode.credit : _mode;`
  et utiliser `mode` dans `build` et `_submit` — garder `box` dans un champ
  `_migrationClosed` mis à jour par le builder) ;
- en mode crédit, sous le montant, le bouton de date (même widget que
  `CashOperationDialog`, clé `Key('credit-date')`, date du jour par défaut,
  `lastDate` aujourd'hui) ;
- `finance.credit(widget.uid, amount, reason.isEmpty ? null : reason, date: _date)` (correction inchangée) ;
- mettre à jour le commentaire d'en-tête (Crédit carburant, reprise).

`instructors_screen.dart` : tooltip `'Crédit carburant'`, libellé du bouton
flottant `'Crédit carburant / corriger'`, commentaire d'en-tête.

- [ ] **Step 4 : succès** — `fvm flutter test && fvm flutter analyze`.

- [ ] **Step 5 : commit**

```bash
git add lib/features/instructors test/features/instructors
git commit -m "feat(app): fuel credit with date in Pilotes; balance correction hidden after migration"
```

---

### Task 10 : docs, vérification complète, déploiement et import en dev

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1 : vérification complète**

```bash
fvm flutter test && fvm flutter analyze
cd functions && npm test
cd functions && JAVA_HOME=/opt/android-studio/jbr PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int
```

Expected : tout vert, aucun `not ok`.

- [ ] **Step 2 : `CLAUDE.md`**

Ajouter le plan 11 dans « Documents de référence » et le découpage (« 11.
suivi de caisse ; 12. vol technique ; 13. suivi de cuve »). Dans « État » :
plan 11 en dev (Functions `creditAccount`, `correctAccount`,
`addCashMovement`, `correctCashMovement`, `closeMigration` et règles
déployées ; **l'app installée en dev doit être reconstruite** ; import de
la caisse fait ou à faire). Dans la liste prod : règles et ces Functions à
déployer avec l'app web, puis import
(`node scripts/import-cashbox.js --project ulmgap-prod --file …`),
comptage, reprises par « Corriger le solde », « Reprise terminée ».

- [ ] **Step 3 : commit**

```bash
git add CLAUDE.md
git commit -m "docs: plan 11 (cash box) state and deployment notes"
```

- [ ] **Step 4 : déploiement dev** (jamais prod)

```bash
firebase deploy --project dev --only firestore:rules,functions:creditAccount,functions:correctAccount,functions:addCashMovement,functions:correctCashMovement,functions:closeMigration
```

- [ ] **Step 5 : import en dev** — **après relecture du CSV par l'utilisateur**

```bash
cd functions && npm run build && node scripts/import-cashbox.js --project ulmgap-dev --file ../docs/caisse-import.csv
```

Expected : `25 opérations importées dans ulmgap-dev. Solde : 3638000 FCFA.`
Si les identifiants ADC manquent, demander à l'utilisateur de lancer
`gcloud auth application-default login`.

- [ ] **Step 6 : recette dev par l'utilisateur** (spec §11.8) : écran
  Caisse, Écart de caisse simulé, reprises par « Corriger le solde »,
  « Reprise terminée », Crédit carburant, dépense, correction.
