# UlmGap, plan 3 : finances (tarifs, crédit FCFA, clôture, relevé)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** mettre en place les finances de la spec §4 et les écrans associés
de la §5 :
- les tarifs modifiables par un admin ;
- le coût d'un vol ;
- le contrôle du crédit (dès la demande) ;
- la clôture avec débit ;
- les crédits et corrections ;
- la correction et la suppression de vol par un admin, avec régularisation ;
- les écrans « Mon compte », « Instructeurs », « Tarifs » et « Relevé »
  (export CSV sur le web) ;
- un script de crédit initial en dev.

**Architecture :** celle des plans 2 et 2b.
- Les calculs d'argent sont dans un **module pur**
  `functions/src/rules/pricing.ts`, avec un miroir Dart dans
  `lib/core/pricing.dart`. Les cas partagés sont dans
  `test/fixtures/pricing_cases.json`.
- Toute écriture de solde se fait **dans une transaction Firestore, avec sa
  ligne `transactions`** : le solde n'est jamais modifié sans son historique.
- Les nouvelles lectures de `planFlight` (tarifs, payeur, vols du payeur) se
  font avant toute écriture, comme les lectures existantes.

**Tech Stack :** identique ; ajout du paquet `web` (téléchargement du CSV sur
le web).

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §2.4,
§2.5 (champs financiers), §2.6, §3.3 (`closeFlight`, `adminUpdateFlight`),
§4, §5 (clôture, Mon compte, Instructeurs, Administration : tarifs et relevé).

## Décisions de l'utilisateur (2026-09-29)

1. **Contrôle du crédit dès la demande.** À toute création, modification ou
   validation d'un vol **imputé sur un solde** (mode `standard` ou
   `fuel_only`), que le résultat soit une `demande` ou un vol `valide`, le
   serveur vérifie que le crédit disponible du compte débité couvre le coût
   estimé.
   - Sinon, l'action est refusée avec le montant manquant : pas d'envoi de
     demande sans crédit.
   - **L'admin est soumis aux mêmes règles.**
2. **Clôture** : par tout membre de l'équipage **ou un admin**, une fois
   l'heure de départ passée.
3. **Vols validés avant le plan 3** (sans `pricingSnapshot`) : à la clôture
   et dans le calcul du crédit disponible, on utilise les tarifs courants.
4. **Crédit initial en dev** : un script réservé à la dev crédite
   500 000 FCFA à chaque compte, par une transaction `credit` « Crédit
   initial (tests) », une seule fois par compte. Les vols déjà prévus pèsent
   ensuite sur le crédit disponible, et les vols réalisés seront débités à
   leur clôture.
5. **Plafond de 200 000 FCFA** pour les montants saisis à la clôture d'un vol. **Pas de plafond pour les versements** (crédits).
6. **Format des montants** : `12 000 FCFA`, groupes de 3 chiffres séparés par
   une espace insécable, sans décimales, avec un signe « − » pour un montant
   négatif.
7. **Écran « Instructeurs »** : accessible aux instructeurs et aux admins. Il
   liste les comptes et leur solde, avec « Créditer / corriger ».

## Décisions du contrôleur (à relire)

- **Plafond** : il s'applique seulement à `shortFlightAmount` et
  `customAmount`. Pas de plafond pour les crédits (décision utilisateur), ni
  pour les corrections, pour pouvoir annuler un versement erroné en une
  seule fois.
- **Tarifs absents** : si `settings/pricing` n'existe pas, le serveur utilise
  les valeurs par défaut de la spec §2.4. Le premier enregistrement depuis
  l'écran « Tarifs » crée le document.
- **Durée minimale** : `minPlannedMinutes` est désormais lu dans les tarifs,
  et vérifié dans `planFlight`. La validation pure ne vérifie plus que
  `fin > départ`. Les limites de 12 h et de 366 jours restent codées en dur.
