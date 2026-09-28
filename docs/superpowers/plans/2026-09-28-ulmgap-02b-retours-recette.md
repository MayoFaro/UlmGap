# UlmGap, plan 2b : retours de la recette du plan 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** appliquer les retours de la recette du plan 2 :
- le compte débité est imposé ;
- « carburant seulement » est conservé ;
- le message de refus pour un élève est reformulé ;
- le conflit dit ce qui le cause ;
- un vol s'ouvre dans une seule fenêtre ;
- le planning est en colonnes par appareil, avec les vols de l'utilisateur mis en évidence ;
- un script crée des comptes de test en dev.

**Architecture :** inchangée (plan 2). Les règles pures restent dans
`functions/src/rules/flights.ts`, avec un miroir Dart dans
`lib/core/flight_rules.dart` et des cas partagés dans
`test/fixtures/flight_rules.json`. Le détail et le formulaire de vol
fusionnent en un seul écran, `FlightScreen`.

**Tech Stack :** identique au plan 2.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, complétée
par les décisions ci-dessous (elles priment sur la spec quand elles la
précisent).

## Décisions de l'utilisateur (2026-09-28, recette du plan 2)

1. **Compte débité** (nouveau libellé de « payeur », partout dans l'app) :
   - pour un créateur qui n'est **ni instructeur ni admin**, le premier de
     l'équipage (`crew[0]`) est obligatoirement lui-même ; le serveur le
     vérifie et l'app masque « Mettre en premier » ;
   - les instructeurs et les admins restent libres de l'ordre.
2. **Carburant seulement** :
   - seuls un instructeur ou un admin cochent ou décochent la case ;
   - quand un non-instructeur modifie le vol, le mode précédent est
     **conservé** ;
   - un équipage entièrement GAP avec un passager sans compte reste
     automatiquement en « carburant seulement ».
3. **Vouvoiement partout.** Nouveau message de refus pour un élève sans
   instructeur : « Impossible de créer un vol à votre profit sans la présence
   d'un instructeur. »
4. **Une seule fenêtre par vol** : les détails s'affichent dans des champs,
   modifiables selon les droits. Les boutons sont en bas de l'écran
   (Enregistrer, Valider, Refuser, Annuler le vol). Toute action ramène au
   planning. La confirmation de l'heure de fin est supprimée ; la
   confirmation d'annulation est conservée.
5. **Planning** :
   - « À valider » et « Mes demandes » restent en haut ;
   - ensuite, jour par jour, une colonne par appareil, avec défilement
     horizontal au-delà de deux appareils ;
   - le filtre par appareil est supprimé.
6. **Mise en évidence** des vols où l'utilisateur est dans l'équipage : fond
   `#E3F2FD` et contour `#1E88E5`, sur toute la largeur de la tuile.
7. **Appareil par défaut** à la création : le premier de la liste.
8. **Conflit expliqué** (constat de recette : un conflit « de personne » a été
   pris pour un conflit d'appareil). Le message indique la cause :
   - « Conflit : TR-KJP est déjà réservé sur le vol du … » quand c'est
     l'appareil ;
   - « Conflit : RAL est déjà sur le vol du … » quand c'est une personne.

   L'appareil est prioritaire si les deux s'appliquent.

## Décisions du contrôleur (à relire)

- Mode conservé pour un non-instructeur **seulement si le vol n'avait pas de
  passager sans compte**. Sans cette règle, un « carburant seulement » imposé
  par un passager survivrait au retrait de ce passager sans qu'aucun
  instructeur l'ait choisi.
- **Comptes de test** : `functions/scripts/seed-test-users.js`, refusé pour
  tout projet autre que `ulmgap-dev` ou `demo-*`. Les e-mails sont en
  `@ulmgap.invalid` (domaine réservé), déjà vérifiés, avec le mot de passe
  passé en argument.

## Global Constraints

Celles du plan 2 (`docs/superpowers/plans/2026-09-28-ulmgap-02-vols.md`,
section Global Constraints) restent en vigueur, notamment :
- `fvm flutter`, jamais de déploiement en prod ;
- écritures métier uniquement par les callables `europe-west1` ;
- champs contrat de `flights` inchangés ;
- TDD ;
- textes en français, **au vouvoiement**.

Libellés, couleurs de statut et de mise en évidence : uniquement dans
`lib/features/flight/flight_texts.dart`.

## Review Focus

1. Un lâché ou un élève qui appelle `createFlight` / `updateFlight` en
   plaçant quelqu'un d'autre en premier : `permission-denied`. → test
   d'intégration (Task 1).
2. Un « carburant seulement » choisi par un instructeur survit à une
   modification par le créateur non instructeur, mais pas au retrait d'un
   passager. → tests (Task 1).
3. Un seul écran pour un vol existant : les boutons affichés correspondent
   exactement aux droits (`flightActions`), et chaque action ramène au
   planning. → tests de widgets (Task 3).
4. Planning avec 3 appareils sur un écran de téléphone : colonnes
   accessibles par défilement horizontal, sans débordement. → test de
   widgets (Task 4).
5. Script de comptes de test lancé par erreur sur la prod : refus avant
   toute écriture. → test unitaire (Task 5).

---

### Task 1 : règles serveur (compte débité, mode conservé, message, cause du conflit)

**Files :**
- Modify: `functions/src/rules/flights.ts`, `functions/src/rules/flights.test.ts`, `test/fixtures/flight_rules.json`, `functions/src/flights/core.ts`, `functions/src/flights/edit.ts`, `functions/src/flights/edit.int.test.ts`

**Interfaces :**
- Produces (`rules/flights.ts`) :
  - `checkPayer(creator: Creator, crew: string[]): string | null` : message
    d'erreur, ou `null` ;
  - `conflictCause(candidate: Slot, other: Slot): { kind: "aircraft" | "crew"; members: string[] }` ;
  - `resolvePricingMode` : quand `mayChoose` est faux, renvoie `fuel_only`
    si `previous === "fuel_only"` (sinon `standard`), en plus des règles
    existantes ;
  - message élève : `"Impossible de créer un vol à votre profit sans la présence d'un instructeur."`.
- Détails d'erreur de conflit enrichis :
  `details.conflict = { start, end, aircraft, crew, passengers, kind, members }`.
- Fixture : nouvelles clés `payer` et, dans chaque cas de `conflicts`
  attendu non nul, `expectedCause`.

- [ ] **Step 1 : cas partagés**

Dans `test/fixtures/flight_rules.json` :

- Remplacer l'objet `pricing` dont le `name` vaut
  `"entre GAP, non instructeur, mode précédent carburant"` par :

```json
    { "name": "entre GAP, non instructeur, mode précédent carburant : conservé", "allGap": true, "hasPassenger": false, "mayChoose": false, "previous": "fuel_only", "expected": "fuel_only" },
    { "name": "entre GAP, non instructeur, mode précédent standard", "allGap": true, "hasPassenger": false, "mayChoose": false, "previous": "standard", "expected": "standard" },
    { "name": "non GAP, non instructeur, mode précédent carburant", "allGap": false, "hasPassenger": false, "mayChoose": false, "previous": "fuel_only", "expected": "standard" }
```

- Dans `conflicts`, ajouter aux cas attendus non nuls :
  - « même appareil, chevauchement » :
    `"expectedCause": { "kind": "aircraft", "members": [] }` ;
  - « autre appareil, même pilote » :
    `"expectedCause": { "kind": "crew", "members": ["p2"] }` ;
  - « englobé entièrement » :
    `"expectedCause": { "kind": "aircraft", "members": [] }`.
- Ajouter une clé racine `payer` :

```json
  "payer": [
    { "name": "lâché en premier : ok", "creator": { "uid": "c", "profile": "lache_toute_mission", "isAdmin": false }, "crew": ["c", "x"], "ok": true },
    { "name": "lâché en second : refusé", "creator": { "uid": "c", "profile": "lache_toute_mission", "isAdmin": false }, "crew": ["x", "c"], "ok": false },
    { "name": "élève en second : refusé", "creator": { "uid": "c", "profile": "eleve", "isAdmin": false }, "crew": ["i", "c"], "ok": false },
    { "name": "instructeur en second : libre", "creator": { "uid": "c", "profile": "instructeur", "isAdmin": false }, "crew": ["x", "c"], "ok": true },
    { "name": "admin hors équipage : libre", "creator": { "uid": "a", "profile": null, "isAdmin": true }, "crew": ["x", "y"], "ok": true }
  ]
```

- [ ] **Step 2 : tests TypeScript qui échouent**

Dans `functions/src/rules/flights.test.ts`, importer `checkPayer` et
`conflictCause`, puis ajouter :

```ts
for (const c of fx.payer) {
  test(`compte débité : ${c.name}`, () => {
    const r = checkPayer(c.creator, c.crew);
    if (c.ok) assert.equal(r, null);
    else assert.equal(r, "Le compte débité doit être le vôtre : placez-vous en premier.");
  });
}

for (const c of fx.conflicts.filter((x: { expectedCause?: unknown }) => x.expectedCause)) {
  test(`cause du conflit : ${c.name}`, () => {
    const other = findConflict(c.candidate, c.others)!;
    assert.deepEqual(conflictCause(c.candidate, other), c.expectedCause);
  });
}

test("message élève au vouvoiement", () => {
  const d = decideStatus({ uid: "c", profile: "eleve", isAdmin: false },
    [{ uid: "c", profile: "eleve" }], 0);
  assert.deepEqual(d, { ok: false,
    reason: "Impossible de créer un vol à votre profit sans la présence d'un instructeur." });
});
```

Run : `cd functions && npm test`. Expected : FAIL.

- [ ] **Step 3 : implémentation pure**

Dans `functions/src/rules/flights.ts` :
- remplacer le message élève par
  `"Impossible de créer un vol à votre profit sans la présence d'un instructeur."` ;
- remplacer dans `resolvePricingMode` la ligne
  `if (!a.mayChoose) return "standard";` par
  `if (!a.mayChoose) return a.previous === "fuel_only" ? "fuel_only" : "standard";` ;
- ajouter :

```ts
/** Décision utilisateur : hors instructeurs et admins, le créateur est le compte débité. */
export function checkPayer(creator: Creator, crew: string[]): string | null {
  if (creator.isAdmin || creator.profile === "instructeur") return null;
  return crew[0] === creator.uid
    ? null
    : "Le compte débité doit être le vôtre : placez-vous en premier.";
}

/** Cause d'un conflit : l'appareil d'abord, sinon les personnes communes. */
export function conflictCause(
  candidate: Slot, other: Slot,
): { kind: "aircraft" | "crew"; members: string[] } {
  if (candidate.aircraftId === other.aircraftId) return { kind: "aircraft", members: [] };
  return { kind: "crew", members: candidate.crew.filter((u) => other.crew.includes(u)) };
}
```

Run : `cd functions && npm test`. Expected : PASS.

- [ ] **Step 4 : tests d'intégration qui échouent**

Ajouter à `functions/src/flights/edit.int.test.ts` :

```ts
test("compte débité : un lâché ne place pas un autre en premier (appel direct)", async () => {
  const me = await seedUser({ profile: "lache_toute_mission" });
  const other = await seedUser({ profile: "lache_toute_mission" });
  await assert.rejects(createFlight(me, draft(await seedAircraft(), [other.uid, me.uid])),
    (e) => code(e) === "permission-denied");
  const a = await seedAircraft();
  const { id } = await createFlight(me, draft(a, [me.uid, other.uid]));
  await assert.rejects(updateFlight(me, { flightId: id, ...draft(a, [other.uid, me.uid]) }),
    (e) => code(e) === "permission-denied");
});

test("carburant choisi par l'instructeur : conservé quand le créateur non instructeur modifie", async () => {
  const eleve = await seedUser({ profile: "eleve", category: "GAP" });
  const instr = await seedUser({ profile: "instructeur", category: "GAP" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(50), end: at(51), aircraftId: a, crew: [eleve.uid, instr.uid], createdBy: eleve.uid,
    instructorUid: instr.uid, status: "valide", pricingMode: "fuel_only",
  });
  await updateFlight(eleve, { flightId: id, ...draft(a, [eleve.uid, instr.uid], { start: at(50), end: at(51), destination: "Kara" }) });
  assert.equal((await get(id)).pricingMode, "fuel_only");
});

test("carburant imposé par un passager : perdu quand le passager est retiré", async () => {
  const gap = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await createFlight(gap, draft(a, [gap.uid], { start: at(60), end: at(61), passengers: ["Paul"] }));
  assert.equal((await get(id)).pricingMode, "fuel_only");
  await updateFlight(gap, { flightId: id, ...draft(a, [gap.uid], { start: at(60), end: at(61) }) });
  assert.equal((await get(id)).pricingMode, "standard");
});

test("conflit : la cause (appareil ou personne) est dans les détails", async () => {
  const p1 = await seedUser({ profile: "instructeur" });
  const p2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  await createFlight(p1, draft(a, [p1.uid], { start: at(70), end: at(71) }));
  await assert.rejects(createFlight(p2, draft(a, [p2.uid], { start: at(70), end: at(71) })),
    (e) => details(e)?.conflict?.kind === "aircraft");
  await assert.rejects(createFlight(p1, draft(await seedAircraft(), [p1.uid], { start: at(70), end: at(71) })),
    (e) => details(e)?.conflict?.kind === "crew" &&
      JSON.stringify(details(e)?.conflict?.members) === JSON.stringify([p1.uid]));
});
```

Run : l'intégration (commande de CLAUDE.md). Expected : FAIL sur ces 4
tests.

- [ ] **Step 5 : branchement serveur**

- `functions/src/flights/edit.ts` :
  - importer `checkPayer` ;
  - dans `createFlight` et `updateFlight`, juste après la validation
    d'entrée, ajouter :

    ```ts
    const payerError = checkPayer(me, input.crew);
    if (payerError) throw new HttpsError("permission-denied", payerError);
    ```

  - dans `updateFlight`, remplacer
    `previousMode: f.get("pricingMode") as PricingMode,` par :

    ```ts
    // Mode conservé seulement si aucun passager ne l'imposait (décision 2b).
    previousMode: ((f.get("passengers") as string[] | undefined) ?? []).length === 0
      ? (f.get("pricingMode") as PricingMode)
      : undefined,
    ```

- `functions/src/flights/core.ts`, dans `assertNoConflict` : importer
  `conflictCause`, puis ajouter au `conflict` des détails
  `...conflictCause(slot, c)`, ce qui fournit `kind` et `members`.

Run : unitaires et intégration. Expected : PASS (y compris les tests
existants).

- [ ] **Step 6 : commit**

```bash
git add functions test/fixtures/flight_rules.json
git commit -m "feat(functions): creator is the debited account, keep instructor fuel choice, explain conflicts"
```

---

### Task 2 : miroir Dart et textes (compte débité, cause du conflit, vouvoiement)

**Files :**
- Modify: `lib/core/flight_rules.dart`, `test/core/flight_rules_test.dart`, `lib/data/flight_api.dart`, `test/data/flight_api_test.dart`, `lib/features/flight/flight_texts.dart`, `test/support/fakes.dart` (si besoin)
- Create: `test/features/flight/flight_texts_test.dart`

**Interfaces :**
- Produces :
  - Dart `checkPayer({required String creatorUid, required String? creatorProfile, required bool creatorIsAdmin, required List<String> crew}) → String?` ;
  - Dart `conflictCause(RuleFlight candidate, RuleFlight other) → ({String kind, List<String> members})` ;
  - `resolvePricingMode` et le message élève alignés sur la Task 1 ;
  - `ConflictInfo` gagne `kind` (`'aircraft'` | `'crew'`, défaut
    `'aircraft'`) et `members` (`List<String>`, défaut vide), décodés par
    `flightFailureFrom` ;
  - `describeConflict` produit :
    - `aircraft` : `'Conflit : <aircraft> est déjà réservé sur le vol du <jour>, <créneau> (<équipage>).'`
    - `crew` : `'Conflit : <codes des members, séparés par « / »> est déjà sur le vol du <jour>, <créneau> (<aircraft>, <équipage>).'`
  - `const debitedLabel = 'Compte débité';` dans `flight_texts.dart`.
  - `const highlightFill = Color(0xFFE3F2FD);` et
    `const highlightBorder = Color(0xFF1E88E5);` dans `flight_texts.dart`.

- [ ] **Step 1 : tests qui échouent**
  - `test/core/flight_rules_test.dart` rejoue `fx['payer']` : `ok` vrai →
    `checkPayer` renvoie `null` ; faux → le message exact de la Task 1.
  - Le même fichier rejoue `expectedCause` pour les conflits concernés.
  - `test/data/flight_api_test.dart` : `flightFailureFrom` décode `kind` et
    `members` quand ils sont présents, et prend les défauts
    (`'aircraft'`, `[]`) sinon.
  - `test/features/flight/flight_texts_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/flight_api.dart';
import 'package:ulmgap/features/flight/flight_texts.dart';

import '../../support/fakes.dart';

void main() {
  final dir = {for (final m in [member('ral', 'RAL', 'eleve'), member('hil', 'HIL', 'lache_toute_mission')]) m.uid: m};
  ConflictInfo info(String kind, List<String> members) => ConflictInfo(
      start: DateTime(2026, 9, 30, 15), end: DateTime(2026, 9, 30, 16),
      aircraft: 'TR-KJP', crew: const ['hil', 'ral'], passengers: const [],
      kind: kind, members: members);

  test('conflit d\'appareil', () {
    expect(describeConflict(info('aircraft', const []), dir),
        'Conflit : TR-KJP est déjà réservé sur le vol du mercredi 30 septembre, 15:00–16:00 (HIL/RAL).');
  });
  test('conflit de personne', () {
    expect(describeConflict(info('crew', const ['ral']), dir),
        'Conflit : RAL est déjà sur le vol du mercredi 30 septembre, 15:00–16:00 (TR-KJP, HIL/RAL).');
  });
}
```

Run : `fvm flutter test`. Expected : FAIL.

- [ ] **Step 2 : implémentation**
  - Porter à l'identique dans `lib/core/flight_rules.dart` : le message
    élève, `resolvePricingMode` (quand `mayChoose` est faux : `previous ==
    'fuel_only'` donne `'fuel_only'`, sinon `'standard'`), `checkPayer`
    (même message) et `conflictCause`.
  - `lib/data/flight_api.dart` : ajouter à `ConflictInfo` les champs
    `this.kind = 'aircraft'` et `this.members = const []`, et les décoder
    dans `flightFailureFrom` (`c['kind']`, `c['members']`).
  - `lib/features/flight/flight_texts.dart` : réécrire `describeConflict`
    selon les formats ci-dessus, en tirant les codes courts de `dir` (repli
    sur `'?'`), et ajouter `debitedLabel`, `highlightFill`,
    `highlightBorder`.
  - Vérifier par `grep -rn "\btu\b\|\bton\b\|\btes\b\|\bte\b" lib` qu'aucun
    texte d'interface ne tutoie.

Run : `fvm flutter test && fvm flutter analyze`. Expected : PASS. Les tests
de formulaire qui attendent l'ancien texte de conflit doivent être mis à
jour vers le nouveau format.

- [ ] **Step 3 : commit**

```bash
git add lib test
git commit -m "feat: mirror debited-account rule and conflict cause in the app"
```

---

### Task 3 : une seule fenêtre par vol

**Files :**
- Create: `lib/features/flight/flight_screen.dart` (via `git mv lib/features/flight/flight_form_screen.dart lib/features/flight/flight_screen.dart`), `test/features/flight/flight_screen_test.dart` (via `git mv` du test de formulaire, puis fusion du test de détail)
- Delete: `lib/features/flight/flight_detail_screen.dart`, `test/features/flight/flight_detail_screen_test.dart`
- Modify: `lib/features/home/home_shell.dart`

**Interfaces :**
- Consumes : `flightActions` / `FlightAction` (inchangés), `FlightApi`,
  `checkPayer`, `debitedLabel`, `describeConflict`.
- Produces : `FlightScreen({required AppUser me, Flight? flight, DateTime Function() now = DateTime.now})`.
  - `flight == null` → création.
  - Sinon, droits calculés par
    `flightActions(flight, me, now())` :
    - `validate` → horaires, destination, appareil et carburant modifiables,
      équipage figé ;
    - `edit` (et pas `validate`) → tout est modifiable ;
    - sinon → lecture seule.
  - `FlightFormMode` et `FlightDetailScreen` disparaissent.

Comportement attendu :
1. **Titre** : « Nouveau vol », ou le jour du vol (`formatDay`).
2. **En tête, pour un vol existant**, les lignes du détail actuel :
   - statut coloré, avec « Refusé (non validée avant le départ) » pour une
     demande expirée ;
   - motif du refus ;
   - « Instructeur désigné : X » ;
   - « Tarification : … ».
3. **Champs** (date, départ, fin, appareil, équipage, passager, destination,
   carburant). Ce sont ceux du formulaire actuel, avec les contrôles
   (`onTap`, `onChanged`, boutons d'équipage) désactivés quand ils ne sont
   pas modifiables.
4. **Libellés** : « Payeur » devient `debitedLabel` : sous-titre du premier
   équipier, et ligne `Key('payer')` « Compte débité : X » (clé conservée),
   aussi dans l'aperçu.
5. **« Mettre en premier »** n'est affiché que si
   `me.isAdmin || me.isInstructor`.
6. **Appareil par défaut** en création : dès que la liste des appareils
   actifs arrive et que `_aircraftId == null`, prendre le premier.
7. **Aperçu** conservé, seulement quand quelque chose est modifiable.
8. **Boutons en bas** (dans `bottomNavigationBar`, `SafeArea` puis `Padding`
   puis `Wrap`) ; plus aucun bouton dans l'`AppBar` :
   - création ou `edit` : `FilledButton` « Enregistrer » ;
   - `validate` : `FilledButton` « Valider » et `OutlinedButton`
     « Refuser », avec le dialogue de motif actuel (`_RefuseDialog`) ;
   - `cancel` : `TextButton` « Annuler le vol », avec la confirmation
     actuelle (« Oui, annuler »).
9. **Plus de dialogue « Heure de fin »** : la sauvegarde appelle
   directement l'API.
10. **Contrôles locaux** : garder ceux existants, et ajouter `checkPayer` (le
    message s'affiche et rien n'est envoyé).
11. **Après tout succès** (enregistrer, valider, refuser, annuler) :
    `Navigator.of(context).maybePop(true)`, ce qui ramène au planning.
12. **Erreurs** : `FlightConflict` produit `describeConflict` ;
    `FlightFailure` produit son message ; toute autre erreur produit
    « Enregistrement impossible. Réessayez. ».
13. **HomeShell** : `onOpen` et le bouton « + » poussent `FlightScreen`.

- [ ] **Step 1 : tests qui échouent** (`test/features/flight/flight_screen_test.dart`)

Reprendre les tests existants du formulaire et du détail, adaptés : plus de
`mode`, plus de confirmation de fin, « Compte débité » au lieu de
« Payeur », et le bouton « Enregistrer » trouvé par `find.text` au lieu du
tooltip. Ajouter :
- création : l'appareil est présélectionné (« ULM 1 (F-JABC) » affiché sans
  toucher la liste) ;
- élève : « Mettre en premier » absent ; instructeur : présent ;
- instructeur désigné sur une demande : boutons « Valider » et « Refuser »
  présents, « Enregistrer » absent. Changer la destination puis appuyer sur
  « Valider » : `api.validated['d']['destination']` a la nouvelle valeur, et
  l'écran se ferme (le planning reste, sous forme d'un `Scaffold` racine
  poussé dans le test) ;
- créateur d'une demande : « Enregistrer » et « Annuler le vol » présents,
  « Valider » absent. Après annulation confirmée : `api.cancelled == ['d']`,
  et l'écran est fermé ;
- utilisateur sans droit : aucun bouton, et les champs ne réagissent pas
  (appuyer sur l'appareil n'ouvre pas de liste) ;
- demande expirée : « Refusé (non validée avant le départ) », aucun bouton ;
- refus avec motif : `api.refused['d'] == 'Météo'`, écran fermé.

Pour vérifier « écran fermé », héberger le test ainsi :
`MaterialApp(home: Builder(builder: (c) => Scaffold(body: Text('planning'), floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => FlightScreen(...))))))`.
Ouvrir l'écran, agir, puis `expect(find.text('planning'), findsOneWidget)`
et `expect(find.byType(FlightScreen), findsNothing)`. Garder l'agrandissement
de la vue de test déjà utilisé par le test de détail si le contenu dépasse.

Run : `fvm flutter test test/features/flight`. Expected : FAIL.

- [ ] **Step 2 : implémentation** selon « Comportement attendu », à partir du
  fichier déplacé. Garder `_PassengerDialog` et reprendre `_RefuseDialog`
  depuis l'ancien détail. Supprimer `flight_detail_screen.dart` et son test.
  Mettre à jour `home_shell.dart`.

Run : `fvm flutter test && fvm flutter analyze`. Expected : PASS.

- [ ] **Step 3 : commit**

```bash
git add -A lib test
git commit -m "feat: single flight screen (view, edit, validate, refuse, cancel) with bottom actions"
```

---

### Task 4 : planning en colonnes par appareil, vols de l'utilisateur mis en évidence

**Files :**
- Modify: `lib/features/planning/planning_screen.dart`, `lib/features/planning/flight_tile.dart`, `test/features/planning/planning_screen_test.dart`
- Create: `lib/features/planning/flight_card.dart`

**Interfaces :**
- Consumes : `highlightFill`, `highlightBorder`, `statusLabel`,
  `statusColor`, `crewText` (Task 2).
- Produces :
  - `FlightTile` gagne `bool mine`. Quand `mine` vaut vrai, la tuile est
    enveloppée dans un `Container` pleine largeur (fond `highlightFill`,
    contour `highlightBorder` de 2 px, coins arrondis de 8, marge
    horizontale de 8).
  - `FlightCard({flight, dir, now, mine, onTap})` : carte compacte pour une
    colonne. Elle affiche le créneau, l'équipage avec ses badges, la
    destination et le statut en texte coloré. Même mise en évidence si
    `mine`.
  - `Key('col-<aircraftId>')` sur chaque colonne ; en-tête de colonne
    `'<label> (<immatriculation>)'`.

Comportement attendu :
1. Le filtre par appareil est supprimé.
2. En haut, « À valider » et « Mes demandes » gardent leur logique actuelle,
   en `FlightTile` pleine largeur, avec `mine = f.crew.contains(me.uid)`.
3. Ensuite vient une **grille** dans un unique
   `SingleChildScrollView(scrollDirection: Axis.horizontal)`, pour que tous
   les jours défilent ensemble.
   - **Colonnes** : les appareils actifs, triés par libellé, puis tout
     `aircraftId` présent dans les vols et absent de cette liste (en-tête =
     immatriculation du vol).
   - **Largeur de colonne**, calculée par `LayoutBuilder` sur la largeur
     disponible `w` :
     - 1 colonne : `w` ;
     - 2 colonnes ou plus : `max((w - 8) / 2, 160)`.
   - **Contenu**, avec des `Column` non paresseuses (volume d'un club) :
     1. une ligne d'en-têtes de colonnes ;
     2. pour chaque jour, un titre `formatDay` sur la largeur totale ;
     3. une `Row` de colonnes, avec pour chacune les `FlightCard` du jour
        triées par départ, ou un « — » discret si la colonne est vide ce
        jour-là.
4. États chargement, erreur et vide : inchangés (`asyncState`).
5. `mine` = l'utilisateur est dans `crew`.

- [ ] **Step 1 : tests qui échouent** (adapter le fichier existant)
- Retirer le test du filtre.
- Deux appareils et des vols sur chacun : la carte d'un vol de `a2` est
  descendante de `find.byKey(Key('col-a2'))`, et pas de `col-a1`.
- Trois appareils en surface 400×800 (`tester.view.physicalSize` avec
  `devicePixelRatio` 1) : aucune exception de débordement ; `col-a3` est
  d'abord hors écran, puis visible après
  `tester.drag(find.byType(SingleChildScrollView).first, const Offset(-400, 0))`.
- Mise en évidence : le vol où `me` est dans l'équipage est un descendant
  d'un `Container` dont la `BoxDecoration` a la couleur `highlightFill` ; un
  vol sans `me` ne l'est pas.
- Conserver les tests des rubriques, de la demande expirée, du vide et de
  l'erreur.

Run : `fvm flutter test test/features/planning`. Expected : FAIL.

- [ ] **Step 2 : implémentation** selon « Comportement attendu ».

Run : `fvm flutter test && fvm flutter analyze`. Expected : PASS.

- [ ] **Step 3 : commit**

```bash
git add lib test
git commit -m "feat: planning in aircraft columns with horizontal scroll, highlight the user's flights"
```

---

### Task 5 : comptes de test en dev

**Files :**
- Create: `functions/src/admin/seed.ts`, `functions/src/admin/seed.test.ts`, `functions/scripts/seed-test-users.js`
- Modify: `functions/src/admin/admin.int.test.ts`, `README.md`

**Interfaces :**
- Produces :
  - `assertSeedAllowed(projectId: string): void` : lève une `Error` si
    `projectId` n'est ni `ulmgap-dev` ni un nom commençant par `demo-` ;
  - `TEST_ACCOUNTS` : la liste figée ci-dessous ;
  - `seedTestUsers(auth, db, password: string): Promise<string[]>` :
    renvoie les e-mails, et peut être relancée sans effet de bord.

Liste des comptes (e-mail `test-<code>@ulmgap.invalid`) :

| code | Nom | Court | Profil | Appartenance |
|---|---|---|---|---|
| eleve-ext | Élève Externe | EEX | eleve | EXT |
| eleve-gap | Élève GAP | EGA | eleve | GAP |
| solo-gap | Lâché Solo GAP | LSG | lache_solo | GAP |
| ltm-gap | Lâché Mission GAP | LMG | lache_toute_mission | GAP |
| ltm-mil | Lâché Mission MIL | LMM | lache_toute_mission | MIL |
| instr-gap | Instructeur GAP | IGA | instructeur | GAP |
| instr-gr | Instructeur GR | IGR | instructeur | GR |
| gest-gap | Gestionnaire GAP | GES | null | GAP |

Pour chaque compte :
- Auth :
  - s'il existe (`getUserByEmail` réussit), `updateUser` avec
    `{ password, emailVerified: true, disabled: false }` ;
  - s'il n'existe pas (`auth/user-not-found` seulement), `createUser` avec
    `{ email, password, displayName, emailVerified: true }`.
- Firestore :
  - `users/{uid}` complet, écrit avec `set(..., { merge: true })` sans
    toucher `balance` ni `createdAt` si le document existe
    (`balance: 0` et `createdAt` seulement à la création) ;
  - `profiles/{uid}` complet ;
  - `isAdmin: false`, `active: true`.

Script : `node scripts/seed-test-users.js --project ulmgap-dev --password <min. 8 car.>`.
Il appelle `assertSeedAllowed` **avant** `initializeApp`, puis affiche la
liste des e-mails créés.

- [ ] **Step 1 : tests qui échouent**
  - `seed.test.ts` (unitaire) :
    - `assertSeedAllowed("ulmgap-prod")` lève une erreur ;
    - `"ulmgap-dev"` et `"demo-ulmgap"` passent.
  - `admin.int.test.ts` :
    - `seedTestUsers` crée 8 comptes vérifiés, avec des documents `users`
      et `profiles` complets ;
    - une relance conserve un `balance` modifié entre-temps.
- [ ] **Step 2 : implémentation** (le script requiert `../lib/admin/seed`,
  comme `bootstrap-admin.js`). Ajouter au README une section « Comptes de
  test (dev) ».
- [ ] **Step 3 :** unitaires et intégration PASS. Commit
  `feat: dev-only test accounts script`.

---

### Task 6 : déploiement dev et CLAUDE.md

- [ ] Suites complètes (Flutter, analyze, unitaires, intégration) : PASS.
- [ ] `firebase deploy --project dev --only firestore:rules,functions`
  (**jamais prod**).
- [ ] Mettre à jour CLAUDE.md :
  - ajouter le plan 2b aux documents de référence ;
  - l'état ;
  - retirer des « Questions ouvertes » les deux points tranchés (compte
    débité, carburant) ;
  - noter la commande des comptes de test.

  Commit `docs: CLAUDE.md after plan 2b`.
