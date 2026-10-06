# UlmGap, plan 10 : lâché amphibie et icônes du menu des profils

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** ajouter la case « Lâché amphibie » aux comptes et l'imposer sur
les appareils amphibies (spec §3.6) ; afficher l'icône de chaque profil dans
le menu « Profil » de la fenêtre de compte.

**Architecture :** comme aux plans précédents : règle pure dans
`functions/src/rules/flights.ts`, miroir Dart dans `lib/core/flight_rules.dart`,
cas partagés `test/fixtures/flight_rules.json` ; contrôle dans `planFlight`
(serveur) ; écritures de comptes par `adminCreateUser` / `adminUpdateUser`.

**Tech Stack :** inchangée.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §1,
§2.1, §2.2, §3.6 (révision du 2026-10-06).

**Branche :** `feature/lache-amphibie`, créée depuis `main`.

## Global Constraints

- Toujours `fvm flutter` / `fvm dart`. TDD. Textes en français. Jamais de
  déploiement en prod.
- Champ `amphibiousCleared` (bool, défaut `false`) sur `users`, recopié dans
  `profiles` à chaque écriture de compte (création et modification).
- Règle sur un appareil `amphibious` (création, modification, validation ;
  **l'admin y échappe**, ainsi que la correction admin) :
  - équipage avec au moins un `instructeur` : au moins un instructeur
    `amphibiousCleared`, sinon « Appareil amphibie : l'instructeur doit être
    lâché amphibie. » ;
  - sans instructeur : au moins un membre `amphibiousCleared`, sinon
    « Appareil amphibie : il faut un pilote lâché amphibie à bord. ».
  Refus serveur en `permission-denied`. La matrice §3.2 reste inchangée.
- Libellés : case « Lâché amphibie » ; mention « amphibie ».
- Tests : `fvm flutter test && fvm flutter analyze` ; `cd functions && npm
  test` ; intégration : `cd functions && JAVA_HOME=/opt/android-studio/jbr
  PATH=/opt/android-studio/jbr/bin:$PATH npm run test:int` (juger sur
  `# fail` / `not ok`).

## Review Focus

1. **Validation par un instructeur non admin** d'une demande sur amphibie
   (`validateFlight` ne passe pas par la matrice) : la règle s'applique
   quand même (Task 2).
2. **Changement d'appareil** vers un amphibie en modification ou validation :
   contrôlé (Task 2).
3. **Ancien compte sans le champ** : traité comme non lâché, et
   `adminUpdateUser` réécrit un `profiles` complet avec le champ (Task 1).
4. **Admin** créateur ou validateur, et correction admin : jamais bloqués
   (Task 2).
5. **Aperçu de l'app** : même verdict que le serveur, sans bloquer un admin
   (Task 3).

---

### Task 1 : champ de compte et règle pure (serveur + miroir Dart)

**Files:**
- Modify: `functions/src/admin/validation.ts` (+ `validation.test.ts`), `functions/src/admin/users.ts`
- Modify: `functions/src/rules/flights.ts` (+ `flights.test.ts`)
- Modify: `lib/core/flight_rules.dart`, `test/core/flight_rules_test.dart`
- Modify: `test/fixtures/flight_rules.json` (nouvelle section `amphibious`)
- Test: `functions/src/admin/admin.int.test.ts`

**Interfaces:**
- Produces:
  - `UserInput.amphibiousCleared: boolean` (`validateNewUser` : défaut
    `false` ; `validateUserPatch` : facultatif) ; `users` et `profiles`
    portent le champ (création ; modification : `profiles` réécrit complet
    avec `merged.amphibiousCleared === true`).
  - TS : `interface AmphibiousPerson { profile: Profile | null; amphibiousCleared: boolean }`,
    `amphibiousError(crew: AmphibiousPerson[]): string | null` (messages
    exacts des Global Constraints).
  - Dart : `class AmphibiousPerson { final String? profile; final bool amphibiousCleared; }`
    et `String? amphibiousError(List<AmphibiousPerson> crew)` dans
    `flight_rules.dart`.

- [ ] **Step 1 : tests qui échouent.**
  - Fixture partagée `amphibious` (lue par `flights.test.ts` et
    `flight_rules_test.dart`), cas :

```json
"amphibious": [
  {"name": "élève + instructeur lâché amphibie", "crew": [{"profile": "eleve", "amphibiousCleared": false}, {"profile": "instructeur", "amphibiousCleared": true}], "expected": null},
  {"name": "élève + instructeur non lâché amphibie", "crew": [{"profile": "eleve", "amphibiousCleared": false}, {"profile": "instructeur", "amphibiousCleared": false}], "expected": "Appareil amphibie : l'instructeur doit être lâché amphibie."},
  {"name": "instructeur non lâché amphibie seul", "crew": [{"profile": "instructeur", "amphibiousCleared": false}], "expected": "Appareil amphibie : l'instructeur doit être lâché amphibie."},
  {"name": "deux instructeurs, un lâché amphibie", "crew": [{"profile": "instructeur", "amphibiousCleared": false}, {"profile": "instructeur", "amphibiousCleared": true}], "expected": null},
  {"name": "lâché non amphibie + instructeur lâché amphibie", "crew": [{"profile": "lache_toute_mission", "amphibiousCleared": false}, {"profile": "instructeur", "amphibiousCleared": true}], "expected": null},
  {"name": "lâché amphibie + instructeur non lâché amphibie", "crew": [{"profile": "lache_toute_mission", "amphibiousCleared": true}, {"profile": "instructeur", "amphibiousCleared": false}], "expected": "Appareil amphibie : l'instructeur doit être lâché amphibie."},
  {"name": "lâché amphibie seul", "crew": [{"profile": "lache_solo", "amphibiousCleared": true}], "expected": null},
  {"name": "lâché non amphibie seul", "crew": [{"profile": "lache_solo", "amphibiousCleared": false}], "expected": "Appareil amphibie : il faut un pilote lâché amphibie à bord."},
  {"name": "deux lâchés, un amphibie", "crew": [{"profile": "lache_toute_mission", "amphibiousCleared": false}, {"profile": "lache_toute_mission", "amphibiousCleared": true}], "expected": null}
]
```

  - Unitaires TS (`admin/validation.test.ts`) : `validateNewUser` rend
    `amphibiousCleared: false` par défaut et `true` si demandé ; valeur non
    booléenne refusée ; `validateUserPatch` accepte `amphibiousCleared` seul.
  - Intégration (`admin.int.test.ts`) : création avec
    `amphibiousCleared: true` → `users` et `profiles` à `true` ; création
    sans → `false` dans les deux ; modification d'un compte ancien sans le
    champ (document écrit à la main) avec un autre champ → `profiles`
    contient `amphibiousCleared: false` ; modification
    `amphibiousCleared: true` → les deux documents à `true`.
- [ ] **Step 2 : vérifier l'échec** (les deux suites).
- [ ] **Step 3 : implémenter** (TS et Dart ; dans `createUser`,
  `profiles` reçoit `amphibiousCleared: input.amphibiousCleared`).
- [ ] **Step 4 : vérifier** — les trois suites.
- [ ] **Step 5 : commit** `feat: amphibious clearance field and rule (plan 10)`

---

### Task 2 : contrôle à la planification (`planFlight`)

**Files:**
- Modify: `functions/src/flights/core.ts` (`loadCrew`, `loadAircraft`, `PlanArgs`, `planFlight`)
- Modify: `functions/src/flights/edit.ts`, `functions/src/flights/actions.ts`, `functions/src/flights/admin-edit.ts`
- Test: `functions/src/flights/edit.int.test.ts`, `functions/src/flights/actions.int.test.ts`, `functions/src/flights/admin-edit.int.test.ts`
- Modify: `functions/src/flights/testkit.ts` (`seedUser` accepte `amphibiousCleared`)

**Interfaces:**
- Consumes: `amphibiousError` (Task 1).
- Produces: `CrewInfo.amphibiousCleared` ; `loadAircraft` rend aussi
  `amphibious: boolean` ; `PlanArgs.skipAmphibious?: boolean`.

- [ ] **Step 1 : tests qui échouent** (intégration, appareil
  `seedAircraft(true, true)` = actif et amphibie) :
  - un lâché solo non lâché amphibie crée un vol seul → refusé
    (`permission-denied`, message exact) ; le même, lâché amphibie →
    accepté ;
  - un élève crée une demande avec un instructeur non lâché amphibie →
    refusé (message instructeur) ; avec un instructeur lâché amphibie →
    `demande` ;
  - un instructeur non lâché amphibie **valide** une demande dont l'appareil
    est amphibie (demande créée sur un appareil classique, puis
    `changes.aircraftId` vers l'amphibie) → refusé ;
  - modification (`updateFlight`) d'un vol classique vers l'appareil
    amphibie par un lâché non amphibie → refusée ;
  - un **admin** non lâché crée un vol sur amphibie avec un équipage non
    lâché → accepté ; correction admin d'un tel vol → acceptée ;
  - appareil non amphibie : aucun changement (un lâché non amphibie vole).
- [ ] **Step 2 : vérifier l'échec.**
- [ ] **Step 3 : implémenter.** `loadCrew` lit `amphibiousCleared === true` ;
  dans `planFlight`, après `decide` :

```ts
  // Spec §3.6 : appareil amphibie, un lâché amphibie aux commandes.
  if (aircraft.amphibious && !a.skipAmphibious) {
    const err = amphibiousError(crew);
    if (err) throw new HttpsError("permission-denied", err);
  }
```

  `createFlight` / `updateFlight` passent `skipAmphibious: me.isAdmin` ;
  `validateFlight` passe `skipAmphibious: me.isAdmin` (le validateur) ;
  `adminUpdateFlight` passe `skipAmphibious: true`.
- [ ] **Step 4 : vérifier** — `npm test` et l'intégration complète.
- [ ] **Step 5 : commit** `feat(functions): enforce amphibious clearance when planning a flight (plan 10)`

---

### Task 3 : app (modèles, aperçu du formulaire, fenêtre de compte, listes)

**Files:**
- Modify: `lib/data/app_user.dart`, `lib/data/crew_member.dart`, `test/support/fakes.dart`
- Modify: `lib/features/flight/flight_screen.dart`
- Modify: `lib/features/admin/user_form_dialog.dart`, `lib/features/admin/users_admin_screen.dart`,
  `lib/features/account/account_screen.dart`
- Test: `test/data/user_repository_test.dart` ou le test qui couvre `AppUser.fromMap`,
  `test/features/flight/flight_screen_test.dart`, `test/features/admin/users_admin_screen_test.dart`,
  `test/features/account/account_screen_test.dart`

**Interfaces:**
- Consumes: `amphibiousError`, `AmphibiousPerson` (Task 1, Dart).
- Produces: `AppUser.amphibiousCleared`, `CrewMember.amphibiousCleared`
  (bool, défaut false) ; `testUser(amphibiousCleared:)`,
  `member(..., amphibiousCleared:)` ; clé `user-amphibious` (case de la
  fenêtre de compte) ; payload `amphibiousCleared` envoyé par la fenêtre.

- [ ] **Step 1 : tests qui échouent** (complets, à partir des mises en
  place voisines) :
  1. Formulaire de vol, appareil amphibie (fake `Aircraft` avec
     `amphibious: true`), créateur lâché solo non lâché amphibie seul :
     l'aperçu affiche « Appareil amphibie : il faut un pilote lâché
     amphibie à bord. » et « Enregistrer » est refusé localement (rien
     envoyé) ; même créateur avec `amphibiousCleared: true` : enregistré.
  2. Élève + instructeur de l'annuaire non lâché amphibie sur amphibie :
     message instructeur dans l'aperçu.
  3. Admin créateur avec un équipage non lâché : pas de message, enregistré.
  4. Fenêtre de compte : case « Lâché amphibie » (clé `user-amphibious`),
     décochée par défaut en création, pré-cochée en modification d'un compte
     lâché amphibie, envoyée dans le payload (`amphibiousCleared`).
  5. Menu « Profil » de la fenêtre de compte : chaque choix pilote affiche
     son `ProfileBadge` (icône) devant le libellé (vérifier un
     `ProfileBadge` par profil dans le menu ouvert) ; « Non pilote » sans
     badge.
  6. Liste des utilisateurs : « amphibie » visible pour un compte lâché
     amphibie ; « Mon compte » : « Lâché amphibie » affiché pour un tel
     compte, absent sinon.
- [ ] **Step 2 : vérifier l'échec.**
- [ ] **Step 3 : implémenter.** Dans `flight_screen.dart`, un getter
  `String? get _amphibiousError` : `null` si l'admin est créateur (ou en
  correction admin), si l'appareil choisi n'est pas amphibie, ou si aucun
  verdict n'est calculable ; sinon `amphibiousError` sur l'équipage
  (`_me` pour soi, `_dir` pour les autres) ; affiché dans l'aperçu (texte
  d'erreur) et renvoyé par `_localError` avant les autres contrôles de
  crédit. Fenêtre de compte : `SwitchListTile` ou `CheckboxListTile`
  « Lâché amphibie » ; menu Profil : `Row(children: [ProfileBadge(profile: p, compact: true), SizedBox(width: 8), Text(p.label)])`.
- [ ] **Step 4 : vérifier** — `fvm flutter test && fvm flutter analyze`.
- [ ] **Step 5 : commit** `feat(app): amphibious clearance in accounts and flight form, profile icons in the account form (plan 10)`

---

### Task 4 : docs, vérification complète, déploiement dev

- [ ] **Step 1** : les trois suites passent.
- [ ] **Step 2** : `CLAUDE.md` (français, sections existantes) : référence
  au plan 10 ; dev : Functions redéployées, app à reconstruire, cocher
  « Lâché amphibie » sur les comptes concernés ; prod (bloc unique) :
  Functions version du plan 10 avec l'app web, puis cocher « Lâché
  amphibie » sur les comptes concernés avant de voler sur l'amphibie ;
  branche non fusionnée.
- [ ] **Step 3 : déploiement dev** (jamais prod) :

```bash
cd functions && npm run build && npx firebase deploy --only functions:adminCreateUser,functions:adminUpdateUser,functions:createFlight,functions:updateFlight,functions:validateFlight,functions:adminUpdateFlight --project dev
```

- [ ] **Step 4 : commit** `docs: CLAUDE.md, plan 10 (amphibious clearance) done, deploy notes`
