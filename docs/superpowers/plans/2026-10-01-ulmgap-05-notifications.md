# UlmGap, plan 5 : Node 22, notifications push et rappels de clôture

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :**
- passer les Functions à Node 22 avant le retrait de Node 20 par Google
  (30/10/2026) ;
- envoyer les notifications push de la spec §6.1 sur Android et sur le web ;
- relancer l'équipage d'un vol non clôturé 24 h après sa fin, puis toutes
  les 48 h.

**Architecture :**
- **Serveur.**
  - Un module pur, `functions/src/rules/notifications.ts`, décide des
    destinataires et du texte de chaque événement.
  - Un module d'envoi, `functions/src/notify/push.ts`, lit les jetons
    `users.fcmToken`, envoie par FCM et efface les jetons périmés. Il
    journalise les erreurs et **ne lève jamais d'exception**.
  - Les actions appellent l'envoi **après** la réussite de leur transaction.
    Un échec d'envoi n'annule jamais l'action (spec §6.1).
- **Rappels.** Une tâche planifiée (`onSchedule`, toutes les heures,
  `europe-west1`) cherche les vols validés non clôturés dont la fin date de
  plus de 24 h. Elle notifie leur équipage, puis note `lastReminderAt` sur le
  vol. Le rappel suivant part 48 h après le précédent.
- **App.** Un `PushService` (paquet `firebase_messaging`) demande la
  permission, enregistre le jeton dans `users/{uid}.fcmToken` (seule écriture
  client autorisée par les règles), le met à jour à chaque renouvellement et
  l'efface à la déconnexion. Une notification reçue pendant que l'app est
  ouverte s'affiche dans une SnackBar.

**Tech Stack :**
- **Functions** :
  - Node 22 ;
  - `firebase-functions` 7 et `firebase-admin` 14 (Messaging) ;
  - `firebase-functions/v2/scheduler`.
- **App** : `firebase_messaging` (Android et web). Sur le web, un service
  worker est ajouté : `web/firebase-messaging-sw.js`.

**Spec :** `docs/superpowers/specs/2026-09-25-ulmgap-app-design.md`, §6
(notifications et rappels), §2.1 (`fcmToken`), §2.5 (`reminderGen`), §7.2
(règles), CLAUDE.md (échéance Node 20).

**Branche :** `feature/notifications`, créée depuis `feature/finances`.

## Décisions de l'utilisateur (2026-10-01)

1. **Plateformes : Android et web.** iOS sera traité plus tard par un
   développeur dédié, qui gérera les clés APNs. Rien n'est fait pour iOS ici,
   et le code ne doit pas le bloquer.
2. **Rappel de clôture** : 24 h après la fin du vol, puis **toutes les 48 h**
   (la spec disait 24 h), tant que le vol n'est pas clôturé.
3. **Node 22 en premier** (Task 1).

## Décisions du contrôleur (à relire)

- **Tâche planifiée plutôt que Cloud Tasks (KISS).** La spec §6.2 prévoit
  une tâche Cloud Tasks par vol, avec `reminderGen` pour neutraliser les
  tâches périmées. Une tâche horaire unique fait le même travail sans file à
  configurer ni reprogrammation quand l'heure de fin change. Le rappel part
  au plus une heure après l'échéance.
  - `reminderGen` n'est plus utilisé : il reste écrit à 0 par `createFlight`
    (champ inoffensif).
  - Le nouveau champ `flights.lastReminderAt` (timestamp) le remplace.
- **Requête de la tâche** : `status == 'valide'` et `isClosed == false`,
  deux égalités, donc sans index composite. Le reste est filtré en mémoire :
  vols non supprimés dont la fin est passée de plus de 24 h.
- **Destinataires** : jamais l'auteur de l'action (on ne se notifie pas
  soi-même), ni un compte inactif ou sans jeton.
  - Pour un **mouvement de crédit**, on notifie l'intéressé et tous les
    instructeurs actifs, l'auteur excepté. Un mouvement de crédit est un
    crédit, une correction ou une régularisation : la régularisation est
    la ligne écrite quand un admin corrige ou supprime un vol clôturé.
  - Le débit d'une clôture (`flight`) n'est pas un mouvement de crédit au
    sens de la spec : pas de notification.