- **`pricingSnapshot`** (tarifs seuls, sans l'appartenance) : il est figé
  lors du passage de `demande` ou `refuse` à `valide`, puis conservé tant que
  le vol reste `valide`. L'appartenance `A` est lue sur le compte débité au
  moment du calcul.
- **Crédit disponible** (spec §4.4) : `balance` moins le coût estimé des
  **autres** vols du compte débité qui sont `valide`, non clôturés, non
  supprimés et imputés sur le solde. Les demandes en attente ne comptent pas.
- **Concurrence** : le verrou `flightLocks/user_<compte débité>` est lu puis
  écrit à chaque contrôle de crédit, et `creditAccount`, `correctAccount` et
  `closeFlight` écrivent le même verrou. Deux opérations sur un même compte
  se sérialisent donc.
- **« Montant à facturer »** (`shortFlightAmount`) : obligatoire quand le vol
  est en mode `standard` et que la durée réelle est inférieure à
  `minPlannedMinutes`. Un vol `fuel_only` est toujours calculé à la minute.
- **« Montant différent (facturé hors app) »** : proposé seulement si le vol
  a un passager sans compte. Le vol passe alors en `custom`, avec
  `billedTo: off_app` et aucun débit.
- **Durée réelle** : un entier de minutes, de 1 à 720.
- **Correction admin (`adminUpdateFlight`)** :
  - Champs modifiables à tout moment : horaires, destination, appareil,
    équipage, passagers, mode, et, sur un vol clôturé, durée réelle et
    montants.
  - Contrôles conservés : composition, conflits (si `valide`), et crédit
    (si le vol n'est pas clôturé et qu'il est imputé sur un solde).
  - Contrôles non appliqués : matrice de droits, comptes et appareils actifs,
    heure passée.
  - Sur un vol clôturé, la **régularisation** est automatique (spec §4.5).
    Elle produit des transactions `flight_adjustment` : remboursement de
    l'ancien débit et débit du nouveau, regroupés par compte, montants nuls
    omis. Pour un vol hors app, seul `billedAmount` est mis à jour.
- **Suppression admin (`adminDeleteFlight`)** : à tout moment. Pour un vol
  clôturé débité sur un compte, on rembourse le compte par une transaction
  `flight_adjustment` de +montant.
- **Historique** : il est trié côté client, avec une requête sur l'égalité
  `userUid` seulement, sans index composite.

## Global Constraints

Celles des plans 2 et 2b restent en vigueur. En particulier :
- `fvm flutter` ;
- **jamais de déploiement en prod** ;
- callables `europe-west1` ;
- les clients n'écrivent jamais `users`, `transactions`, `settings` ni
  `flights` ;
- TDD ;
- français, au vouvoiement ;
- libellés et couleurs de vol dans `lib/features/flight/flight_texts.dart`.

À respecter dans ce plan :
- **Règle absolue** : pas de modification de `users.balance` sans une ligne
  `transactions` dans la **même** transaction Firestore.
  - Champs de la ligne : `userUid`, `amount` (entier, positif pour un
    crédit), `type` (`credit` / `correction` / `flight` /
    `flight_adjustment`), `reason`, `flightId`, `by` (uid ou `system`), `at`
    (horodatage serveur), `balanceAfter`.
- Les coûts sont arrondis au franc le plus proche (`Math.round`).
- Codes d'appartenance : `GAP`, `GR`, `MIL`, `EXT`.
- Tarifs par défaut (§2.4) :
  - `flatFee` : GAP 12 000, GR 30 000, MIL 50 000, EXT 70 000 ;
  - `includedMinutes` : 75 ;
  - `minPlannedMinutes` : 45 ;
  - `overtimeHourly` : GAP 12 000, GR 30 000, MIL 30 000, EXT 30 000 ;
  - `fuelHourlyRate` : 12 000.

## Review Focus

1. **Deux opérations simultanées sur le même compte** (deux demandes, ou une
   demande et un crédit) : le crédit disponible est toujours calculé sur un
   état cohérent. → test d'intégration de concurrence (Task 3).
2. **Deux clôtures simultanées du même vol** : une seule débite. → test
   d'intégration (Task 4).
3. **Correction admin d'un vol clôturé** qui change le compte débité, la
   durée ou le mode (hors app ↔ compte) : les soldes et l'historique restent
   cohérents, et la somme des transactions liées au vol égale le montant
   facturé actuel. → tests d'intégration (Task 6).
4. **Montant de clôture saisi avec un zéro de trop** : refusé au-delà de
   200 000 FCFA, côté serveur comme côté app. → tests (Tasks 4 et 9).
5. **Tarifs modifiés entre la validation et la clôture** : la clôture
   utilise les tarifs figés. → test d'intégration (Task 4).

---

### Task 1 : module pur des coûts et cas partagés

**Files :**
- Create: `functions/src/rules/pricing.ts`, `functions/src/rules/pricing.test.ts`, `test/fixtures/pricing_cases.json`

**Interfaces (`rules/pricing.ts`) :**

```ts
export type Category = "GAP" | "GR" | "MIL" | "EXT";
export interface Pricing {
  flatFee: Record<Category, number>;
  includedMinutes: number;
  minPlannedMinutes: number;
  overtimeHourly: Record<Category, number>;
  fuelHourlyRate: number;
}
export const DEFAULT_PRICING: Pricing;              // valeurs de §2.4
export const MAX_MANUAL_AMOUNT = 200_000;
/** Coût calculé ; null si standard et d < minPlannedMinutes (montant à saisir). */
export function computedCost(mode: "standard" | "fuel_only", minutes: number, category: Category, p: Pricing): number | null;
/** Coût estimé d'un vol prévu (durée prévue ≥ minimum). */
export function estimatedCost(mode: "standard" | "fuel_only", plannedMinutes: number, category: Category, p: Pricing): number;
export function availableCredit(balance: number, otherEstimatedCosts: number[]): number;
/** Montant facturé à la clôture. Lève Error("…") si un montant requis manque. */
export function closingBill(a: {
  mode: "standard" | "fuel_only"; actualMinutes: number; category: Category; pricing: Pricing;
  shortFlightAmount?: number | null; customAmount?: number | null; hasPassenger: boolean;
}): { billedAmount: number; billedTo: "account" | "off_app"; pricingMode: "standard" | "fuel_only" | "custom" };
/** Régularisation : mouvements par compte entre l'ancien et le nouveau débit. */
export function adjustments(
  before: { billedTo: "account" | "off_app" | null; payerUid: string | null; amount: number },
  after: { billedTo: "account" | "off_app" | null; payerUid: string | null; amount: number },
): { uid: string; amount: number }[];
export function toCategory(v: unknown): Category;   // inconnu → "EXT"
```

Règles :
- `standard`, `d ≥ minPlannedMinutes` :
  `flatFee[A] + round(overtimeHourly[A] × max(0, d − includedMinutes) / 60)`.
  L'arrondi porte sur le total : `Math.round(flat + hourly * extra / 60)`.
- `standard`, `d < minPlannedMinutes` : `null`.
- `fuel_only` : `Math.round(fuelHourlyRate × d / 60)`.
- `closingBill` :
  - si `customAmount` est fourni : il faut `hasPassenger`, sinon on lève
    « Montant différent réservé aux vols avec un passager sans compte. ».
    Résultat : `billedTo: off_app`, `pricingMode: "custom"`,
    `billedAmount = customAmount`.
  - sinon, `computedCost`. S'il vaut `null`, on lève si `shortFlightAmount`
    est absent : « Montant à facturer obligatoire pour un vol de moins de
    <min> min. ». Sinon `billedAmount = shortFlightAmount`.
  - Dans ces deux derniers cas : `billedTo: account`, et le mode d'origine
    est conservé.
- `adjustments` :
  - on rembourse `before` (+amount au `payerUid`) si `before.billedTo` vaut
    `account` ;
  - on débite `after` (−amount au `payerUid`) si `after.billedTo` vaut
    `account` ;
  - on regroupe par uid et on omet les totaux nuls. L'ordre du résultat suit
    la première apparition de l'uid.

- [ ] **Step 1 : cas partagés** `test/fixtures/pricing_cases.json`, avec les
  clés `cost`, `closing` et `adjustments`. Cas obligatoires :
  - `cost` (mode, minutes, catégorie → attendu) :
    - les exemples de la spec §4.3 : GAP 60 → 12 000 ; GAP 90 → 15 000 ;
      MIL 75 → 50 000 ; EXT 90 → 77 500 ; EXT 60 → 70 000 ;
    - 75 min pile (GAP) → 12 000 ;
    - 76 min EXT → `70000 + round(30000/60)` = 70 500 ;
    - 44 min standard → `null`, et 45 min → forfait ;
    - `fuel_only` : 60 min → 12 000, 50 min → 10 000, 7 min → 1 400 ;
    - GR 100 min → `30000 + round(30000 × 25 / 60)` = 42 500 ;
    - un arrondi au franc : MIL 77 min → `50000 + round(30000 × 2 / 60)` =
      51 000, et `fuel_only` 1 min → 200.
  - `closing` :
    - standard 90 min GAP → 15 000 sur le compte ;
    - standard 30 min avec `shortFlightAmount` 8 000 → 8 000 sur le compte ;
    - standard 30 min sans montant → erreur ;
    - `customAmount` 50 000 avec passager → `custom`, `off_app`, 50 000 ;
    - `customAmount` sans passager → erreur ;
    - `fuel_only` 30 min → 6 000 sur le compte.
  - `adjustments` :
    - même compte, 15 000 → 18 000 : `[{u1, −3000}]` ;
    - changement de compte, 15 000 (u1) → 15 000 (u2) :
      `[{u1, +15000}, {u2, −15000}]` ;
    - compte → hors app : `[{u1, +15000}]` ;
    - hors app → compte : `[{u1, −12000}]` ;
    - même montant, même compte : `[]`.
- [ ] **Step 2 : tests TS qui échouent** (`pricing.test.ts`) : ils rejouent
  toute la fixture, et vérifient que `DEFAULT_PRICING` reproduit la §2.4
  champ par champ et que `toCategory("XX")` vaut `"EXT"`. Run :
  `cd functions && npm test`. Expected : FAIL.
- [ ] **Step 3 : implémentation** selon les règles ci-dessus. Run : PASS.
- [ ] **Step 4 : commit**
  `feat(functions): pure pricing module (cost, credit, closing bill, adjustments)`.

---

### Task 2 : tarifs (`settings/pricing`) et callable admin

**Files :**
- Create: `functions/src/finance/pricing-store.ts`, `functions/src/finance/validation.ts`, `functions/src/finance/validation.test.ts`, `functions/src/finance/pricing.int.test.ts`
- Modify: `functions/src/index.ts`, `functions/src/flights/validation.ts`, `functions/src/flights/validation.test.ts`

**Interfaces :**
- `readPricing(tx: Transaction, db: Firestore): Promise<Pricing>` : le
  document `settings/pricing` fusionné sur `DEFAULT_PRICING` (un champ
  absent prend la valeur par défaut).
- `validatePricing(data): Pricing` :
  - toutes les clés sont exigées ;
  - les valeurs sont des entiers ;
  - `flatFee`, `overtimeHourly` et `fuelHourlyRate` sont compris entre 0 et
    1 000 000 ;
  - `includedMinutes` est compris entre 1 et 600 ;
  - `minPlannedMinutes` est compris entre 1 et 600 ;
  - message en cas d'erreur : « Tarifs invalides : <champ>. »
- Callable `adminUpdatePricing(pricing)` : admin seulement ; `set` complet
  de `settings/pricing` avec `updatedAt` et `updatedBy`.
- `flights/validation.ts` :
  - `checkDuration` ne vérifie plus que `end > start` (sinon « L'heure de fin
    doit suivre le départ. ») et le maximum de 12 h ;
  - nouvelle fonction exportée
    `checkMinDuration(start, end, minPlannedMinutes)`, avec le message
    « Durée prévue minimale : <n> min. ».

- [ ] **Step 1 : tests qui échouent.**
  - Unitaires : validation des tarifs (cas nominal, champ manquant, négatif,
    décimal) ; `checkDuration` accepte 30 min ; `checkMinDuration` refuse
    44 min avec un minimum de 45.
  - Intégration :
    - `readPricing` sans document → `DEFAULT_PRICING` ;
    - après `adminUpdatePricing` → nouvelles valeurs ;
    - un non-admin → `permission-denied`.

    Adapter les tests existants qui attendaient le refus de 44 min par la
    validation pure : ce refus vient désormais de `planFlight` (Task 3).
- [ ] **Step 2 : implémentation.** Exporter `adminUpdatePricing` dans
  `index.ts`.
- [ ] **Step 3 :** unitaires et intégration PASS. Commit
  `feat(functions): admin-editable pricing settings with spec defaults`.

---

### Task 3 : crédit contrôlé dès la demande, tarifs figés, durée minimale des tarifs

**Files :**
- Modify: `functions/src/flights/core.ts`, `functions/src/flights/edit.ts`, `functions/src/flights/actions.ts`, `functions/src/flights/testkit.ts`
- Create: `functions/src/flights/credit.int.test.ts`

**Interfaces :**
- `CrewInfo` gagne `balance: number`.
- `PlanArgs` gagne `existingSnapshot?: Pricing | null` et
  `previousStatus?: string`.
- `planFlight`, après la décision et le mode :
  1. `pricing = await readPricing(tx, db)` ;
  2. vérifier `checkMinDuration(start, end, pricing.minPlannedMinutes)`, en
     transformant l'erreur en `invalid-argument` ;
  3. si le mode est `standard` ou `fuel_only` (toujours à ce stade, puisque
     `custom` ne se décide qu'à la clôture) :
     - lire le verrou `flightLocks/user_<compte débité>` s'il n'est pas déjà
       dans les verrous ;
     - lire les vols `where("payerUid", "==", payer)` ;
     - garder ceux qui sont `valide`, non clôturés, non supprimés, d'un autre
       `id` et en mode `standard` ou `fuel_only` ;
     - calculer leurs coûts estimés, avec leur `pricingSnapshot` ou à défaut
       les tarifs courants, et l'appartenance du compte débité ;
     - calculer le coût estimé du vol en cours ;
     - si `availableCredit < coût`, lever
       `HttpsError("failed-precondition", "Crédit insuffisant pour <shortName> : il manque <n> FCFA.", { credit: { missing, available, cost } })`.
       `<n>` utilise le format de la décision 6, et le verrou est ajouté à
       `locks` ;
  4. `fields.pricingSnapshot` :
     - si le statut est `valide` et que `existingSnapshot` existe avec
       `previousStatus === "valide"` → conserver `existingSnapshot` ;
     - sinon, si le statut est `valide` → `pricing` ;
     - sinon (`demande`) → `null`.
- `edit.ts` et `actions.ts` passent `existingSnapshot` et `previousStatus`
  lus sur le vol existant (création : `null` / `undefined`).
- `testkit.seedUser` accepte `balance` (défaut `0`), et
  `seedFlight` accepte `payerUid` (défaut `crew[0]`).
- **Adapter tous les tests d'intégration existants** : les comptes créés par
  `seedUser` pour y créer des vols reçoivent un solde suffisant.
  Recommandation : changer le défaut de `seedUser` à `balance: 1_000_000`,
  et ne passer `balance: 0` que dans les tests de crédit.

- [ ] **Step 1 : tests d'intégration qui échouent** (`credit.int.test.ts`) :
  - élève avec un solde de 0 qui crée une demande (élève + instructeur) →
    `failed-precondition`, `details.credit.missing === 70000` pour un EXT de
    60 min, et message « Crédit insuffisant pour … : il manque 70 000 FCFA. » ;
  - élève avec un solde de 70 000 → demande acceptée ;
  - un second vol validé du même compte débité (70 000 déjà réservés) sur un
    autre créneau → refusé ;
  - un vol `fuel_only` (GAP avec passager, 60 min) → coût 12 000 ;
  - **admin** qui crée pour un compte débité sans crédit → refusé ;
  - validation par l'instructeur quand le crédit est devenu insuffisant
    entre-temps (vol réservé ailleurs) → refusée ;
  - tarifs figés : un vol validé a
    `pricingSnapshot.flatFee.EXT === 70000`. Modifier les tarifs, puis
    modifier la destination du vol : le snapshot ne change pas ;
  - `minPlannedMinutes` lu dans les tarifs : régler 30, puis créer un vol de
    35 min → accepté ;
  - concurrence : deux demandes simultanées du même compte débité, dont le
    crédit n'en couvre qu'une, sur des créneaux distincts → une seule passe.
- [ ] **Step 2 : implémentation.** Run : unitaires et intégration PASS (tous
  les tests existants compris).
- [ ] **Step 3 : commit**
  `feat(functions): credit check from the request on, frozen pricing snapshot`.

---

### Task 4 : clôture (`closeFlight`) et débit

**Files :**
- Create: `functions/src/finance/ledger.ts`, `functions/src/flights/close.ts`, `functions/src/flights/close.int.test.ts`
- Modify: `functions/src/flights/validation.ts` (+ tests), `functions/src/index.ts`

**Interfaces :**
- `ledger.ts` :
  - `postMovement(tx, db, a: { uid: string; amount: number; type: "credit" | "correction" | "flight" | "flight_adjustment"; reason: string | null; flightId: string | null; by: string; currentBalance: number }): number`.
    Il écrit `users/{uid}.balance = currentBalance + amount` (avec
    `updatedAt`) et crée `transactions/{auto}` avec `balanceAfter`, puis
    renvoie le nouveau solde.
  - L'appelant a **lu** `users/{uid}` dans la même transaction, avant toute
    écriture.
- `validateClosing(data)` →
  `{ flightId, actualMinutes, shortFlightAmount: number | null, customAmount: number | null }`.
  Les minutes sont un entier de 1 à 720. Les montants sont des entiers de
  0 à 200 000 ; au-delà, message « Montant trop élevé (200 000 FCFA au
  maximum). ».
- Callable `closeFlight` :
  - appelant : membre de `crew` ou admin, sinon `permission-denied` ;
  - le vol doit être `valide`, non supprimé, **non clôturé** (sinon
    « Ce vol est déjà clôturé. »), avec un départ passé (sinon « Le vol n'a
    pas encore eu lieu. ») ;
  - dans une transaction :
    1. lire le vol, le compte débité, le verrou du compte, puis les tarifs
       (`pricingSnapshot` ou `readPricing`) ;
    2. appeler `closingBill` ; une erreur devient `invalid-argument` ;
    3. si `billedTo === "account"` : `postMovement` avec le type `flight`,
       `amount = −billedAmount` et la raison « Vol du <jj/mm/aaaa> » ;
    4. mettre à jour le vol :
       - `isClosed: true`, `actualFlightMinutes`, `closedBy`, `closedAt`,
         `billedAmount`, `billedTo` ;
       - `customAmount` et `shortFlightAmount` ;
       - `pricingMode` (`custom` le cas échéant) ;
       - `updatedAt`.
- `loadFlight` (`core.ts`) n'est pas utilisé tel quel, car il refuse un vol
  clôturé avec un autre message. `close.ts` fait sa propre lecture.

- [ ] **Step 1 : tests d'intégration qui échouent** (`close.int.test.ts`) :
  - clôture de 90 min d'un vol GAP par un membre de l'équipage :
    - solde −15 000 ;
    - une transaction `flight` de −15 000 avec `balanceAfter` et `flightId`
      corrects ;
    - vol clôturé, avec `billedAmount` 15 000 et `billedTo` à `account` ;
  - un non-membre non admin → `permission-denied` ; l'admin hors équipage →
    accepté ;
  - avant le départ → `failed-precondition` ;
  - deux clôtures simultanées → une seule réussit, un seul débit ;
  - moins de 45 min, standard, sans montant → `invalid-argument` ; avec
    8 000 → débit de 8 000 ;
  - montant différent avec passager → `off_app`, aucun mouvement de solde ;
    sans passager → `invalid-argument` ;
  - montant de 250 000 → `invalid-argument` ;
  - tarifs figés : valider (snapshot EXT 70 000), passer le tarif EXT à
    80 000, clôturer 60 min → 70 000 ;
  - vol validé sans snapshot (ancien vol créé par `seedFlight`) → tarifs
    courants ;
  - le solde peut devenir négatif.
- [ ] **Step 2 : implémentation.** Run : PASS.
- [ ] **Step 3 : commit** `feat(functions): closeFlight with debit and history`.

---

### Task 5 : crédits et corrections de compte

**Files :**
- Create: `functions/src/finance/accounts.ts`, `functions/src/finance/accounts.int.test.ts`
- Modify: `functions/src/finance/validation.ts` (+ tests), `functions/src/auth/guards.ts`, `functions/src/index.ts`

**Interfaces :**
- `guards.ts` : `requireStaff(db, caller): Promise<CallerProfile>`
  (instructeur ou admin actif, sinon « Réservé aux instructeurs et aux
  admins. »).
- `validateCredit(data)` → `{ userUid, amount, reason: string | null }`,
  avec `amount` entier `> 0`, sans plafond.
- `validateCorrection(data)` → `{ userUid, amount, reason: string }`, avec
  `amount ≠ 0` (entier, sans plafond), et une raison obligatoire de 1 à 200
  caractères (sinon « Motif obligatoire pour une correction. »).
- Callables `creditAccount` et `correctAccount` :
  - accès via `requireStaff` ;
  - dans une transaction : lire le compte ciblé (`not-found` s'il est
    absent) et son verrou, puis `postMovement` (types `credit` /
    `correction`, `by` = l'appelant) et écrire le verrou ;
  - renvoient `{ balance }`.

- [ ] **Step 1 : tests qui échouent.**
  - Unitaires : validations (zéro, décimal, négatif pour un crédit, motif
    obligatoire pour une correction) ; un crédit de 1 000 000 est accepté.
  - Intégration :
    - crédit de 50 000 → solde +50 000, transaction `credit` ;
    - correction de −10 000 avec motif → transaction `correction` ;
    - un lâché → `permission-denied` ;
    - un crédit et une clôture simultanés sur le même compte → le solde
      final et les deux `balanceAfter` sont cohérents.
- [ ] **Step 2 : implémentation.** Run : PASS.
- [ ] **Step 3 : commit** `feat(functions): staff credit and correction of accounts`.

---

### Task 6 : correction et suppression admin, avec régularisation

**Files :**
- Create: `functions/src/flights/admin-edit.ts`, `functions/src/flights/admin-edit.int.test.ts`
- Modify: `functions/src/flights/validation.ts` (+ tests), `functions/src/flights/core.ts` (options de `planFlight`), `functions/src/index.ts`

**Interfaces :**
- `validateAdminUpdate(data)` → `{ flightId, input: FlightInput, pricingMode?: "standard" | "fuel_only" | "custom", actualMinutes?: number, shortFlightAmount?: number | null, customAmount?: number | null }`.
  Mêmes règles de champs que `validateFlightInput` et `validateClosing`.
- `planFlight` gagne les options :
  - `skipActiveChecks?: boolean` : ne vérifie ni les comptes ni les appareils
    actifs ;
  - `skipCredit?: boolean` : pour un vol clôturé, la régularisation suffit ;
  - `forcedMode?: "standard" | "fuel_only"` : l'admin choisit librement ;
    `resolvePricingMode` n'est pas appliqué.
- Callable `adminUpdateFlight` (admin seulement) :
  - **Vol non clôturé** : `planFlight` avec
    `decide = () => ({ ok: true, status: current status (demande → demande, valide → valide), instructorUid: designatedInstructor(createdBy, crew) })`,
    `skipActiveChecks`, crédit contrôlé, conflits si `valide`.
    `actualMinutes` et les montants sont refusés (« Réservé aux vols
    clôturés. »).
  - **Vol clôturé** :
    - recalculer la facture avec `closingBill` à partir des nouvelles
      valeurs (tarifs figés du vol, sinon courants ; appartenance du nouveau
      compte débité) ;
    - lire les comptes concernés (l'ancien et le nouveau compte débité) et
      leurs verrous ;
    - appliquer `adjustments(before, after)` par `postMovement` (type
      `flight_adjustment`, raison « Régularisation du vol du <date> ») ;
    - mettre à jour les champs du vol, dont `billedAmount`, `billedTo`,
      `payerUid` et `pricingMode` ;
    - conflits contrôlés, matrice ignorée.
  - Toujours : `updatedAt`, suppression logique uniquement.
- Callable `adminDeleteFlight({ flightId })` (admin, à tout moment) :
  - `deleted: true` ;
  - si le vol est clôturé et que `billedTo === "account"` : remboursement
    `flight_adjustment` de `+billedAmount`, raison « Annulation du vol du
    <date> ».

- [ ] **Step 1 : tests d'intégration qui échouent.**
  - Vol clôturé GAP 90 min (15 000) corrigé à 120 min → transaction de
    −6 000, `billedAmount` 21 000.
  - Changement de compte débité → +15 000 à l'ancien, −débit au nouveau.
  - Passage en montant différent (avec passager) → remboursement complet,
    `off_app`.
  - Invariant : pour chaque vol, la somme des transactions `flight` et
    `flight_adjustment` de ce `flightId` vaut `−billedAmount` si le vol est
    sur un compte, et `0` s'il est hors app ou supprimé.
  - Un non-admin → `permission-denied`.
  - Correction d'un vol non clôturé vers un créneau en conflit → refusée.
  - Suppression d'un vol clôturé → remboursement et `deleted: true`.
  - Suppression d'un vol déjà commencé mais non clôturé → autorisée, sans
    mouvement.
- [ ] **Step 2 : implémentation.** Run : PASS.
- [ ] **Step 3 : commit**
  `feat(functions): admin flight correction and deletion with automatic regularisation`.

---

### Task 7 : crédit initial en dev

**Files :**
- Create: `functions/src/admin/seed-credit.ts`, `functions/scripts/seed-dev-credit.js`
- Modify: `functions/src/admin/admin.int.test.ts`, `README.md`

**Interfaces :**
- `seedInitialCredit(db, amount: number): Promise<{ credited: string[]; skipped: string[] }>` :
  - pour chaque document `users` : s'il existe déjà une transaction de ce
    compte avec `reason === "Crédit initial (tests)"`, le compte est ignoré ;
  - sinon, dans une transaction, `postMovement` (type `credit`, `by`
    `system`).
- Le script `seed-dev-credit.js --project ulmgap-dev [--amount 500000]`
  appelle `assertSeedAllowed` (Task 5 du plan 2b) avant `initializeApp`.

- [ ] **Step 1 : test d'intégration qui échoue** : deux comptes → crédités
  une fois chacun, avec `balanceAfter` correct ; une relance → tous ignorés.
- [ ] **Step 2 : implémentation**, plus une section du README.
- [ ] **Step 3 :** PASS. Commit `feat: dev-only initial credit script`.

---

### Task 8 : app, miroir des coûts, format des montants, modèles et API

**Files :**
- Create: `lib/core/pricing.dart`, `lib/core/money.dart`, `lib/data/pricing_settings.dart`, `lib/data/account_movement.dart`, `lib/data/finance_api.dart`, `test/core/pricing_test.dart`, `test/core/money_test.dart`, `test/data/finance_api_test.dart`
- Modify: `lib/data/flight.dart` (champs financiers), `lib/data/services.dart`, `lib/main.dart`, `test/support/fakes.dart`, `pubspec.yaml` (paquet `web`)

**Interfaces :**
- `lib/core/pricing.dart` : miroir exact de `rules/pricing.ts`, avec
  `Pricing` (`fromMap` avec défauts, `toMap`), `defaultPricing`,
  `maxManualAmount = 200000`, `computedCost`, `estimatedCost`,
  `availableCredit` et `closingBill` (renvoie un record, ou lève
  `ArgumentError` avec le même message). Il rejoue
  `test/fixtures/pricing_cases.json` (la partie `adjustments` n'est pas
  nécessaire côté app).
- `lib/core/money.dart` : `formatFcfa(int)` → `'12 000 FCFA'` et
  `'−3 000 FCFA'` ; `parseAmount(String) → int?`, qui accepte les
  espaces et refuse les décimales.
- `Flight` gagne : `payerUidField`, `pricingSnapshot` (`Pricing?`),
  `actualFlightMinutes`, `billedAmount`, `billedTo`, `customAmount`,
  `shortFlightAmount`, `closedBy` et `closedAt`.
- `AccountMovement` : `id`, `userUid`, `amount`, `type`, `reason`,
  `flightId`, `by`, `at` et `balanceAfter`.
- `FinanceApi` (interface, implémentation Firebase, doublure `FakeFinanceApi`) :
  - `Stream<Pricing> watchPricing()` (document absent → défauts) ;
  - `Future<void> updatePricing(Pricing)` ;
  - `Stream<List<AccountMovement>> watchMovements(String uid)` (requête
    `userUid ==`, tri décroissant côté client) ;
  - `Stream<List<AppUser>> watchAccounts()` (collection `users`, triée par
    nom) ;
  - `Future<int> credit(String uid, int amount, String? reason)` et
    `Future<int> correct(String uid, int amount, String reason)` ;
  - `Future<void> closeFlight(String flightId, {required int actualMinutes, int? shortFlightAmount, int? customAmount})` ;
  - `Future<void> adminUpdateFlight(String flightId, Map<String, dynamic> payload)`
    et `Future<void> adminDeleteFlight(String flightId)` ;
  - `Stream<List<Flight>> watchFlightsBetween(DateTime from, DateTime to)`
    (plage sur `start`).
  - Les erreurs sont converties en `FlightFailure` via `flightFailureFrom`
    existant (message du serveur).
- `AppServices` gagne `FinanceApi? finance`, branché dans `main.dart`.

- [ ] **Step 1 : tests qui échouent**
  - `pricing_test` (fixture) ;
  - `money_test` : 0, 500, 12 000, 1 234 567, −3 000, et l'analyse de
    `"12 000"`, `"12000"`, `"abc"` → `null`, `"12,5"` → `null` ;
  - `finance_api_test` : décodage d'un `AccountMovement` et d'un `Flight`
    avec ses champs financiers.
- [ ] **Step 2 : implémentation.** Run :
  `fvm flutter test && fvm flutter analyze` PASS.
- [ ] **Step 3 : commit**
  `feat: app pricing mirror, FCFA format, finance models and API`.

---

### Task 9 : fenêtre du vol : coût estimé, crédit disponible, clôture

**Files :**
- Modify: `lib/features/flight/flight_screen.dart`, `lib/features/flight/flight_actions.dart`, `lib/features/flight/flight_texts.dart`, `test/features/flight/flight_screen_test.dart`, `test/features/flight/flight_actions_test.dart`

Comportement :
1. **Aperçu** (quand il est affiché) :
   - « Coût estimé : <montant> » (mode `standard` ou `fuel_only`, durée
     prévue, appartenance du compte débité, tarifs de `watchPricing`) ;
   - « Crédit disponible de <code> : <montant> », **seulement si
     l'utilisateur peut lire ce solde** : le compte débité est le sien
     (`me.balance`), ou il est instructeur ou admin (`watchAccounts`) ;
   - le crédit disponible est calculé comme le serveur, sur les vols chargés
     (`valide`, non clôturés, du même compte débité, autres que ce vol) ;
   - s'il est inférieur au coût, la ligne est en rouge, suivie de « Crédit
     insuffisant : il manque <montant>. », et l'enregistrement est bloqué
     localement.
2. **`flightActions`** gagne `FlightAction.close` : vol `valide`, non
   clôturé, non supprimé, départ passé, et utilisateur membre de l'équipage
   ou admin.
3. **Clôture** (bouton « Clôturer » en bas), section ou dialogue sur le même
   écran :
   - « Durée réelle (minutes) », prérempli avec la durée prévue ;
   - si le mode est `standard` et la durée réelle inférieure au minimum des
     tarifs → champ obligatoire « Montant à facturer » ;
   - si le vol a un passager sans compte → case « Montant différent
     (facturé hors app) » et son champ montant ;
   - aperçu du montant calculé par `closingBill` ;
   - montants limités à 200 000 localement (message « Montant trop élevé
     (200 000 FCFA au maximum). ») ;
   - validation → `closeFlight`, puis retour au planning.
4. **Vol clôturé**, en tête de fenêtre : « Clôturé : <durée h mm>,
   <montant> débité sur le compte de <code> » ou « … facturé hors app ». Il
   n'y a plus d'action, sauf les actions admin de la Task 10.

- [ ] **Step 1 : tests qui échouent.**
  - Aperçu :
    - coût estimé EXT 60 min = « 70 000 FCFA » ;
    - crédit insuffisant → message, et aucun appel d'API à l'enregistrement ;
    - crédit masqué pour un élève qui voit le vol d'un autre compte.
  - `flightActions` : `close` pour un membre après le départ, pas pour un
    tiers ni avant le départ.
  - Clôture :
    - 90 min GAP → aperçu « 15 000 FCFA », puis appel
      `closeFlight(actualMinutes: 90)` et retour au planning ;
    - 30 min standard → le montant est exigé ;
    - montant différent → `customAmount` envoyé ;
    - 250 000 → refusé localement.
  - Vol clôturé → la ligne « Clôturé » est affichée, sans bouton pour un
    non-admin.
- [ ] **Step 2 : implémentation.** Run : PASS.
- [ ] **Step 3 : commit**
  `feat: flight screen shows estimated cost and available credit, and closes flights`.

---

### Task 10 : fenêtre du vol, correction et suppression admin

**Files :**
- Modify: `lib/features/flight/flight_screen.dart`, `lib/features/flight/flight_actions.dart`, tests associés

Comportement :
- **`flightActions`** gagne `FlightAction.adminEdit` et
  `FlightAction.adminDelete`, pour un admin sur tout vol non supprimé, à tout
  moment, clôturé compris.
- **Admin sur un vol où il n'a pas d'autre droit de modification** (vol
  passé, clôturé, ou vol d'un autre) :
  - bouton « Corriger » : il rend tous les champs modifiables et affiche un
    bouton « Enregistrer la correction » ;
  - sur un vol clôturé, les champs de clôture (durée réelle, montants) sont
    aussi modifiables ;
  - l'enregistrement appelle `adminUpdateFlight`, puis revient au planning ;
  - l'aperçu indique « Régularisation : <±montant> sur le compte de <code> »
    pour un vol clôturé (calcul local de `closingBill` et de la différence).
- **Bouton « Supprimer le vol »** (admin), avec la confirmation « Supprimer
  définitivement ce vol ? Le montant débité sera remboursé. » (la seconde
  phrase seulement si le vol est clôturé et débité sur un compte). Appelle
  `adminDeleteFlight`, puis revient au planning.

- [ ] **Step 1 : tests qui échouent.**
  - Admin sur un vol clôturé : correction de la durée → appel
    `adminUpdateFlight` avec `actualMinutes`, et aperçu de régularisation.
  - Suppression confirmée → appel, puis retour au planning.
  - Non-admin : aucun de ces boutons.
- [ ] **Step 2 : implémentation.** Run : PASS.
- [ ] **Step 3 : commit**
  `feat: admin flight correction and deletion from the flight screen`.

---

### Task 11 : « Mon compte » et « Instructeurs »

**Files :**
- Create: `lib/features/account/account_screen.dart`, `lib/features/account/movements_list.dart`, `lib/features/instructors/instructors_screen.dart`, `lib/features/instructors/credit_dialog.dart`, tests associés
- Modify: `lib/features/home/home_shell.dart`

Comportement :
- **`AccountScreen(me)`** :
  - en tête : nom, badge de profil, appartenance, et **solde** (en rouge
    s'il est négatif) ;
  - puis la liste `MovementsList(uid)` : date et heure, libellé du type
    (Crédit, Correction, Vol, Régularisation), raison, montant signé en
    vert ou rouge, et « Solde : <balanceAfter> » ;
  - états chargement, erreur et vide via `asyncState` (« Aucun mouvement. »).
- **`InstructorsScreen`** (instructeurs et admins) :
  - la liste des comptes (`watchAccounts`) avec leur solde et le badge ;
  - un appui sur un compte ouvre son historique (`MovementsList`) et un
    bouton « Créditer / corriger » ;
  - **`CreditDialog`** : choix entre « Créditer » et « Corriger » ; montant
    (positif pour un crédit, signé pour une correction) ; motif (obligatoire
    pour une correction) ; aucun plafond ; appel de
    l'API et SnackBar « Nouveau solde : <montant> ».
- **HomeShell** :
  - une icône « Mon compte » (tous) et une icône « Instructeurs »
    (instructeurs et admins) ;
  - le menu Administration gagne « Tarifs » et « Relevé » (Task 12).

- [ ] **Step 1 : tests de widgets qui échouent** : solde et mouvements
  affichés et formatés ; crédit (appel avec le bon montant et SnackBar) ;
  correction sans motif → bloquée ; 1 000 000 → accepté ; l'icône
  « Instructeurs » est absente pour un élève.
- [ ] **Step 2 : implémentation.** Run : PASS.
- [ ] **Step 3 : commit** `feat: my account and instructors screens`.

---

### Task 12 : administration, tarifs et relevé des vols facturés

**Files :**
- Create: `lib/features/admin/pricing_admin_screen.dart`, `lib/features/admin/billing_report_screen.dart`, `lib/core/csv.dart`, `lib/core/download.dart` (et ses variantes web et stub), tests associés
- Modify: `lib/features/home/home_shell.dart`

Comportement :
- **`PricingAdminScreen`** :
  - un champ par tarif (forfait et taux de dépassement par appartenance,
    minutes incluses, durée minimale, carburant/h), prérempli depuis
    `watchPricing` ;
  - le bouton « Enregistrer » appelle `updatePricing` ; une SnackBar
    confirme ou affiche l'erreur.
- **`BillingReportScreen`** :
  - une période (deux sélecteurs de date, par défaut le mois courant) ;
  - `watchFlightsBetween`, en gardant les vols clôturés non supprimés ;
  - un tableau : date, appareil, équipage, mode, montant, « Compte de
    <code> » ou « Hors app » ;
  - les totaux « Débité sur comptes » et « Facturé hors app » ;
  - le bouton « Exporter en CSV » **sur le web seulement** (`kIsWeb`),
    qui télécharge `releve_<du>_<au>.csv` :
    - séparateur `;`, encodage UTF-8 avec BOM (pour Excel) ;
    - colonnes : date, départ, fin, appareil, équipage, passagers, mode,
      durée réelle (min), montant, imputation, compte débité ;
    - la génération est une fonction pure dans `csv.dart`, et le
      téléchargement se fait via une import conditionnelle (`web` sur le
      web, et une fonction vide ailleurs).

- [ ] **Step 1 : tests qui échouent** :
  - tarifs : préremplissage et envoi des nouvelles valeurs ;
  - relevé : lignes et totaux sur des vols factices ;
  - `csv.dart` : contenu exact (BOM, en-tête, `;`, un champ contenant `;`
    ou des guillemets bien échappé).
- [ ] **Step 2 : implémentation.** Run : PASS.
- [ ] **Step 3 : commit** `feat: pricing admin and billed flights report with CSV export`.

---

### Task 13 : déploiement dev, crédit initial, documentation

- [ ] Suites complètes PASS.
- [ ] `firebase deploy --project dev --only firestore:rules,functions`
  (**jamais prod**).
- [ ] Crédit initial en dev (décision 4) :
  `cd functions && npm run build && node scripts/seed-dev-credit.js --project ulmgap-dev --amount 500000`.
- [ ] Mettre à jour la spec si une décision la précise, puis CLAUDE.md :
  - plan 3 terminé ;
  - état ;
  - commandes ;
  - rubrique « À reprendre » pour les plans 4 et 5.
- [ ] Commit, puis push de `feature/finances`.
