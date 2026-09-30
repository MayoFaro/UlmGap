# UlmGap : application de gestion des vols ULM

> Spec rédigée dans le repo AppGAP, à déplacer dans le repo `ulmgap` à sa
> création. Elle complète `2026-09-24-ulm-bridge-design.md` (le pont
> ULM → AppGAP), dont elle respecte le contrat `flights`.

## Contexte / problème

Un vecteur ULM est exploité par des pilotes du GAP (ATR, hélico) et par des
personnels **externes au GAP**. Ces externes ne doivent **jamais** accéder à
AppGAP (règles de sécurité interne). La gestion des vols ULM se fait donc dans
une **application séparée**, UlmGap, avec son propre repo et ses propres projets
Firebase. AppGAP récupère les vols validés via le pont déjà livré.

## Objectif

Permettre aux pilotes (instructeurs, lâchés, élèves) et à leurs passagers de
**planifier**, **faire valider**, **réaliser** et **clôturer** des vols ULM,
avec :
- une matrice de droits selon le profil ;
- un blocage des doubles réservations d'appareil ou d'équipage ;
- un **crédit en FCFA** par compte, qui conditionne la validation et est débité
  à la clôture ;
- des compteurs d'heures **par pilote** et **par appareil** ;
- un relevé admin de tout ce qui a été facturé.

## Décisions structurantes

| Sujet | Décision |
|---|---|
| Repo | Dédié (`ulmgap`), projet Flutter neuf, Flutter 3.32.8 via fvm. Rien n'est forké d'AppGAP : on reprend à la main thème, formats de date et écran de connexion |
| Plateformes | Android, iOS et web, à partir du même code |
| Firebase | Deux projets, `ulmgap-dev` et `ulmgap-prod`. Dev par défaut |
| Écritures métier | **Toutes via des Cloud Functions** (callables). Les clients n'écrivent jamais `flights`, `users`, `transactions`, `aircraft` ni `settings` |
| Stockage client | Cache hors ligne natif de Firestore. Pas de Drift |
| Comptes | Créés par un admin, sans inscription libre. E-mail vérifié obligatoire |
| Appareils | Collection `aircraft`, nombre illimité |
| Principe | KISS : l'option la plus simple qui satisfait le besoin |

## Hors périmètre

- Planning, astreintes et tout autre module d'AppGAP.
- Paiement en ligne. Les crédits sont saisis par les instructeurs et les
  admins ; les montants « hors app » sont réglés en dehors.
- Suivi d'entretien des appareils (le compteur par appareil fournit les heures).
- Toute remontée d'information d'AppGAP vers UlmGap.
- *Flavors* Android/iOS distincts dev/prod : à ajouter seulement si l'on veut
  installer les deux versions sur le même téléphone.

---

## 1. Profils, rôles et badges

**Profil pilote** (`users.profile`) :

| Code | Libellé provisoire | Badge |
|---|---|---|
| `instructeur` | Instructeur | Violet, icône diplôme |
| `lache_toute_mission` | Lâché toute mission | Vert, icône deux ailes |
| `lache_solo` | Lâché solo | Bleu, icône une aile |
| `eleve` | Élève | Orange, icône casquette d'étudiant |
| `null` | Non pilote (gestionnaire) | Aucun |

Libellés, couleurs et icônes sont définis dans **un seul fichier** de l'app
(`lib/core/profiles.dart`). Les renommer ne touche pas aux données. Le badge
s'affiche à côté du nom partout où une personne apparaît : planning, détail
d'un vol, sélection d'équipage, liste des comptes, « Mon compte ».

**Appartenance** (`users.category`) : `GAP` / `GR` / `MIL` / `EXT`. Elle
détermine le forfait et le taux de dépassement (§4).

**Admin** (`users.isAdmin`) : un drapeau indépendant du profil. Un admin gère
les comptes, les profils, les catégories, les appareils et les tarifs. Il peut
corriger ou supprimer n'importe quel vol. Un admin ou un instructeur peut créer
un vol dont il ne fait pas partie (révision du 2026-09-28). Le premier admin de chaque projet est créé à la
main dans la console Firebase.

## 2. Modèle de données (Firestore, identique en dev et en prod)

### 2.1 `users/{uid}`, écrit par les Functions (sauf `fcmToken`)