- **Annulation** :
  - par `cancelFlight`, d'un vol `valide` : on notifie l'équipage et
    l'instructeur désigné. Une demande annulée ne notifie personne ;
  - par `adminDeleteFlight`, d'un vol `valide` non clôturé : même
    notification que `cancelFlight`.
- **Texte des messages** : en français, avec date et heure **à l'heure du
  club** (`Africa/Libreville`), par exemple « lundi 12 octobre, 09:00–10:00,
  F-JABC → Lomé ». Pas de lien direct vers le vol : un appui ouvre l'app.
  Le lien direct est une option pour plus tard.
- **Jetons périmés** : si FCM renvoie `messaging/registration-token-not-registered`
  ou `messaging/invalid-registration-token`, le jeton est effacé
  (`fcmToken: null`).
- **Un jeton par compte** : le dernier appareil connecté reçoit les
  notifications. Plusieurs appareils par compte restent une option pour plus
  tard.
- **Web** :
  - `getToken` exige une **clé VAPID**, que l'utilisateur crée dans la
    console : Paramètres du projet → Cloud Messaging → Certificats Web Push,
    une par projet. Elle se range dans `lib/core/env.dart`. Si elle est
    vide, l'app web ne s'inscrit pas aux notifications, sans erreur.
  - Le service worker choisit la configuration dev ou prod selon le nom
    d'hôte (`ulmgap-prod` dans l'URL → prod, sinon dev).

## Global Constraints

- `fvm flutter` / `fvm dart` ; TDD ; textes en français.
- Déploiement **dev** seulement.
- Toute écriture métier passe par les Functions. Seule exception : le client
  écrit `users/{uid}.fcmToken`, déjà permis par `firestore.rules`.
- Aucun index composite.
- L'émulateur n'a pas FCM : en test, l'envoi passe par une doublure
  (`setPushSenderForTests`).
- Vérification : `fvm flutter test && fvm flutter analyze`, `cd functions &&
  npm test`, puis les tests d'intégration (JDK d'Android Studio).

## Review Focus

1. **Échec d'envoi FCM** (réseau, jeton invalide) : l'action réussit quand
   même, l'erreur est journalisée, et un jeton invalide est effacé (Task 3).
2. **Auteur de l'action** : il ne reçoit jamais sa propre notification, même
   quand il est aussi destinataire (instructeur qui valide un vol où il vole,
   instructeur qui crédite son propre compte) (Task 2).
3. **Rappels** :
   - pas de rappel avant 24 h ;
   - pas de second rappel avant 48 h ;
   - aucun rappel pour un vol clôturé, supprimé ou non validé ;
   - deux passages successifs de la tâche n'envoient pas deux fois (Task 6).
4. **Déconnexion** : le jeton du compte est effacé, et l'appareil ne reçoit
   plus les notifications de ce compte (Task 7).
5. **Web sans clé VAPID ou permission refusée** : l'app fonctionne
   normalement, sans plantage ni boucle de demandes (Task 7).

---

### Task 1 : Node 22, firebase-functions 7, firebase-admin 14

**Files:** `functions/package.json`, `functions/package-lock.json`, et le
code éventuellement touché par les changements incompatibles.

- [ ] Vérifier la branche : `git checkout feature/notifications` (créée avec le plan).
- [ ] Dans `functions/package.json` :
  - `"engines": { "node": "22" }` ;
  - `"firebase-functions": "^7.4.0"` ;
  - `"firebase-admin": "^14.5.0"` ;
  - `"@types/node": "^22.0.0"` ;
  - puis `npm install`.
- [ ] `npm run build` : corriger les erreurs de compilation éventuelles. Le
  code n'utilise que l'API v2 (`onCall`, `HttpsError`), qui reste en v7.
- [ ] `npm test`, puis les tests d'intégration : tous doivent passer. Le
  Node local est en 20 : l'émulateur peut avertir d'un écart de version,
  c'est accepté.
- [ ] Déployer en dev (`npx firebase deploy --only functions --project dev`).
  Vérifier avec `npx firebase functions:list --project dev` que le runtime
  affiché est `nodejs22`.
- [ ] Commit `chore(functions): Node 22, firebase-functions 7, firebase-admin 14`.

### Task 2 : module pur des notifications

**Files:** `functions/src/rules/notifications.ts`, test
`functions/src/rules/notifications.test.ts`.

**Produces :**

