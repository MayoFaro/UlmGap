# UlmGap, plan 9 : dépassement à partir de 60 min, trois forfaits de baptême, battement de 30 min

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** (1) au-delà de 75 min, facturer tout le temps après 60 min ;
(2) remplacer le baptême unique par trois forfaits (Local, Nyonye, Awagne)
choisis avant le vol ; (3) imposer 30 min d'écart entre deux vols (même
appareil ou même personne).

**Architecture :** comme au plan 8 : règles pures dans `functions/src/rules/`
avec miroir Dart dans `lib/core/` et cas partagés `test/fixtures/*.json`,
écritures par les callables existants. Chaque tâche modifie **les deux côtés**
quand une règle partagée change, pour que les deux suites restent vertes.

**Tech Stack :** inchangée.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §2.4,
§3.5, §4.3, §10.2, §10.3 (révision du 2026-10-05, commit `b6133a4`).

**Branche :** `feature/instruction-bapteme` (suite du plan 8, non fusionnée).

## Global Constraints

- Toujours `fvm flutter` / `fvm dart`. TDD. Textes en français. Jamais de
  déploiement en prod.
- **Dépassement** (mode `standard`, `d` ≥ `minPlannedMinutes`) :
  `d` ≤ `toleranceMinutes` → `flatFee[A]` ; sinon
  `flatFee[A] + overtimeHourly[A] × (d − includedMinutes) / 60`, arrondi au
  franc. Défauts : `includedMinutes` = **60**, `toleranceMinutes` = **75**.
  Toutes les appartenances. Un snapshot sans `toleranceMinutes` prend 75 (il
  garde alors l'ancien calcul puisque son `includedMinutes` vaut 75) : **toute
  lecture d'un `pricingSnapshot` stocké passe par `pricingWithDefaults`**
  (serveur) / `Pricing.fromMap` (app).
- `validatePricing` : `toleranceMinutes` entier de 1 à 600, **≥ `includedMinutes`**,
  sinon « La tolérance doit être au moins égale au temps couvert. ».
- **Baptême** : `baptismTier` ∈ `local` / `nyonye` / `awagne` ; `baptismFees`
  = `{local: 70000, nyonye: 90000, awagne: 110000}` (remplace `baptismFee`).
  Un baptême sans forfait valide est refusé : « Choisissez le forfait du
  baptême (Local, Nyonye ou Awagne). ». À la clôture, un vol `baptism` sans
  `baptismTier` (données de dev du plan 8) est facturé au forfait `local`.
  Libellés : « Local », « Nyonye », « Awagne » ; « Baptême Nyonye ».
- **Battement** : constante `FLIGHT_BUFFER_MINUTES = 30` (fixe). Conflit si
  `c.start < o.end + 30 min && o.start < c.end + 30 min` (bornes ouvertes :
  écart d'exactement 30 min accepté). Même appareil ou même personne, vols
  `valide` non supprimés non clôturés, planification seulement (inchangé).
  Message serveur : « Conflit avec un autre vol validé (30 min d'écart
  minimum). » ; message app (`describeConflict`) suffixé de « (30 min
  d'écart minimum) ».
- Tests : `fvm flutter test && fvm flutter analyze` ; `cd functions && npm
  test` ; intégration : `cd functions && JAVA_HOME=/opt/android-studio/jbr
  PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int` (juger sur
  `# fail` / `not ok`).

## Review Focus

1. **Saut 75 → 76 min** : EXT 75 = 70 000, 76 = 78 000 (Task 1, cas partagés).
2. **Ancien snapshot** (`includedMinutes` 75, sans tolérance) : 60 min =
   forfait, jamais de montant négatif ni de dépassement fantôme — en
   particulier dans le calcul du crédit disponible (`checkCredit`, autres
   vols) (Task 1).
3. **Écart exactement 30 min** accepté, 29 refusé, côté serveur et app
   (Task 4).
4. **Requête serveur des conflits** : un vol finissant 20 min avant le début
   du candidat doit être lu (filtre `end > start − 30 min`) (Task 4).
5. **Baptême sans forfait** refusé ; changement de forfait par l'admin après
   clôture met à jour `billedAmount` (Task 2).

---

### Task 1 : dépassement à partir de 60 min (serveur + app)

**Files:**
- Modify: `functions/src/rules/pricing.ts`, `functions/src/rules/pricing.test.ts`
- Modify: `functions/src/finance/validation.ts` (+ `validation.test.ts`), `functions/src/finance/pricing-store.ts`
- Modify: `functions/src/flights/core.ts` (`checkCredit`, `planFlight` : snapshots via `pricingWithDefaults`)
- Modify: `lib/core/pricing.dart`, `lib/features/admin/pricing_admin_screen.dart`
- Modify: `test/fixtures/pricing_cases.json`
- Modify (montants attendus) : `functions/src/flights/close.int.test.ts`,
  `functions/src/flights/admin-edit.int.test.ts`, `functions/src/finance/accounts.int.test.ts`,
  et tout test Dart qui fige un coût de vol de plus de 75 min
- Test: `test/core/pricing_test.dart`, `test/features/admin/pricing_admin_screen_test.dart`

**Interfaces:**
- Produces: `Pricing.toleranceMinutes` (TS et Dart, défaut 75) ;
  `includedMinutes` défaut 60 ; `computedCost` selon la règle des Global
  Constraints ; champ Tarifs clé `toleranceMinutes`, libellés « Temps couvert
  par le forfait (min) » (clé existante `includedMinutes`) et « Tolérance
  jusqu'à (min) ».

- [ ] **Step 1 : tests qui échouent.** `pricing_cases.json` → `cost` :
  remplacer les attentes par la nouvelle règle et ajouter les cas :

| name | mode | minutes | category | expected |
|---|---|---|---|---|
| GAP 90 (spec §4.3) | standard | 90 | GAP | 18000 |
| EXT 90 (spec §4.3) | standard | 90 | EXT | 85000 |
| EXT 75 (tolérance) | standard | 75 | EXT | 70000 |
| 76 min EXT (saut) | standard | 76 | EXT | 78000 |
| GR 100 min | standard | 100 | GR | 50000 |
| MIL 77 min | standard | 77 | MIL | 58500 |

  (les autres cas existants — GAP 60, MIL 75, EXT 60, 75 pile GAP, 44, 45,
  fuel_only — gardent leurs valeurs) ; `closing` « standard 90 min GAP » →
  18 000. Tests en ligne (TS et Dart) : ancien snapshot
  `{...DEFAULT_PRICING, includedMinutes: 75}` sans `toleranceMinutes` passé
  par `pricingWithDefaults` / `Pricing.fromMap` : 60 min → forfait, 90 min
  GAP → 15 000 (ancien calcul). `validatePricing` : tolérance < temps couvert
  refusée avec le message exact. Tarifs : champ `toleranceMinutes`
  pré-rempli (75) et enregistré.
- [ ] **Step 2 : vérifier l'échec** (les deux suites).
- [ ] **Step 3 : implémenter** (TS et Dart) ; `readPricing` et
  `pricingWithDefaults` fusionnent `toleranceMinutes` ; dans `core.ts`,
  `existingSnapshot` et le snapshot des autres vols de `checkCredit`
  passent par `pricingWithDefaults` ; mettre à jour les montants attendus des
  tests d'intégration et Dart qui en dépendent (recalculés avec la nouvelle
  règle, commentaire avec le calcul).
- [ ] **Step 4 : vérifier** — les trois suites.
- [ ] **Step 5 : commit** `feat: overtime counted from 60 min beyond a 75 min tolerance (plan 9)`

---

### Task 2 : trois forfaits de baptême (serveur, règles et modèles app)

**Files:**
- Modify: `functions/src/rules/pricing.ts` (+ test), `functions/src/finance/validation.ts` (+ test), `functions/src/finance/pricing-store.ts`
- Modify: `functions/src/flights/validation.ts` (+ test), `functions/src/flights/core.ts`, `functions/src/flights/actions.ts`, `functions/src/flights/close.ts`, `functions/src/flights/admin-edit.ts`
- Test: `functions/src/flights/edit.int.test.ts`, `actions.int.test.ts`, `close.int.test.ts`, `admin-edit.int.test.ts`
- Modify: `lib/core/pricing.dart`, `lib/data/flight.dart` (`Flight.baptismTier`, `FlightDraft.baptismTier`), `lib/features/flight/flight_texts.dart`
- Modify: `test/fixtures/pricing_cases.json`, `test/support/fakes.dart` (`testFlight(baptismTier:)`)
- Test: `test/core/pricing_test.dart`, `test/data/flight_test.dart`, `test/features/flight/flight_texts_test.dart`

**Interfaces:**
- Produces:
  - TS : `type BaptismTier = "local" | "nyonye" | "awagne"` ;
    `Pricing.baptismFees: Record<BaptismTier, number>` (remplace `baptismFee`) ;
    `closingBill({..., baptismTier?: BaptismTier | null})` → en `baptism`,
    `baptismFees[baptismTier ?? "local"]` ; `FlightInput.baptismTier: BaptismTier | null`
    (obligatoire si `baptism`, sinon `null`) ; `ReviewChanges.baptismTier?` ;
    champ `flights.baptismTier` (null hors baptême) écrit par `planFlight`.
  - Dart : `Pricing.baptismFees` (`Map<String, int>`, clés `local`,
    `nyonye`, `awagne`), `closingBill(..., baptismTier:)`, `Flight.baptismTier`
    (String?), `FlightDraft.baptismTier` (String?, envoyé toujours, `null`
    hors baptême), `const baptismTiers = ['local', 'nyonye', 'awagne']`,
    `String baptismTierLabel(String? tier)` (« Local » / « Nyonye » /
    « Awagne »), `String flightPricingLabel(String mode, String? baptismTier)`
    (« Baptême Nyonye » en baptême, sinon `pricingModeLabel(mode)`).

- [ ] **Step 1 : tests qui échouent.**
  - Unitaires TS : `closingBill` baptism Nyonye 20 min → 90 000 off_app ;
    sans tier → 70 000 ; `validateFlightInput` : `baptism: true` sans
    `baptismTier` ou avec `"autre"` refusé (message exact), `baptismTier`
    ignoré (`null`) si `baptism` faux ; `validatePricing` exige les trois
    forfaits (0 à 1 000 000).
  - Intégration : création d'un baptême Awagne → `pricingMode: "baptism"`,
    `baptismTier: "awagne"` ; clôture → `billedAmount` 110 000 off_app ;
    validation avec `changes.baptismTier: "nyonye"` → stocké ; correction
    admin d'un baptême clôturé Local → Awagne → `billedAmount` 110 000,
    aucun mouvement de solde ; correction admin qui retire le baptême →
    `baptismTier: null`.
  - Fixture `closing` : le cas baptême existant devient Nyonye (90 000) et un
    cas sans `baptismTier` → 70 000 ; les loaders TS et Dart passent
    `baptismTier`.
  - Dart : `Pricing.fromMap({})` → les trois forfaits par défaut ; `toMap()`
    les contient (et plus `baptismFee`) ; `Flight`/`FlightDraft` ;
    libellés.
- [ ] **Step 2 : vérifier l'échec.**
- [ ] **Step 3 : implémenter.** `validateFlight` (`actions.ts`) reprend
  `changes.baptismTier ?? f.get("baptismTier")` quand le baptême reste actif.
  `close.ts` et `admin-edit.ts` passent `baptismTier` (champ du vol / de
  l'input) à `closingBill`. Les écrans existants qui lisaient
  `pricing.baptismFee` (aperçu du formulaire, dialogue de clôture, Tarifs)
  doivent compiler : y lire provisoirement `baptismFees['local']` (la Task 3
  les remplace).
- [ ] **Step 4 : vérifier** — les trois suites.
- [ ] **Step 5 : commit** `feat: three baptism tiers (local, nyonye, awagne), rules and models (plan 9)`

---

### Task 3 : forfaits de baptême dans l'app (formulaire, clôture, correction, Tarifs, relevé)

**Files:**
- Modify: `lib/features/flight/flight_screen.dart`, `lib/features/flight/closing_dialog.dart`,
  `lib/features/admin/pricing_admin_screen.dart`, `lib/features/admin/billing_report_screen.dart`
- Test: `test/features/flight/flight_screen_test.dart`, `test/features/flight/closing_dialog_test.dart`,
  `test/features/admin/pricing_admin_screen_test.dart`, `test/features/admin/billing_report_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 (Dart).
- Produces: clés `passenger-baptism-tier` (choix dans la fenêtre passager,
  un `SegmentedButton` ou trois `RadioListTile` sans valeur par défaut),
  `passenger-baptism-tier-line` (choix sur la ligne du passager),
  `baptismFee-local`, `baptismFee-nyonye`, `baptismFee-awagne` (Tarifs, à la
  place de `baptismFee`) ; paramètre `ClosingDialog(baptismTier:)`.

- [ ] **Step 1 : tests qui échouent** (écrits en entier à partir des mises
  en place voisines) :
  1. Fenêtre passager : « Baptême de l'air » coché sans forfait → « Ajouter »
     refusé avec « Choisissez le forfait du baptême (Local, Nyonye ou
     Awagne). » ; Nyonye choisi → ligne « Passager sans compte · Baptême
     Nyonye », aperçu « Baptême Nyonye : 90 000 FCFA, facturé hors app »,
     payload `baptismTier: 'nyonye'`.
  2. Ligne du passager : forfait changé en Awagne → aperçu 110 000 et
     payload `awagne` ; baptême décoché → payload `baptismTier: null`.
  3. Validation : `changes` contient `baptismTier`.
  4. Fiche d'un vol baptême Awagne : « Tarification » = « Baptême Awagne ».
  5. Dialogue de clôture Nyonye : « Montant : 90 000 FCFA facturé hors app ».
  6. Correction admin d'un baptême clôturé : forfait modifiable, payload
     `baptismTier`.
  7. Tarifs : trois champs pré-remplis (70 000 / 90 000 / 110 000) ; des
     valeurs personnalisées sont conservées à l'enregistrement.
  8. Relevé et CSV : mode « Baptême Nyonye ».
- [ ] **Step 2 : vérifier l'échec.**
- [ ] **Step 3 : implémenter** (état `_baptismTier` dans `flight_screen.dart`,
  initialisé depuis `f.baptismTier` ; `_draft()` envoie
  `baptismTier: baptême actif ? _baptismTier : null` ; `_PassengerDialog`
  rend aussi le forfait ; `ClosingDialog` reçoit `baptismTier: f.baptismTier` ;
  relevé et fiche utilisent `flightPricingLabel`).
- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze`.
- [ ] **Step 5 : commit** `feat(app): choose the baptism tier, show it everywhere (plan 9)`

---

### Task 4 : battement de 30 min entre deux vols (serveur + app)

**Files:**
- Modify: `functions/src/rules/flights.ts` (+ test), `functions/src/flights/core.ts` (`assertNoConflict`)
- Modify: `lib/core/flight_rules.dart`, `lib/features/flight/flight_texts.dart` (`describeConflict`)
- Modify: `test/fixtures/flight_rules.json`, `test/core/flight_rules_test.dart`, `functions/src/rules/flights.test.ts`
- Modify (fixtures d'intégration qui enchaînent des vols à moins de 30 min) : tests d'intégration et widgets concernés
- Test: `functions/src/flights/edit.int.test.ts`, `test/features/flight/flight_texts_test.dart`, `test/features/flight/flight_screen_test.dart`

**Interfaces:**
- Produces: `FLIGHT_BUFFER_MINUTES = 30` (TS, `rules/flights.ts`) /
  `const flightBufferMinutes = 30` (Dart) ; `findConflict` applique le
  battement (signature inchangée).

- [ ] **Step 1 : tests qui échouent.**
  - Fixtures `conflicts` : les heures y sont en **minutes** ; les deux
    loaders (TS et Dart) les convertissent en millisecondes (× 60 000) avant
    d'appeler `findConflict`. Attentes mises à jour : « fin = début de
    l'autre » et « début = fin de l'autre » deviennent des conflits (`o1`),
    renommés « … (moins de 30 min d'écart) ». Nouveaux cas : écart de
    30 min exactement après (autre 690–750) → `null` ; écart de 29 min
    (autre 689–750) → `o1` ; écart de 30 min avant (autre 510–570) → `null` ;
    même pilote sur un autre appareil à 20 min d'écart → `o1`.
  - Intégration (`edit.int.test.ts`) : vol validé 10 h–11 h ; un second sur
    le même appareil à 11 h 20 refusé (`failed-precondition`, message exact
    « Conflit avec un autre vol validé (30 min d'écart minimum). ») ; à
    11 h 30 accepté ; le premier finissant à 10 h 50 est bien trouvé par la
    requête (cas « end > start − 30 min »).
  - App : `describeConflict` se termine par « (30 min d'écart minimum). » ;
    le formulaire signale le conflit pour un vol à 11 h 20 après un vol
    10 h–11 h.
- [ ] **Step 2 : vérifier l'échec.**
- [ ] **Step 3 : implémenter.** `findConflict` (TS et Dart) :
  `c.start < o.end + B && o.start < c.end + B` avec `B` = 30 min en ms ;
  `assertNoConflict` : requête `where("end", ">", Timestamp.fromMillis(slot.start - B))`
  et message mis à jour. Mettre à jour les tests existants qui
  enchaînaient deux vols sans écart (les décaler d'au moins 30 min, sans
  changer ce qu'ils vérifient).
- [ ] **Step 4 : vérifier** — les trois suites.
- [ ] **Step 5 : commit** `feat: 30 min buffer between flights (plan 9)`

---

### Task 5 : docs, vérification complète, déploiement dev

- [ ] **Step 1** : les trois suites passent.
- [ ] **Step 2** : `CLAUDE.md` (français, sections existantes) : référence
  au plan 9 ; prod : Functions version du plan 9 avec l'app web,
  `adminUpdatePricing` exige `toleranceMinutes` et `baptismFees` ; **dev :
  régler « Temps couvert par le forfait » à 60 dans Tarifs** (le document de
  dev contient 75) ; branche non fusionnée.
- [ ] **Step 3 : déploiement dev** (jamais prod) :

```bash
cd functions && npm run build && npx firebase deploy --only functions:createFlight,functions:updateFlight,functions:validateFlight,functions:closeFlight,functions:adminUpdateFlight,functions:adminDeleteFlight,functions:adminUpdatePricing --project dev
```

- [ ] **Step 4 : commit** `docs: CLAUDE.md, plan 9 (overtime, baptism tiers, buffer) done, deploy notes`