| Champ | Type | Contenu |
|---|---|---|
| `displayName` | string | Nom complet |
| `shortName` | string | Code court affiché (trigramme ou équivalent) |
| `email` | string | Copie de l'e-mail Firebase Auth |
| `profile` | string? | Voir §1 |
| `category` | string | Appartenance : `GAP` / `GR` / `MIL` / `EXT` |
| `isAdmin` | bool | |
| `active` | bool | Faux : plus de connexion, ne peut plus être ajouté à un nouveau vol |
| `balance` | int | Solde en FCFA (peut être négatif) |
| `fcmToken` | string? | Seul champ modifiable par l'utilisateur lui-même |

### 2.2 `profiles/{uid}`, annuaire public en lecture

`displayName`, `shortName`, `profile`, `active`, tenus à jour par les Functions
en même temps que `users`. Il permet d'afficher équipages et badges sans
exposer à tous les soldes, e-mails ou catégories.

### 2.3 `aircraft/{id}`, géré par un admin

`registration` (immatriculation), `label` (« ULM 1 »…), `active`.

### 2.4 `settings/pricing`, modifiable par un admin

| Champ | Défaut | Rôle |
|---|---|---|
| `flatFee` | `{GAP: 12000, GR: 30000, MIL: 50000, EXT: 70000}` | Forfait par appartenance, couvrant jusqu'à `includedMinutes` |
| `includedMinutes` | 75 | Durée couverte par le forfait |
| `minPlannedMinutes` | 45 | Durée minimale d'un vol **prévu** |
| `overtimeHourly` | `{GAP: 12000, GR: 30000, MIL: 30000, EXT: 30000}` | Taux horaire du dépassement, par appartenance |
| `fuelHourlyRate` | 12 000 FCFA/h | Mode « carburant seulement » |

### 2.5 `flights/{id}`, écrit uniquement par les Functions

Les champs marqués **(contrat)** sont lus par le pont AppGAP : ni leur nom ni
leur sens ne doivent changer sans mettre à jour le pont.

| Champ | Type | Contenu |
|---|---|---|
| `start` **(contrat)** | timestamp | Heure de départ prévue |
| `end` **(contrat)** | timestamp | Heure de fin prévue, obligatoire, défaut `start` + 1 h, confirmée à la validation |
| `destination` **(contrat)** | string | Obligatoire, texte libre |
| `aircraftId` | string | Référence `aircraft` |
| `aircraft` **(contrat)** | string | Immatriculation recopiée |
| `crew` **(contrat)** | array<uid> | Membres d'équipage **avec compte**, dans l'ordre saisi |
| `passengers` **(contrat)** | array<string> | Noms des passagers **sans compte** |
| `instructorUid` | uid? | L'instructeur à qui revient la validation d'une demande |
| `status` **(contrat)** | string | `demande` / `valide` / `refuse` |
| `refusalReason` | string? | Motif de refus |
| `createdBy` | uid | |
| `pricingMode` | string | `standard` / `fuel_only` / `custom` |
| `customAmount` | int? | Montant « facturé hors app » saisi à la clôture (mode `custom`) |
| `shortFlightAmount` | int? | Montant saisi à la clôture d'un vol réel de moins de `minPlannedMinutes` (§4.3) |
| `payerUid` | uid | Premier inscrit dans `crew` (§4.2). Son solde n’est pas débité si le vol finit en `custom` |
| `pricingSnapshot` | map | Tarifs figés au moment du passage en `valide` |
| `isClosed` **(contrat)** | bool | |
| `actualFlightMinutes` **(contrat)** | int? | Saisi à la clôture |
| `closedBy`, `closedAt` | uid, timestamp | |
| `billedAmount` | int? | Montant final, fixé à la clôture |
| `billedTo` | string? | `account` (débité sur un solde) / `off_app` (facturé hors app) |
| `reminderGen` | int | Génération du rappel de clôture (§6) |
| `deleted` **(contrat)** | bool | **Suppression logique uniquement**, jamais de suppression physique |
| `updatedAt` **(contrat)** | timestamp serveur | Mis à jour à **chaque** écriture |

**Composition** : **2 personnes à bord au maximum** (`crew` + `passengers`),
dont au moins un membre avec compte. Deux instructeurs peuvent voler ensemble.

### 2.6 `transactions/{id}`, historique non modifiable