```ts
export interface FlightInfo {
  start: number; end: number; aircraft: string; destination: string;
  crew: string[]; passengers: string[]; createdBy: string; instructorUid: string | null;
}
export interface PushMessage { title: string; body: string }
export interface Push { to: string[]; message: PushMessage }

/** « lundi 12 octobre, 09:00–10:00 » à l'heure du club. */
export function clubWhen(start: number, end: number): string;
/** « DPS/LDX, lundi 12 octobre, 09:00–10:00, F-JABC → Lomé » */
export function flightLine(f: FlightInfo, names: Record<string, string>): string;

export function requestPush(f: FlightInfo, names: Record<string, string>, actor: string, modified: boolean): Push | null;
export function validatedPush(f: FlightInfo, names: Record<string, string>, actor: string, modified: boolean): Push;
export function refusedPush(f: FlightInfo, names: Record<string, string>, actor: string, reason: string | null): Push;
export function cancelledPush(f: FlightInfo, names: Record<string, string>, actor: string): Push;
export function reminderPush(f: FlightInfo, names: Record<string, string>): Push;
export function movementPush(a: {
  userUid: string; shortName: string; amount: number; balanceAfter: number;
  type: "credit" | "correction" | "flight_adjustment"; actor: string; instructors: string[];
}): Push;

/** Rappel dû (décision 2) : fin + 24 h passée, et 48 h depuis le précédent. */
export function reminderDue(end: number, lastReminderAt: number | null, now: number): boolean;
```

Le champ `to` est dédoublonné et ne contient jamais `actor`.

**Textes :**

| Événement | Destinataires | Titre | Corps |
|---|---|---|---|
| Nouvelle demande | `instructorUid` | « Nouvelle demande de vol » | `flightLine` |
| Demande modifiée | `instructorUid` | « Demande de vol modifiée » | `flightLine` |
| Validée | `createdBy` et `crew` | « Vol validé » (« Vol validé avec modifications » si changé) | `flightLine` |
| Refusée | `createdBy` | « Demande refusée » | `flightLine` + « . Motif : … » si motif |
| Annulée (vol validé) | `crew` et `instructorUid` | « Vol annulé » | `flightLine` |
| Rappel | `crew` | « Vol à clôturer » | `flightLine` + « . Pensez à le clôturer dans le carnet de vol. » |
| Mouvement | `userUid` et `instructors` | « Compte de LDX » | « Crédit : +50 000 FCFA. Nouveau solde : 120 000 FCFA. » (« Correction », « Régularisation ») |

Montants au format `formatFcfa` (déjà dans `rules/pricing.ts`), avec un
« + » pour un montant positif.

- [ ] Tests qui échouent :
  - un cas par ligne du tableau ;
  - `actor` exclu même s'il est dans `crew`, et doublons supprimés
    (créateur aussi membre de l'équipage) ;
  - `requestPush` renvoie `null` sans `instructorUid` ;
  - `clubWhen` à l'heure de Libreville, par exemple 08:00 UTC → « 09:00 » ;
  - `reminderDue` :
    - fin il y a 23 h 59 → non ;
    - fin il y a 24 h, aucun rappel → oui ;
    - dernier rappel il y a 47 h → non ;
    - dernier rappel il y a 48 h → oui.
- [ ] Implémentation, `npm test` : PASS, puis commit
  `feat(functions): notification recipients and texts`.

### Task 3 : envoi FCM, doublure de test, jetons périmés

**Files:** `functions/src/notify/push.ts`, test
`functions/src/notify/push.int.test.ts`.

**Produces :**

```ts
export type Sender = (tokens: string[], m: PushMessage) =>
  Promise<{ failedTokens: string[]; invalidTokens: string[] }>;
export function setPushSenderForTests(s: Sender | null): void;
/** Lit les jetons des comptes actifs de `push.to`, envoie, efface les jetons invalides. Ne lève jamais. */
export async function sendPush(db: Firestore, push: Push | null): Promise<void>;
```

L'envoi par défaut appelle `admin.messaging().sendEachForMulticast`, avec
`notification: { title, body }` et `webpush.fcmOptions.link: "/"`.

- [ ] Tests d'intégration qui échouent (émulateur Firestore, doublure
  d'envoi) :
  - seuls les jetons des comptes actifs destinataires sont envoyés ;
  - un compte sans jeton est ignoré ;
  - un jeton invalide passe à `fcmToken: null` ;
  - une doublure qui lève une exception : `sendPush` se termine sans lever ;
  - `push` à `null` ou `to` vide : rien n'est envoyé.
- [ ] Implémentation, tests : PASS, puis commit
  `feat(functions): FCM sender with stale token cleanup`.

### Task 4 : notifications des actions sur les vols

**Files:**
- `functions/src/flights/edit.ts` (`createFlight`, `updateFlight`) ;
- `functions/src/flights/actions.ts` (`validateFlight`, `refuseFlight`,
  `cancelFlight`) ;
- `functions/src/flights/admin-edit.ts` (`adminDeleteFlight`) ;
- un petit module `functions/src/notify/flight-info.ts`, qui lit le vol et
  les `shortName` de l'annuaire (`profiles`) après la transaction ;
- tests : `functions/src/notify/flights.int.test.ts`.

- [ ] Tests d'intégration qui échouent (doublure d'envoi qui enregistre les
  envois), un par cas :
  - un élève crée une demande avec un instructeur : l'instructeur reçoit
    « Nouvelle demande de vol » ;
  - le créateur modifie sa demande : « Demande de vol modifiée » ;
  - un vol validé directement (lâché seul) : aucune notification ;
  - l'instructeur valide : le créateur reçoit « Vol validé », pas
    l'instructeur ;
  - l'instructeur valide en changeant l'heure : « Vol validé avec
    modifications » ;
  - l'instructeur refuse avec un motif : le créateur reçoit le motif ;
  - annulation d'un vol validé par le créateur : l'équipage et
    l'instructeur désigné le reçoivent, pas le créateur ;
  - annulation d'une demande : aucune notification ;
  - suppression admin d'un vol validé non clôturé : « Vol annulé » ;
  - une doublure qui lève une exception : l'action réussit quand même.
- [ ] Implémentation : après chaque `await db.runTransaction(...)` réussi,
  `await sendPush(db, …Push(...))`. Les informations du vol sont lues à
  nouveau, hors transaction.
- [ ] Tests : PASS, puis commit
  `feat(functions): push notifications for flight actions`.

### Task 5 : notifications des mouvements de crédit

**Files:**
- `functions/src/finance/accounts.ts` (`creditAccount`, `correctAccount`) ;
- `functions/src/flights/admin-edit.ts` (régularisations de
  `adminUpdateFlight` et `adminDeleteFlight`) ;
- tests : `functions/src/notify/movements.int.test.ts`.

- [ ] Tests d'intégration qui échouent :
  - crédit de 50 000 par l'instructeur A sur LDX : LDX et l'instructeur B
    reçoivent « Compte de LDX », avec « Crédit : +50 000 FCFA. Nouveau
    solde : … » ; A ne reçoit rien ;
  - correction : « Correction : −10 000 FCFA » ;
  - un instructeur qui crédite son propre compte ne reçoit rien, les autres
    instructeurs oui ;
  - correction admin d'un vol clôturé avec régularisation : notification
    « Régularisation » à chaque compte touché ;
  - clôture d'un vol (débit `flight`) : aucune notification.
- [ ] Implémentation : la transaction rend les mouvements écrits
  (`uid`, `amount`, `balanceAfter`, `type`). Après la transaction, on lit
  les instructeurs actifs (`users` où `profile == 'instructeur'`) et on
  envoie `movementPush` pour chaque mouvement.
- [ ] Tests : PASS, puis commit
  `feat(functions): push notifications for account movements`.

### Task 6 : rappels de clôture planifiés

**Files:** `functions/src/notify/reminders.ts`
(`sendClosingReminders(db, now)` et l'export
`closingReminders = onSchedule({ schedule: "every 60 minutes", region: "europe-west1", timeZone: "Africa/Libreville" }, …)`),
`functions/src/index.ts`, test `functions/src/notify/reminders.int.test.ts`.

- [ ] Tests d'intégration qui échouent, en appelant
  `sendClosingReminders(db, now)` avec un `now` choisi :
  - vol validé terminé il y a 25 h, sans rappel : l'équipage est notifié et
    `lastReminderAt = now` ;
  - même vol, nouveau passage 1 h plus tard : aucun envoi ;
  - nouveau passage 48 h après : nouvel envoi ;
  - vol terminé il y a 23 h : rien ;
  - vol clôturé, supprimé, en `demande` ou `refuse` : rien ;
  - une doublure qui lève une exception : la tâche continue avec les autres
    vols, et `lastReminderAt` est quand même écrit, pour ne pas relancer en
    boucle.