| Champ | Contenu |
|---|---|
| `userUid` | Compte concerné |
| `amount` | int, positif pour un crédit, négatif pour un débit |
| `type` | `credit` / `correction` / `flight` / `flight_adjustment` |
| `reason` | Texte, **obligatoire** pour un montant négatif saisi à la main |
| `flightId` | Pour `flight` / `flight_adjustment` |
| `by` | uid de l'auteur, ou `system` |
| `at` | timestamp serveur |
| `balanceAfter` | Solde après le mouvement |

Règle absolue : **le solde n'est jamais modifié sans sa ligne d'historique**,
écrite dans la même transaction Firestore.

## 3. Droits et cycle de vie d'un vol

### 3.1 Définitions

- **Vol seul** : 1 personne à bord.
- **Vol à deux** : 2 personnes à bord.
- Un vol est **effectué** dès que son heure de départ est passée.

### 3.2 Création (`createFlight`)

Hors admin et instructeur, **le créateur doit figurer dans `crew`**. Statut obtenu :

| Créateur | Seul | À deux, sans instructeur | Avec un instructeur autre que lui |
|---|---|---|---|
| Élève | ✗ refusé | ✗ refusé | `demande` |
| Lâché solo | `valide` | ✗ refusé | `demande` |
| Lâché toute mission | `valide` | `valide` | `demande` |
| Instructeur (dans l'équipage ou non) | `valide` | `valide` | `valide` (deux instructeurs) |
| Admin (dans l'équipage ou non) | `valide` | `valide` | `valide` |
| Non pilote, non admin | ✗ refusé | ✗ refusé | ✗ refusé |

Dans un vol à deux sans instructeur, l'équipier peut être **n'importe quel
utilisateur**, élève compris (comme passager), ou un **passager sans compte**.

En `demande`, `instructorUid` = l'instructeur de l'équipage.

### 3.3 Actions

| Action | Qui | Effet |
|---|---|---|
| `validateFlight` (modifications facultatives : horaire, destination, appareil, mode de tarification) | L'instructeur désigné, ou un admin | `demande` → `valide` |
| `refuseFlight` (motif facultatif) | L'instructeur désigné, ou un admin | `demande` → `refuse` |
| `updateFlight` | Le créateur, avant le départ | Mêmes règles qu'à la création. Si un non-instructeur modifie un vol avec instructeur, il redevient `demande`. Un vol `refuse` modifié repart en `demande` |
| `cancelFlight` | Le créateur, l'instructeur désigné ou un admin, avant le départ | `deleted: true` |
| `closeFlight` (minutes réelles) | Tout membre de `crew` ou un admin, une fois le vol effectué | Clôture et fige le vol, puis facturation (§4). **Le premier qui clôture l'emporte** : une seconde clôture est refusée |
| `adminUpdateFlight` | Admin, à tout moment, vols clôturés compris | Modification libre, sans matrice mais avec conflits. Sur un vol clôturé, régularisation automatique (§4.5) |

### 3.4 Contrôles communs

Pour toute action qui crée ou modifie un vol :
- durée prévue (`end` − `start`) ≥ `minPlannedMinutes` (45 min) ;
- appareil `active` ;
- membres de `crew` `active` ;
- composition (§2.5) ;
- `destination` non vide.

### 3.5 Conflits (bloquants pour les vols `valide`)

Quand un vol **devient ou reste `valide`** (création directe, validation,
modification, correction admin), la Function vérifie **dans une transaction**
qu'aucun autre vol `valide`, non supprimé, ne chevauche `[start, end[` :
- sur le **même appareil** ;
- ou avec **une même personne** de `crew`.

S'il y a conflit, l'action est refusée, avec un message qui cite le vol en
conflit (date, horaire, appareil, équipage). Les **demandes** ne bloquent rien
et peuvent se chevaucher : l'instructeur arbitre à la validation. Les bornes
sont ouvertes : une fin égale à un début n'est pas un conflit.

## 4. Finances

> Révision du 2026-09-25 : le modèle « taux horaire + malus + forfait
> instruction » est remplacé par un **forfait par appartenance** avec
> dépassement au prorata. Il n'y a plus de forfait instruction : voler avec ou
> sans instructeur coûte le même prix.

### 4.1 Modes de tarification

| Mode | Condition | Choix |
|---|---|---|
| `standard` | Tous les vols | Par défaut, sauf le cas ci-dessous |
| `fuel_only` | **Tous les membres de `crew` sont d'appartenance `GAP`** (un passager sans compte ne l'empêche pas) | **Par défaut** si l'équipage GAP emmène un passager sans compte. Pour un vol entre GAP sans passager : au choix d'un instructeur (créateur ou validateur) ou d'un admin ; ce choix est conservé quand un non-instructeur modifie le vol, sauf si c'est un passager qui l'imposait |
| `custom` (facturé hors app) | **Tout vol avec un passager sans compte**, quelle que soit l'appartenance du pilote | **Décidé à la clôture** : « montant différent », avec la saisie du montant |

La Function vérifie ces conditions à chaque écriture. Si l'équipage change et
que la condition n'est plus remplie, le vol repasse en `standard`.

### 4.2 Payeur

Règle unique, valable pour tous les vols : **le premier inscrit dans `crew`
paie** (« compte débité »). DPS/LDX : DPS paie. LDX/DPS : LDX paie. L'app place
le créateur en premier. Révision du 2026-09-28 : hors instructeurs et admins,
le créateur est obligatoirement le premier (le serveur le vérifie) ; seuls les
instructeurs et les admins peuvent changer l'ordre. Le formulaire affiche en
clair « Compte débité : XXX ». Un passager sans compte ne paie jamais sur un solde.

### 4.3 Coût

Notations : `d` = durée en minutes, `A` = appartenance du payeur, et les
tarifs de `pricingSnapshot`.

| Mode | Coût | Imputation |
|---|---|---|
| `standard`, `d` ≥ 45 | `flatFee[A]` + `overtimeHourly[A]` × max(0, `d` − 75) / 60 | Solde du payeur (`billedTo: account`) |
| `standard`, vol **réel** de moins de 45 min | `shortFlightAmount`, **saisi à la clôture** | Solde du payeur |
| `fuel_only` | `fuelHourlyRate` × `d` / 60 | Solde du payeur |
| `custom` | `customAmount` | Hors app (`billedTo: off_app`) |

- Le résultat est arrondi au franc le plus proche.
- Un vol ne peut pas être **prévu** sous 45 min (§3.4). Le cas « moins de
  45 min » n'existe donc qu'à la clôture, quand le vol réel a été plus court :
  l'écran de clôture affiche alors un champ obligatoire **« Montant à
  facturer »**.
- Les tarifs utilisés sont ceux de `pricingSnapshot`, figés au passage en
  `valide`.

Exemples (`standard`) :

| Payeur | Durée | Coût |
|---|---|---|
| GAP | 60 min | 12 000 |
| GAP | 90 min | 12 000 + 15 min à 12 000/h = **15 000** |
| MIL | 75 min | **50 000** |
| EXT | 90 min | 70 000 + 15 min à 30 000/h = **77 500** |
| EXT, avec ou sans instructeur | 60 min | **70 000** (plus de forfait instruction) |

### 4.4 Crédit disponible et blocage

- **Crédit disponible** du payeur = `balance` − somme des coûts **estimés**
  (durée prévue) de ses autres vols `valide`, non clôturés, non supprimés,
  imputés sur son solde.
- À **chaque création, modification ou validation** d'un vol imputé sur un
  solde (`standard` ou `fuel_only`), **dès la demande** (révision du
  2026-09-29), si le crédit disponible est inférieur au coût estimé, l'action
  est **refusée**, avec le montant manquant affiché. L'admin est soumis à la
  même règle.
- Plafond de 200 000 FCFA pour les montants saisis à la clôture (« Montant à
  facturer », « Montant différent ») ; aucun plafond pour les crédits et
  corrections.
- À la **clôture** : coût réel calculé sur `actualFlightMinutes` (ou
  `shortFlightAmount` sous 45 min), puis débit (transaction `flight`) ; le
  solde peut devenir négatif. En `custom`, `billedAmount` est enregistré sans
  mouvement de solde.

### 4.5 Crédits, corrections, régularisations

| Action | Qui | Règle |
|---|---|---|
| `creditAccount` (montant > 0, motif facultatif) | Instructeurs et admins | Transaction `credit` |
| `correctAccount` (montant ±, motif obligatoire) | Instructeurs et admins | Transaction `correction` |
| Régularisation | Automatique, sur `adminUpdateFlight` d'un vol clôturé | Vol imputé sur un solde : transaction `flight_adjustment` pour la différence entre l'ancien et le nouveau coût. Hors app : mise à jour de `billedAmount` |

### 4.6 Visibilité

- Chacun voit son solde et son historique.
- Les instructeurs et les admins voient tous les soldes et tous les historiques.

## 5. Écrans

Identiques sur mobile et sur web.

**Accès**
- **Connexion** : e-mail et mot de passe, « mot de passe oublié ».
- **Première connexion** : lien de définition du mot de passe, puis
  vérification de l'e-mail. L'app reste bloquée sur un écran d'attente tant
  que l'e-mail n'est pas vérifié.

**Planning (accueil)**
- Vols à venir groupés par jour, avec un filtre par appareil.
- Statut en couleur : demande en orange, validé en vert, refusé en gris.
- Rubriques **« À valider »** (instructeur désigné) et **« Mes demandes »**.
- Bouton « + ».

**Formulaire de vol (création, modification, validation)**
- Date, départ, fin (+1 h par défaut, confirmée à l'enregistrement), appareil
  (actifs uniquement).
- Équipage : soi-même en premier, puis un utilisateur ou un passager sans
  compte ; ordre modifiable.
- Destination : texte libre, avec des suggestions tirées des destinations déjà
  utilisées.
- Pour un instructeur ou un admin, sur un vol entre GAP sans passager : le
  choix « carburant seulement » (§4.1). Le mode par défaut s'affiche dans
  l'aperçu.
- **Aperçu en direct** : statut obtenu (« sera créé » / « sera une demande à
  DPS »), **payeur**, coût estimé, crédit disponible du payeur, conflits éventuels. Cet
  aperçu est **indicatif** : la décision finale revient à la Function.

**Détail d'un vol**
- Toutes les informations, et les actions permises selon le rôle : valider,
  refuser, modifier, annuler, clôturer (durée réelle), corriger (admin).
- **Clôture** : saisie de la durée réelle. Si elle est inférieure à 45 min,
  un champ obligatoire « Montant à facturer » apparaît. Pour tout vol avec un
  passager sans compte, une case « Montant différent (facturé hors app) »
  permet de saisir le montant : le vol passe alors en `custom` et aucun solde
  n'est débité.

**Compteurs**
- **Pilote** : une période, un total. Chacun voit le sien ; les instructeurs
  et les admins choisissent le pilote.
- **Appareil** : un appareil et une période, par exemple « total 154h45 »,
  visible par tous.
- Base de calcul : `actualFlightMinutes` des vols clôturés, non supprimés.

**Mon compte**
- Solde, historique, profil (badge), appartenance.

**Instructeurs**
- Liste des comptes avec leur solde, et un bouton « créditer / corriger ».

**Administration**
- Utilisateurs : création, profil, catégorie, admin, activation.
- Appareils, tarifs.
- **Relevé des vols facturés** : sur une période, chaque vol clôturé avec son
  mode, son montant facturé, son payeur ou « hors app », son appareil et son
  équipage ; totaux « débité sur comptes » et « facturé hors app » ; export
  CSV sur le web.

## 6. Notifications et rappels

### 6.1 Notifications push

Via FCM, avec le jeton dans `users.fcmToken`. Elles sont envoyées par les
Functions **après** l'écriture réussie ; un échec d'envoi est journalisé et
n'annule jamais l'action.

| Événement | Destinataires |
|---|---|
| Nouvelle demande, ou demande modifiée | L'instructeur désigné |
| Demande validée (éventuellement modifiée) | Le créateur et l'équipage |
| Demande refusée (avec motif) | Le créateur |
| Vol validé annulé | L'équipage et l'instructeur désigné |
| Vol non clôturé 24 h après sa fin, puis toutes les 24 h | Les membres de `crew` |
| Mouvement de crédit (crédit, correction, régularisation) | L'intéressé et **tous les autres instructeurs** |

### 6.2 Rappel de clôture par tâche programmée

- Quand un vol **devient `valide`**, ou quand l'heure de fin d'un vol `valide`
  change, la Function incrémente `reminderGen` et programme, dans une file de
  tâches Firebase (`onTaskDispatched`), la tâche
  `checkFlightClosure(flightId, gen)` à `end` + 24 h.
- À l'exécution, la tâche **relit le vol** :
  - supprimé, clôturé ou non `valide` → fin ;
  - `gen` ≠ `reminderGen` (tâche caduque) → fin ;
  - sinon → notification aux membres de `crew`, puis nouvelle tâche à
    maintenant + 24 h, avec le même `gen`.
- Aucune annulation de tâche n'est nécessaire : les anciennes s'éteignent
  d'elles-mêmes.

## 7. Architecture technique

### 7.1 Environnements

- Deux projets : `ulmgap-dev` et `ulmgap-prod`.
- `flutterfire configure` génère `lib/firebase_options_dev.dart` et
  `lib/firebase_options_prod.dart`. Le choix se fait par
  `--dart-define=ENV=dev|prod`, **dev par défaut**.
- `.firebaserc` définit les alias `dev` (par défaut) et `prod`. Tout
  déploiement en prod est explicite : `firebase deploy --project prod`.
- Émulateurs Firebase (Auth, Firestore, Functions) pour les tests et le
  développement local.

### 7.2 Règles Firestore

Tout est refusé par défaut. « Connecté » signifie authentifié, e-mail vérifié
et `users/{uid}.active == true`.

| Collection | Lecture | Écriture client |
|---|---|---|
| `flights`, `aircraft`, `settings/pricing`, `profiles` | Connecté | ✗ |
| `users/{uid}` | Soi-même ; instructeurs et admins : tous | Uniquement `fcmToken` sur son propre document |
| `transactions` | Les siennes ; instructeurs et admins : toutes | ✗ |

### 7.3 Structure du repo `ulmgap`

- `lib/core/` : profils et badges, calcul de coût (miroir du serveur, pour
  l'aperçu), formats.
- `lib/data/` : lecture Firestore, appels des Functions.
- `lib/features/` : `planning`, `flight`, `counters`, `account`,
  `instructors`, `admin`.
- `functions/src/rules/` : **module pur** (matrice, payeur, coût, crédit
  disponible, conflits), sans accès à Firestore.
- `functions/src/flights/`, `credits/`, `admin/`, `reminders/` : les actions
  callables et la tâche.
- `test/fixtures/` : cas partagés (matrice de droits, coût), rejoués
  en Dart et en TypeScript.
- `README.md` : rappel du **contrat `flights`** lu par le pont AppGAP.

### 7.4 Tests

- **TypeScript, unitaires** sur le module `rules/` : chaque ligne de la
  matrice, le payeur (premier inscrit : DPS/LDX et LDX/DPS), le coût (les exemples du
  §4.3, le seuil de 75 min pile, le vol réel de moins de 45 min), les conditions
  des modes `fuel_only` (tous GAP, par défaut avec un passager sans compte) et `custom` (à la clôture), le crédit disponible et les conflits
  (bornes ouvertes, demandes non bloquantes).
- **TypeScript, intégration contre l'émulateur** : chaque action (statuts,
  transactions et soldes cohérents, historique écrit dans la même
  transaction, première clôture l'emporte, régularisation) et la tâche de
  rappel (gen caduque, relance).
- **Dart** : calcul de coût client (cas partagés), badges, formulaire de vol et
  compteurs (widgets).
- **Recette dans `ulmgap-dev`** avec un compte de test par profil et par
  appartenance.

## 8. Impact sur le pont AppGAP (chantier séparé)

1. `transformFlight` ne copie que les vols `status == 'valide'`. Sinon il
   renvoie `null`, ce qui passe une copie existante à `deleted: true` (cas
   d'un vol validé qui redevient une demande).
2. `externalCount` compte les membres de `crew` non-GAP **plus**
   `passengers.length`.
3. Mise à jour du §2.1 de `2026-09-24-ulm-bridge-design.md`.
4. Mise en service : `ULM_PROJECT_ID=ulmgap-prod`, rôles IAM
   `datastore.viewer` et `firebaseauth.viewer` accordés **sur `ulmgap-prod`
   uniquement**. Le pont ne lit jamais `ulmgap-dev`.

Limite assumée : ces rôles donnent techniquement au compte de service d'AppGAP
la lecture de toute la base UlmGap (soldes et historiques compris). Seules les
données du contrat sont recopiées.