- [ ] Implémentation :
  - lecture de la requête à deux égalités et filtrage par
    `reminderDue` ;
  - pour chaque vol dû : `sendPush(reminderPush)`, puis
    `update({ lastReminderAt, updatedAt })`.
- [ ] Tests : PASS, puis commit `feat(functions): scheduled closing reminders`.

### Task 7 : app, inscription aux notifications

**Files:**
- `pubspec.yaml` (`firebase_messaging`) ;
- `lib/data/push_service.dart` (interface `PushService`, avec
  `Future<String?> token()`, `Stream<String> onTokenRefresh`,
  `Stream<({String title, String body})> onForegroundMessage` et
  `Future<void> deleteToken()`, plus l'implémentation Firebase) ;
- `lib/data/user_repository.dart` (`Future<void> saveFcmToken(String uid, String? token)`) ;
- `lib/data/services.dart` (`push` facultatif) ;
- `lib/main.dart` ;
- `lib/core/env.dart` (`webVapidKeyFor(AppEnv)`, vide par défaut) ;
- `lib/features/auth/gate.dart` : à l'état `ready`, inscription une fois
  par uid ; abonnement aux renouvellements ; SnackBar pour les messages
  reçus app ouverte, via un `ScaffoldMessengerKey` dans `app.dart` ;
- `lib/features/account/account_screen.dart` : à la déconnexion,
  `saveFcmToken(uid, null)` et `deleteToken()` **avant** `signOut` ;
- `web/firebase-messaging-sw.js` ;
- tests : `test/features/auth/push_registration_test.dart` et les doublures
  `FakePushService` et `FakeUserRepository.savedTokens` dans
  `test/support/fakes.dart`.

- [ ] Tests qui échouent (doublures) :
  - compte prêt : le jeton est enregistré une fois, et un rafraîchissement
    du flux de l'utilisateur ne réenregistre pas ;
  - nouveau jeton (renouvellement) : il est enregistré ;
  - `token()` renvoie `null` (permission refusée ou web sans clé VAPID) :
    rien n'est écrit, aucune erreur ;
  - `token()` lève une exception : rien n'est écrit, l'accueil s'affiche
    normalement ;
  - message reçu app ouverte : SnackBar « titre : corps » ;
  - déconnexion depuis « Mon compte » : `saveFcmToken(uid, null)` et
    `deleteToken()` avant `signOut` ;
  - `services.push` à `null` (tests existants) : aucun changement.
- [ ] Implémentation, `fvm flutter test && fvm flutter analyze`, puis commit
  `feat(app): push notification registration (Android, web)`.
- [ ] Android : vérifier que `android/app/src/main/AndroidManifest.xml`
  déclare `android.permission.POST_NOTIFICATIONS`, et l'ajouter sinon.

### Task 8 : docs et déploiement dev

- [ ] Spec :
  - §6.1 : plateformes Android et web, iOS plus tard ;
  - §6.2 : réécrite, avec la tâche planifiée, `lastReminderAt` et le
    rythme 24 h puis 48 h ;
  - §2.5 : `lastReminderAt` ajouté, `reminderGen` marqué inutilisé.
- [ ] CLAUDE.md :
  - plan 5 terminé, Node 22 ;
  - **action utilisateur** : créer la clé VAPID web dans la console (dev,
    puis prod), et me la donner pour `env.dart` ;
  - prod : déployer toutes les Functions, y compris `closingReminders`.
- [ ] Déploiement dev : `npx firebase deploy --only functions --project dev`.
- [ ] Commit `docs: plan 5 in spec and CLAUDE.md`.

## Recette en dev (par l'utilisateur)

- Android dev :
  - accepter les notifications ;
  - créer une demande avec un compte élève : l'instructeur la reçoit ;
  - la valider : l'élève reçoit « Vol validé ».
- Web (une fois la clé VAPID dans `env.dart`) : mêmes vérifications dans
  Chrome.
- Créditer un compte : l'intéressé et les autres instructeurs reçoivent la
  notification.
- Rappel : laisser un vol passé non clôturé. Le rappel arrive dans l'heure
  qui suit les 24 h après la fin du vol.
