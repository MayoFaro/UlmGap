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
- un **carnet de vol** avec le temps de vol total par pilote (révision du
  2026-09-30 : plus de compteur par appareil) ;
- un relevé admin de tout ce qui a été facturé ;
- un **suivi carburant** par appareil (révision du 2026-10-02, §9) ;
- un **suivi de caisse** de l'association (révision du 2026-10-14, §11) ;
- des **vols techniques** non facturés (révision du 2026-10-14, §12) ;
- un **suivi de cuve** et le carburant « bidon perso » (révision du 2026-10-15, §13).

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
- Suivi d'entretien des appareils.
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

**Lâché amphibie** (`users.amphibiousCleared`, révision du 2026-10-06) : case
cochée par un admin, indépendante du profil. Elle conditionne les vols sur un
appareil amphibie (§3.6). La fenêtre de compte, la liste des utilisateurs et
« Mon compte » l'affichent (« amphibie »). Dans le menu « Profil » de la
fenêtre de compte, chaque choix montre l'icône de son badge.

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
| `amphibiousCleared` | bool | Lâché amphibie (§1, §3.6), faux par défaut |
| `balance` | int | Solde en FCFA (peut être négatif) |
| `fcmToken` | string? | Seul champ modifiable par l'utilisateur lui-même |

### 2.2 `profiles/{uid}`, annuaire public en lecture

`displayName`, `shortName`, `profile`, `active`, `amphibiousCleared`, tenus à jour par les Functions
en même temps que `users`. Il permet d'afficher équipages et badges sans
exposer à tous les soldes, e-mails ou catégories.

### 2.3 `aircraft/{id}`, géré par un admin

`registration` (immatriculation), `label` (« ULM 1 »…), `active`, `amphibious`
(révision du 2026-10-01 : amerrissages saisis à la clôture).

Carburant actuel (révision du 2026-10-02, §9), écrit seulement par
`closeFlight` et `adminUpdateFlight`, jamais par `adminUpsertAircraft` :
`fuelLiters` (int?, `null` : inconnu), `fuelFlightId` et `fuelFlightStart`
(le vol clôturé dont vient la valeur, et son départ).

### 2.4 `settings/pricing`, modifiable par un admin

| Champ | Défaut | Rôle |
|---|---|---|
| `flatFee` | `{GAP: 12000, GR: 30000, MIL: 50000, EXT: 70000}` | Forfait par appartenance, seul facturé jusqu'à `toleranceMinutes` |
| `includedMinutes` | 60 | « Temps couvert par le forfait » : au-delà de la tolérance, le dépassement se compte à partir de cette durée (révision du 2026-10-05) |
| `toleranceMinutes` | 75 | « Tolérance jusqu'à » : jusqu'à cette durée, le forfait seul (révision du 2026-10-05) |
| `minPlannedMinutes` | 45 | Durée minimale d'un vol **prévu** |
| `overtimeHourly` | `{GAP: 12000, GR: 30000, MIL: 30000, EXT: 30000}` | Taux horaire du dépassement, par appartenance |
| `fuelHourlyRate` | 12 000 FCFA/h | Mode « carburant seulement » |
| `instructionCredit` | 20 000 FCFA | Crédit de l'instructeur par vol d'instruction (§10) |
| `baptismFees` | `{local: 70000, nyonye: 90000, awagne: 110000}` | Forfaits de baptême de l'air, facturés hors app (§10.2) |

### 2.5 `flights/{id}`, écrit uniquement par les Functions

Les champs marqués **(contrat)** sont lus par le pont AppGAP : ni leur nom ni
leur sens ne doivent changer sans mettre à jour le pont.

| Champ | Type | Contenu |
|---|---|---|
| `start` **(contrat)** | timestamp | Heure de départ prévue |
| `end` **(contrat)** | timestamp | Heure de fin prévue, obligatoire, défaut `start` + 1 h, confirmée à la validation. À la clôture, allongée à `start` + `actualFlightMinutes` si elle est plus courte, jamais raccourcie (l'appareil a pu rester posé ailleurs) |
| `destination` **(contrat)** | string | Obligatoire, texte libre |
| `aircraftId` | string | Référence `aircraft` |
| `aircraft` **(contrat)** | string | Immatriculation recopiée |
| `crew` **(contrat)** | array<uid> | Membres d'équipage **avec compte**, dans l'ordre saisi |
| `passengers` **(contrat)** | array<string> | Noms des passagers **sans compte** |
| `instructorUid` | uid? | L'instructeur à qui revient la validation d'une demande |
| `status` **(contrat)** | string | `demande` / `valide` / `refuse` |
| `refusalReason` | string? | Motif de refus |
| `createdBy` | uid | |
| `pricingMode` | string | `standard` / `fuel_only` / `custom` / `baptism` (§10) |
| `instruction` | bool | Case « Vol d'instruction » (§10) |
| `instructionCreditUid`, `instructionCreditAmount` | uid?, int? | Crédit instruction versé à la clôture (§10) |
| `customAmount` | int? | Montant « facturé hors app » saisi à la clôture (mode `custom`) |
| `shortFlightAmount` | int? | Montant saisi à la clôture d'un vol réel de moins de `minPlannedMinutes` (§4.3) |
| `payerUid` | uid | Premier inscrit dans `crew` (§4.2). Son solde n’est pas débité si le vol finit en `custom` |
| `pricingSnapshot` | map | Tarifs figés au moment du passage en `valide` |
| `isClosed` **(contrat)** | bool | |
| `actualFlightMinutes` **(contrat)** | int? | Saisi à la clôture |
| `landings` | int? | Nombre d'atterrissages, saisi à la clôture (révision du 2026-10-01) |
| `waterLandings` | int? | Nombre d'amerrissages, saisi à la clôture d'un appareil `amphibious` ; 0 sinon |
| `fuelStartExpectedLiters` | int? | Carburant actuel de l'appareil affiché à la clôture (`null` : inconnu) (§9) |
| `fuelStartLiters` | int? | Carburant au départ : la valeur affichée, ou la valeur corrigée par l'équipage (§9) |
| `fuelAddedLiters` | int? | Carburant ajouté par l'équipage, avant ou après le vol (§9) |
| `fuelEndLiters` | int? | Carburant à bord une fois l'appareil rangé (§9) |
| `closedBy`, `closedAt` | uid, timestamp | |
| `billedAmount` | int? | Montant final, fixé à la clôture |
| `billedTo` | string? | `account` (débité sur un solde) / `off_app` (facturé hors app) |
| `reminderGen` | int | Inutilisé depuis le plan 5 (toujours 0) |
| `lastReminderAt` | timestamp? | Dernier rappel de clôture envoyé (§6.2) |
| `deleted` **(contrat)** | bool | **Suppression logique uniquement**, jamais de suppression physique |
| `updatedAt` **(contrat)** | timestamp serveur | Mis à jour à **chaque** écriture |

**Composition** : **2 personnes à bord au maximum** (`crew` + `passengers`),
dont au moins un membre avec compte. Deux instructeurs peuvent voler ensemble.

### 2.6 `transactions/{id}`, historique non modifiable

| Champ | Contenu |
|---|---|
| `userUid` | Compte concerné |
| `amount` | int, positif pour un crédit, négatif pour un débit |
| `type` | `credit` / `correction` / `flight` / `flight_adjustment` / `instruction` (§10) |
| `reason` | Texte, **obligatoire** pour un montant négatif saisi à la main |
| `flightId` | Pour `flight` / `flight_adjustment` / `instruction` |
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
- Un vol validé se **clôture dès le jour du vol** (date du jour ou avant, à l'heure du
  club, Africa/Libreville), même avant l'heure de départ (révision du 2026-09-30).

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
| `closeFlight` (minutes réelles, atterrissages, amerrissages, carburant §9) | Tout membre de `crew` ou un admin, dès le jour du vol (§3.1) | Clôture et fige le vol, puis facturation (§4). **Le premier qui clôture l'emporte** : une seconde clôture est refusée |
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
qu'aucun autre vol `valide`, non supprimé, n'est à **moins de 30 min** de
`[start, end[` (battement fixe, révision du 2026-10-05) : il y a conflit si
`start` < `fin de l'autre` + 30 min et `début de l'autre` < `end` + 30 min.
- sur le **même appareil** ;
- ou avec **une même personne** de `crew`.

S'il y a conflit, l'action est refusée, avec un message qui cite le vol en
conflit (date, horaire, appareil, équipage). Les **demandes** ne bloquent rien
et peuvent se chevaucher : l'instructeur arbitre à la validation. Les bornes
sont ouvertes : un écart d'exactement 30 min n'est pas un conflit (vol de 9 h
à 10 h : le suivant peut partir à 10 h 30, pas à 10 h 29). Le message ajoute
« (30 min d'écart minimum) ».

**Planification seulement, jamais la conduite** (révision du 2026-10-01) :
- le contrôle ne s'applique qu'à un vol **à venir** (départ pas encore
  atteint) et **non clôturé** ;
- un vol **clôturé** n'est jamais en conflit avec un autre : ses horaires
  sont ceux de la conduite (retards, fin allongée à la clôture) ;
- la clôture, la correction admin d'un vol passé ou clôturé, et la saisie
  après coup d'un vol passé par un admin ne sont donc jamais bloquées par
  un chevauchement.

### 3.6 Appareil amphibie (révision du 2026-10-06)

À la création, la modification et la validation d'un vol sur un appareil
`amphibious` (l'admin y échappe, comme pour la matrice §3.2) :
- **si l'équipage compte un instructeur**, au moins un instructeur doit être
  lâché amphibie, sinon refus : « Appareil amphibie : l'instructeur doit être
  lâché amphibie. » ;
- **sans instructeur**, au moins un membre de `crew` doit être lâché amphibie,
  sinon refus : « Appareil amphibie : il faut un pilote lâché amphibie à
  bord. »

Ce contrôle s'ajoute à la matrice (§3.2), qui reste inchangée. Exemples :
élève + instructeur lâché amphibie : accepté ; élève + instructeur non lâché
amphibie : refusé ; instructeur non lâché amphibie seul : refusé, avec un
instructeur lâché amphibie : accepté ; lâché non amphibie seul : refusé ;
lâché amphibie seul : accepté selon son profil. Les vols déjà créés ne sont
pas remis en cause si la case ou l'appareil change ensuite. L'aperçu du
formulaire affiche le refus avant l'enregistrement.

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
| `standard`, 45 ≤ `d` ≤ `toleranceMinutes` (75) | `flatFee[A]` | Solde du payeur (`billedTo: account`) |
| `standard`, `d` > `toleranceMinutes` (75) | `flatFee[A]` + `overtimeHourly[A]` × (`d` − `includedMinutes` (60)) / 60 | Solde du payeur |
| `standard`, vol **réel** de moins de 45 min | `shortFlightAmount`, **saisi à la clôture** | Solde du payeur |
| `fuel_only` | `fuelHourlyRate` × `d` / 60 | Solde du payeur |
| `custom` | `customAmount` | Hors app (`billedTo: off_app`) |
| `baptism` | `baptismFees[baptismTier]`, quelle que soit la durée (§10.2) | Hors app (`billedTo: off_app`) |

- Le résultat est arrondi au franc le plus proche.
- Un vol ne peut pas être **prévu** sous 45 min (§3.4). Le cas « moins de
  45 min » n'existe donc qu'à la clôture, quand le vol réel a été plus court :
  l'écran de clôture affiche alors un champ obligatoire **« Montant à
  facturer »**.
- Les tarifs utilisés sont ceux de `pricingSnapshot`, figés au passage en
  `valide`. Un snapshot antérieur à la révision du 2026-10-05 (sans
  `toleranceMinutes`, avec `includedMinutes` à 75) garde l'ancien calcul :
  la tolérance par défaut (75) égale alors le temps couvert.
- Révision du 2026-10-05 : au-delà de 75 min, tout le temps après 60 min est
  facturé, d'où un saut au passage de 75 à 76 min (EXT : 70 000 → 78 000).

Exemples (`standard`) :

| Payeur | Durée | Coût |
|---|---|---|
| GAP | 60 min | 12 000 |
| GAP | 75 min | **12 000** (tolérance) |
| GAP | 90 min | 12 000 + 30 min à 12 000/h = **18 000** |
| MIL | 75 min | **50 000** |
| EXT | 76 min | 70 000 + 16 min à 30 000/h = **78 000** |
| EXT | 90 min | 70 000 + 30 min à 30 000/h = **85 000** |
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
| `correctAccount` (**nouveau solde**, motif obligatoire ; révision du 2026-10-01) | Instructeurs et admins | Transaction `correction` de l'écart entre le nouveau solde et le solde lu dans la transaction ; refusée si le solde est déjà celui demandé |
| Régularisation | Automatique, sur `adminUpdateFlight` d'un vol clôturé | Vol imputé sur un solde : transaction `flight_adjustment` pour la différence entre l'ancien et le nouveau coût. Hors app : mise à jour de `billedAmount` |

### 4.6 Visibilité

- Chacun voit son solde et son historique.
- Les instructeurs et les admins voient tous les soldes et tous les historiques.

## 5. Écrans

Identiques sur mobile et sur web.

**Navigation** (révision du 2026-10-01) : les icônes de la barre du haut de
l'accueil (Carnet de vol, Mon compte, Instructeurs, Administration) figurent
sur tous les écrans. Un appui ouvre directement l'écran voulu, juste
au-dessus de l'accueil : « retour » ramène toujours à l'accueil. L'icône de
l'écran affiché est grisée.

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

**Confirmation des actions** (révision du 2026-10-01)
- Toute écriture passe par une Function : sans réseau, rien n'est enregistré
  (pas de file d'attente locale ; la lecture fonctionne hors ligne grâce au
  cache Firestore).
- Après une action réussie, l'app revient à l'écran précédent et affiche une
  confirmation : « Vol enregistré. », « Demande envoyée à DPS. »,
  « Modifications enregistrées. », « Vol validé. », « Vol clôturé. »… Le
  serveur ne répond qu'après l'écriture dans Firestore : la confirmation
  vaut enregistrement.
- Sans réponse du serveur (hors ligne, coupure, délai) : « Pas de réponse du
  serveur. Vérifiez votre connexion, puis le planning avant de recommencer :
  l'opération a pu aboutir. » Un refus du serveur affiche son propre message.

**Détail d'un vol**
- Toutes les informations, et les actions permises selon le rôle : valider,
  refuser, modifier, annuler, clôturer (durée réelle), corriger (admin).
- **Clôture** : saisie de la durée réelle et du nombre d'atterrissages
  (pré-rempli à 1), plus, sur un appareil amphibie, du nombre d'amerrissages
  (pré-rempli à 0) ; entiers de 0 à 99, au moins 1 posé au total. Si la
  durée réelle dépasse fin − début, l'heure de fin est allongée d'autant. Si elle est inférieure à 45 min,
  un champ obligatoire « Montant à facturer » apparaît. Pour tout vol avec un
  passager sans compte, une case « Montant différent (facturé hors app) »
  permet de saisir le montant : le vol passe alors en `custom` et aucun solde
  n'est débité.
- **Carburant** (révision du 2026-10-02) : voir §9.

**Carnet de vol** (révision du 2026-09-30 : remplace les écrans « Vols
effectués » et « Compteurs »)
- Un seul écran, ouvert par l'icône « Carnet de vol » de l'accueil. Il liste
  les vols **effectués** (date ≤ aujourd'hui, clôturés ou non), **tous
  appareils confondus**, du plus récent au plus ancien. Seuls les vols
  validés et non supprimés y figurent.
- En haut, le nombre d'atterrissages de la période, et celui des
  amerrissages s'il y en a ; chaque vol clôturé affiche les siens
  (« Clôturé · 1 h 15 · 2 att. »).
- En haut, le **temps de vol total** de la période choisie, calculé sur
  `actualFlightMinutes` des vols clôturés, non supprimés. Chaque vol compte
  une fois ; dans un vol à deux, chaque membre de `crew` le cumule sur son
  carnet. Les passagers sans compte ne comptent pas.
- Période : un menu des mois (janvier à décembre, plus « Année »), un menu
  de l'année (année en cours par défaut), et un bouton « Période précise »
  qui ouvre un calendrier où l'on choisit le début puis la fin. Par défaut :
  le mois en cours.
- Un pilote voit ses vols (ceux où il est dans l'équipage) et son total.
  Un instructeur ou un admin a en plus un menu « Pilote » : lui-même par
  défaut, un autre pilote, ou « Tous les pilotes » (tous les vols du club).
- Menu « Appareil » pour tous (« Tous les appareils » par défaut, appareils
  inactifs compris) : il restreint la liste et le total à un appareil. Avec
  « Tous les pilotes », on obtient le total d'heures de l'appareil.
- C'est l'endroit pour **clôturer** : un vol non clôturé s'ouvre dans la
  fenêtre du vol, avec l'action « Clôturer » (membres de l'équipage et
  admins, §3.3). Les vols à clôturer (date du jour ou avant, sans condition
  d'heure) sont surlignés en orange. Un compteur « N vols à clôturer » les
  compte sur toutes les périodes ; un appui dessus les affiche.
- Sélecteur **« Tous | Clôturés | Non clôturés »** (révision du 2026-10-05),
  « Tous » par défaut : il filtre la liste de la période ; le temps de vol et
  les atterrissages n'en dépendent pas. Choisir un segment ou une période
  quitte l'affichage « à clôturer », qui s'arrête aussi de lui-même quand il
  ne reste plus aucun vol à clôturer.
- Le planning (accueil) reste limité aux vols à venir, **non clôturés** (révision du 2026-10-15) : un vol clôturé n'apparaît plus que dans le carnet de vol et les récapitulatifs.
- **Rappel au lancement** (révision du 2026-10-02) : au démarrage de l'app,
  si un vol validé, non clôturé, dont l'utilisateur est membre de `crew` a
  son heure de fin passée, la fiche du plus ancien s'ouvre au-dessus de
  l'accueil (bouton « Clôturer »). « Retour » ramène à l'accueil ; pas de
  nouveau rappel avant le prochain lancement, ni au retour d'arrière-plan.

**Mon compte**
- Solde, historique, profil (badge), appartenance.
- Bouton « Se déconnecter » (retiré de la barre d'accueil au plan 4).

**Pilotes** (icône « Pilotes », anciennement « Instructeurs » ; instructeurs
et admins seulement)
- Liste des comptes avec leur solde et, sur chaque ligne, un bouton
  « Créditer » qui ouvre « Créditer / corriger ». Un appui sur le nom ouvre
  la fiche du compte (historique, « Créditer / corriger »).
- « Corriger » : on saisit le nouveau solde total (pré-rempli avec le solde
  actuel), pas un écart.
- Champs de montant : chiffres regroupés par milliers pendant la saisie
  (« 350 000 »).

**Administration**
- Utilisateurs : création, profil, catégorie, admin, activation. Révision du
  2026-10-06 : **suppression** d'un compte **vierge** seulement (aucun vol,
  même annulé, ni aucun mouvement de solde ; jamais son propre compte), par le
  bouton « Supprimer le compte » de la fenêtre de compte, avec confirmation
  (`adminDeleteUser` : compte Auth, `users`, `profiles`) ; sinon refus « Ce
  compte a un historique (vols ou mouvements de solde) : désactivez-le
  plutôt. ». Sur chaque ligne, les puces (appartenance, amphibie, admin,
  désactivé) sont sous le nom ; seule l'icône du lien de mot de passe est à
  droite.
- **Tri des comptes** (révision du 2026-10-06), partout où des comptes sont
  listés (Utilisateurs, Pilotes, choix d'un équipier, menu « Pilote » du
  carnet) : instructeurs, lâchés toutes missions, lâchés solo, élèves, puis
  non-pilotes ; dans chaque groupe, ordre alphabétique du nom (sans casse ni
  accents).
- Appareils, tarifs.
- **Relevé des vols facturés** : sur une période, chaque vol clôturé avec son
  mode, son **temps de vol réel**, son montant facturé, son payeur ou « hors
  app », son appareil et son équipage ; totaux « débité sur comptes » et « facturé hors app » ; export
  CSV sur le web.

## 6. Notifications et rappels

### 6.1 Notifications push

Via FCM, avec le jeton dans `users.fcmToken`. Elles sont envoyées par les
Functions **après** l'écriture réussie ; un échec d'envoi est journalisé et
n'annule jamais l'action.

Plan 5 (2026-10-01) :
- plateformes : **Android et web** ; iOS plus tard, par un développeur
  dédié (clés APNs) ;
- l'auteur d'une action n'est jamais notifié ; les comptes inactifs ou sans
  jeton sont ignorés ; un jeton déclaré invalide par FCM est effacé ;
- un jeton par compte, celui du dernier appareil connecté ; effacé à la
  déconnexion ;
- un appui sur une notification ouvre l'app ; app ouverte, la notification
  s'affiche en bas de l'écran ;
- web : clé VAPID par projet (console Firebase → Cloud Messaging →
  Certificats Web Push), dans `lib/core/env.dart`.

| Événement | Destinataires |
|---|---|
| Nouvelle demande, ou demande modifiée | L'instructeur désigné |
| Demande validée (éventuellement modifiée) | Le créateur et l'équipage |
| Demande refusée (avec motif) | Le créateur |
| Vol validé annulé | L'équipage et l'instructeur désigné |
| Vol non clôturé 24 h après sa fin, puis toutes les **48 h** | Les membres de `crew` |
| Mouvement de crédit (crédit, correction, régularisation) | L'intéressé et **tous les autres instructeurs** |

### 6.2 Rappel de clôture par tâche planifiée (révision du 2026-10-01)

- Une tâche planifiée (`closingReminders`, toutes les heures, heure de
  Libreville) lit les vols `valide` non clôturés (deux égalités, sans index
  composite) et, pour chaque vol non supprimé :
  - fin + 24 h pas encore atteinte → rien ;
  - `lastReminderAt` vide, ou plus vieux que 48 h → notification aux membres
    de `crew`, puis `lastReminderAt` = maintenant (écrit même si l'envoi
    échoue, pour ne pas relancer toutes les heures).
- La tâche relit toujours l'horaire courant du vol : rien à reprogrammer
  quand l'heure de fin change. Un rappel part au plus une heure après son
  échéance.
- Remplace la file de tâches (`onTaskDispatched`, `reminderGen`) prévue à
  l'origine.

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
| `cashbox`, `cashMovements` | Instructeurs et admins | ✗ |

### 7.3 Structure du repo `ulmgap`

- `lib/core/` : profils et badges, calcul de coût (miroir du serveur, pour
  l'aperçu), formats.
- `lib/data/` : lecture Firestore, appels des Functions.
- `lib/features/` : `planning`, `flight`, `logbook`, `account`,
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
  carnet de vol (widgets).
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

## 9. Suivi carburant (révision du 2026-10-02)

But : savoir combien de carburant se trouve dans chaque appareil, et suivre
une tendance de consommation. Toutes les valeurs sont des **déclarations de
l'équipage**, en litres entiers de **0 à 100**. Le serveur ne fait **aucun
calcul** entre elles : seul l'écran « Suivi carburant » calcule, à titre
indicatif, la consommation estimée.

### 9.1 Saisie à la clôture

Le dialogue « Clôturer le vol » ajoute un bloc « Carburant », après les
atterrissages :
- « Carburant prévu au départ : 40 L » : carburant actuel de l'appareil, soit
  la valeur « rangé » déclarée par l'équipage du vol précédent ;
- case « Carburant réel à bord non conforme » ; cochée, elle fait apparaître
  le champ obligatoire « Carburant réel au départ (L) ». Si le carburant de
  l'appareil est **inconnu** (aucun vol précédent avec carburant), la case
  disparaît et le champ « Carburant au départ (L) » est affiché d'emblée,
  obligatoire ;
- « Carburant ajouté (L) » : obligatoire, pré-rempli à 0 (révision du 2026-10-05) ;
  avant ou après le vol, peu importe ;
- « Carburant à bord, appareil rangé (L) » : obligatoire, vide au départ.

`closeFlight` reçoit `fuelStartExpected` (valeur affichée, ou `null`),
`fuelStart`, `fuelAdded`, `fuelEnd` ; `fuelStartExpected` à `null` ou entier,
les trois autres obligatoires ; entiers de 0 à 100, mêmes messages côté app et
côté serveur. Le vol enregistre les quatre valeurs (§2.5).

**Alerte de consommation** (non bloquante) : au clic sur « Clôturer », l'app
calcule (départ + ajouté − rangé) / durée réelle. Hors de 8 à 30 L/h (bornes
acceptées), une fenêtre « Consommation inhabituelle » affiche « Consommation
calculée : 42,0 L/h. Vérifiez les valeurs saisies. » avec « Corriger »
(retour au dialogue) et « Confirmer » (clôture). Rien côté serveur.

### 9.2 Carburant actuel de l'appareil

Dans la même transaction que la clôture, `fuelEnd` est recopié sur
l'appareil (`fuelLiters`, `fuelFlightId`, `fuelFlightStart`) **si** ce vol
part au même moment ou après `fuelFlightStart`, ou si l'appareil n'a pas encore de
valeur. Un vol clôturé en retard, après un vol plus récent, ne remplace donc
pas un état plus récent.

Pas de saisie directe par un admin : un plein fait hors vol est déclaré par
l'équipage suivant, avec « non conforme ». Si un admin supprime le vol source,
l'appareil garde sa valeur.

### 9.3 Correction admin

`adminUpdateFlight` d'un vol clôturé accepte `fuelStart`, `fuelAdded`,
`fuelEnd` (facultatifs, mêmes bornes ; `fuelStartExpected` ne se corrige pas).
Pour un vol clôturé avant cette révision, ils restent facultatifs. Si le vol
est la source du carburant de l'appareil (`fuelFlightId`) et que son appareil
ne change pas, `fuelLiters` suit le nouveau `fuelEnd`. Sinon, aucun appareil
n'est modifié.

### 9.4 Affichages

- « Carburant : 40 L » (ou « Carburant : inconnu ») : dans le formulaire de
  vol sous le choix de l'appareil, sur la fiche d'un vol non clôturé, dans
  Administration → Appareils. Un appui ouvre « Suivi carburant ».
- Fiche d'un vol clôturé : « Carburant : départ 40 L · ajouté 20 L · rangé
  35 L », suivi de « (prévu 30 L) » ou « (prévu inconnu) » en cas d'écart.

### 9.5 Écran « Suivi carburant »

Ouvert par tout utilisateur (« Carburant : 40 L », icône de Administration →
Appareils), titre « Suivi carburant · F-XXXX » (révision du 2026-10-05 :
tableau) :
- en haut, le carburant actuel et la **consommation estimée** sur tous les
  vols : Σ (départ + ajouté − rangé) / Σ `actualFlightMinutes`, en L/h, sur
  les vols clôturés non supprimés qui ont les trois valeurs ; « Consommation
  estimée : 14,2 L/h (12 vols, 18 h 30) ». Indicative, masquée tant qu'aucun
  vol ne compte ;
- le **sélecteur de période du carnet** (mois, année, période précise ; mois
  en cours par défaut) ;
- un **tableau** des vols clôturés non supprimés de la période, du plus
  récent au plus ancien : Date, Équipage, Temps de vol, Départ (L), Ajouté
  (L), Rangé (L), Conso (L) = départ + ajouté − rangé, Conso (L/h), Att., et
  Am. pour un appareil amphibie ou si un vol en a. « Ajouté » est vide sans
  ajout, en gras sur fond coloré sinon. Un écart au départ colore la case
  « Départ » en orange (valeur prévue en bulle d'aide) ; une conso hors de 8
  à 30 L/h est en orange. Les vols d'avant le suivi carburant affichent « — »
  dans les colonnes carburant. Un appui sur une ligne ouvre la fiche du vol ;
- une **ligne de totaux** : temps de vol et atterrissages de tous les vols de
  la période ; ajouts, conso totale et moyenne en L/h sur ceux qui ont du
  carburant. Sans vol : « Aucun vol clôturé sur cette période. »

Requête : `flights` filtrés sur `aircraftId`, tri et filtres dans l'app ; ni
index ni règle nouvelle. Aucun champ du contrat du pont ne change.

**Déploiement** : `closeFlight` exige les champs carburant ; l'app et les
Functions se déploient ensemble.

## 10. Vol d'instruction et baptême de l'air (révision du 2026-10-05)

### 10.1 Vol d'instruction

- **Case « Vol d'instruction »** (`flights.instruction`) dans le formulaire de
  vol (création, modification, validation), visible seulement si l'équipage
  compte **exactement un instructeur et un autre membre avec compte**. Deux
  instructeurs ensemble, ou un instructeur avec un passager sans compte : pas
  d'instruction. La case se décoche si l'équipage ne remplit plus la
  condition. Modifiable par le créateur, l'instructeur qui valide ou un admin,
  jusqu'à la clôture. Le serveur refuse `instruction: true` hors condition.
- **À la clôture**, si `instruction` est vrai et `actualFlightMinutes` ≥ 45 :
  l'instructeur de l'équipage est crédité de `instructionCredit` (tarifs
  figés du vol, sinon courants) : transaction `instruction`, motif « Crédit
  instruction », dans la même transaction Firestore que la clôture, avec la
  notification habituelle d'un mouvement. Le vol enregistre
  `instructionCreditUid` et `instructionCreditAmount`.
- **Aucune mention à la clôture** ni sur le vol (ni aperçu, ni dialogue, ni
  résumé du vol clôturé) : le crédit n'est visible que dans l'historique du
  compte de l'instructeur. La fiche du vol indique seulement « Vol
  d'instruction (XXX) ».
- **Correction ou suppression admin** d'un vol clôturé : le crédit dû est
  recalculé (case, durée, instructeur) ; l'écart avec le crédit versé est
  régularisé par des transactions `instruction`, motif « Régularisation
  crédit instruction » (retrait, ajout, ou les deux en cas de changement
  d'instructeur), dans la même transaction que la correction. Suppression :
  retrait du crédit versé.
- **Historique** (Mon compte, fiche Pilotes) : « Crédit instruction — vol du
  12 oct. », « Régularisation crédit instruction — vol du 12 oct. ».

### 10.2 Baptême de l'air

- La fenêtre « Ajouter un passager sans compte » a, en plus du nom, une case
  **« Baptême de l'air »** qui ouvre un **choix obligatoire du forfait**
  (révision du 2026-10-05) : **Local** (70 000), **Nyonye** (90 000),
  **Awagne** (110 000), montants de `baptismFees`. Le vol stocke
  `baptismTier` (`local` / `nyonye` / `awagne`). La ligne du passager affiche
  « Passager sans compte · Baptême Nyonye » et permet de changer la case et
  le forfait tant que le vol est modifiable (jusqu'au départ). Retirer le
  passager retire le baptême.
- Le vol passe en mode **`baptism`**, prioritaire sur `standard` et
  `fuel_only` (la case « Carburant seulement » est masquée) : facturé **hors
  app** (`billedTo: off_app`), **`baptismFees[baptismTier]` quelle que soit
  la durée**. Aucun solde débité, aucun contrôle de crédit disponible.
  L'aperçu affiche « Baptême Nyonye : 90 000 FCFA, facturé hors app ». Le
  serveur refuse un baptême sans forfait valide.
- À la clôture : ni « Montant à facturer » ni « Montant différent » ; montant
  affiché « 90 000 FCFA facturé hors app ».
- Après la clôture, seul l'admin change le baptême ou son forfait (correction
  admin), avec la régularisation habituelle (§4.5).
- Fiche du vol : tarification « Baptême Nyonye ». Relevé des vols facturés et
  export CSV : mode « Baptême Nyonye », compté dans « facturé hors app ».

### 10.3 Tarifs et déploiement

- Administration → Tarifs : « Crédit instruction » et les trois forfaits
  « Baptême Local / Nyonye / Awagne » (`instructionCredit`, `baptismFees`),
  ainsi que « Tolérance jusqu'à » (`toleranceMinutes`), figés dans `pricingSnapshot`
  à la validation comme les autres tarifs ; un vol figé avant cette révision
  utilise les valeurs par défaut.
- Ni règle Firestore, ni index, ni champ du contrat du pont ne changent.
- Les Functions de vol, de clôture, de correction et de tarifs se déploient
  avec l'app.

## 11. Suivi de caisse (révision du 2026-10-14)

But : tenir dans l'app la caisse unique de l'association, reprise du
fichier Excel « caisse Ulmgap » (deux tableaux, « COMPTE ULM » et « COMPTE
COURANT JOURNALIER », **fusionnés**), sans double comptage avec les comptes
des adhérents. Gérée par les admins et les instructeurs.

Ce chantier est le premier de trois : **caisse** (ce §), puis **vol
technique** et **suivi de cuve** (révisions à venir). Principe commun :
**la caisse suit l'argent, la cuve suit les litres**. Un vol technique ne
touche jamais la caisse : le carburant, déjà payé à l'achat, sort de la
cuve.

### 11.1 Libellés normalisés

Une même réalité, un seul libellé. Acompte, crédit de vol, crédit
carburant, « CREDIT VOLS ULM » : c'est toujours un adhérent qui apporte de
l'argent, mis en caisse, et dont le compte est alimenté d'autant.

| `kind` | Libellé | Sens | Effet |
|---|---|---|---|
| `fuel_credit` | **Crédit carburant XXX** (`shortName` de l'adhérent) | Entrée | Caisse + **et** compte de l'adhérent + |
| `fuel_purchase` | **Achat carburant** | Sortie | Caisse − |
| `maintenance` | **Maintenance** (pièces, réparations, nettoyage, équipement, citerne…) | Sortie | Caisse − |
| `off_app_income` | **Recette hors app** (baptême, vol au montant différent payé en espèces) | Entrée | Caisse + |
| `cash_gap` | **Écart de caisse** (motif obligatoire) | ± | Caisse ± |
| `opening` | **Fond initial** (import seulement, jamais saisi) | Entrée | Caisse + |

Chaque libellé a une icône. Dans l'historique d'un compte d'adhérent, le
type `credit` s'affiche désormais « Crédit carburant ».

### 11.2 Données

**`cashbox/main`** : `balance` (int, FCFA), `migrationClosedAt`
(timestamp ou `null` tant que la reprise est en cours, §11.5), `updatedAt`.
Toute opération de caisse lit puis écrit ce document dans sa transaction :
les opérations se sérialisent.

**`cashMovements/{id}`**, historique non modifiable :

| Champ | Contenu |
|---|---|
| `kind` | §11.1 |
| `amount` | int signé : positif pour une entrée, négatif pour une sortie |
| `date` | Jour de l'opération, chaîne « AAAA-MM-JJ » (jour du club, Africa/Libreville) : aujourd'hui par défaut, jamais dans le futur |
| `userUid` | Adhérent d'un `fuel_credit` ; `null` pour une ligne importée |
| `transactionId` | Ligne `transactions` jumelle d'un `fuel_credit` (ou de sa correction) |
| `note` | Texte : objet de la dépense, motif, ou libellé d'origine de l'Excel |
| `correctsId` | Ligne d'origine, pour une correction (§11.4) ; `null` sinon |
| `imported` | `true` pour une ligne reprise de l'Excel |
| `by` | uid de l'auteur, ou `import` |
| `at` | timestamp serveur |
| `balanceAfter` | Solde de caisse après le mouvement |

Règle absolue, comme pour les comptes : **le solde de caisse n'est jamais
modifié sans sa ligne d'historique**, dans la même transaction. Un
`fuel_credit` écrit, dans **une seule** transaction, la ligne de caisse, le
solde de caisse, la ligne `transactions` et le solde de l'adhérent.

**Règles Firestore** : `cashbox` et `cashMovements` en lecture pour les
admins et les instructeurs, aucune écriture client. Ni index composite ni
index nouveau : l'app filtre par `kind`.

### 11.3 Opérations

| Function | Qui | Règle |
|---|---|---|
| `creditAccount` (élargie) | Instructeurs et admins | **Crédit carburant** : montant > 0, date, note facultative. Caisse + et compte + (§11.2), notification habituelle à l'adhérent |
| `addCashMovement` | Instructeurs et admins ; `cash_gap` : **admins seulement** | `fuel_purchase` (montant > 0, débité), `maintenance` et `off_app_income` (montant > 0, note obligatoire), `cash_gap` (montant ≠ 0 signé, note obligatoire). `fuel_credit` et `opening` refusés ici |
| `correctCashMovement` | Instructeurs et admins ; correction d'un `cash_gap` : **admins seulement** | Voir §11.4 |
| `closeMigration` | **Admins seulement** | « Reprise terminée » : `migrationClosedAt` = maintenant. Irréversible ; refusée si déjà faite |
| `correctAccount` (existante) | Instructeurs et admins | Inchangée **tant que la reprise est en cours**. Ensuite refusée : « La reprise est terminée : corrigez le crédit carburant concerné. » |

Montants entiers en FCFA, sans plafond (comme les crédits, §4.4).

### 11.4 Corrections : on corrige une opération, jamais un solde

- On saisit le **montant juste** de l'opération ; 0 l'annule. Le **montant
  juste actuel** d'une ligne = son montant + celui de toutes ses
  corrections (relues dans la transaction) ; on peut donc corriger
  plusieurs fois. Refus si le montant saisi est déjà le montant juste.
- La correction est une **nouvelle ligne** du même `kind`, `correctsId` =
  ligne d'origine, `amount` = écart, **même `date` que la ligne d'origine**
  (elle reste dans la même période), note « Correction » ou « Correction :
  motif ». On ne corrige qu'une ligne d'origine, jamais une ligne de
  correction. Corriger un Écart de caisse ou le Fond initial : admins
  seulement.
- Le signe reste celui du `kind` : le montant juste d'une entrée est ≥ 0,
  celui d'une sortie ≤ 0 (saisi en positif dans l'app) ; un `cash_gap`
  accepte les deux signes.
- **Crédit carburant** : l'écart est porté aussi sur le compte de
  l'adhérent, transaction `credit`, motif « Correction crédit carburant du
  12/10/2026 », dans la même transaction, avec la notification habituelle.
  L'équilibre caisse / comptes est préservé par construction.
- **Ligne importée** : corrigeable (caisse seulement, aucun adhérent).
- Les autres erreurs ont déjà leur circuit : la facturation d'un vol par la
  correction admin (§4.5), le crédit instruction par sa régularisation
  automatique (§10.1).
- **Ce qui ne s'explique pas ressort en Écart de caisse** (admin, motif
  obligatoire) : par exemple l'écart entre le comptage physique et le solde.

### 11.5 Reprise de l'existant

1. **Import** de l'historique de l'Excel, une fois (§11.7).
2. **Comptage physique** de la caisse ; l'écart éventuel avec le solde
   importé est saisi en Écart de caisse.
3. **Reprise des soldes** à la main, avec « Corriger le solde »
   (`correctAccount`, sans effet sur la caisse) : l'argent est déjà en
   caisse. Aucun acompte de l'Excel ne crédite automatiquement un compte,
   certains l'ayant déjà été.
4. **« Reprise terminée »** (admin) : à partir de là, plus de correction de
   solde libre ; seules restent les opérations du §11.3 et les corrections
   du §11.4. Toute divergence entre caisse et comptes a donc une ligne
   visible qui l'explique.

### 11.6 Écrans

- **Icône « Caisse »** dans la barre de navigation (§5), pour les
  instructeurs et les admins, entre « Pilotes » et « Administration ».
- **En-tête** : « Caisse : 3 638 000 FCFA », « Avoirs adhérents : X »
  (somme nette des soldes de tous les comptes) et « Disponible : caisse −
  avoirs ».
- **Filtres** : cinq puces à icône (Crédit carburant, Achat carburant,
  Maintenance, Recette hors app, Écart de caisse), aucune sélectionnée par
  défaut (tout s'affiche, Fond initial compris). Une correction suit le
  filtre de sa ligne d'origine.
- **Période** : le sélecteur du carnet de vol (mois en cours par défaut),
  sur `date`.
- **Liste** : du plus récent au plus ancien (`date`, puis `at`) ; icône,
  libellé (« Crédit carburant LCM »), note, date, montant en vert (entrée)
  ou en rouge (sortie), mention « Correction » le cas échéant. Pas de solde
  progressif par ligne (trompeur pour une opération saisie après coup).
  Ligne de totaux de la période : entrées, sorties. Sans opération :
  « Aucune opération sur cette période. »
- **« + Opération »** : type (Écart de caisse visible des admins seulement),
  adhérent pour un Crédit carburant, montant (milliers groupés), date, note.
- **Appui sur une ligne** : détail (auteur, date de saisie, ligne d'origine
  ou corrections) et bouton « Corriger » selon les droits du §11.3.
- **Pilotes** (§5) : « Créditer » devient « Crédit carburant » (même
  Function, avec la date). « Corriger » disparaît une fois la reprise
  terminée.
- **Reprise** : sur l'écran Caisse, pour les admins, bouton « Reprise
  terminée » avec confirmation, tant que la reprise est en cours ; ensuite
  « Reprise terminée le 20/10/2026 ».

### 11.7 Import de l'Excel

- Script `functions/scripts/import-cashbox.js --project <id> --file
  <caisse.csv>` (identifiants ADC, comme `bootstrap-admin.js`). Accepte
  **`ulmgap-dev`** (d'abord, pour la recette) et `ulmgap-prod`. Refuse si
  `cashMovements` contient déjà une ligne. Écrit les lignes (`imported:
  true`, `by: import`, `userUid: null`) et `cashbox/main` dans un seul lot,
  ordonnées par date.
- CSV normalisé `date;kind;amount;note`, préparé depuis l'Excel et **relu
  par l'utilisateur avant import**. Le CSV et l'Excel restent **hors du
  dépôt** (données financières).
- Normalisation :
  - fond initial de 10 000 000 : `opening` ;
  - RESERVOIR, ESSENCE : `fuel_purchase` ;
  - réparation Rotax, huile, pièces Loravia et St Ex, batterie, roue,
    lettres d'immatriculation, flexible et filtre citerne, travaux citerne
    roulante, cadenas et déménagement, nettoyage : `maintenance` ;
  - CREDIT VOLS ULM, « vol » payés comptant, acomptes LCM et CNL, LCM :
    `fuel_credit` sans adhérent ;
  - libellé d'origine en `note`.
- **« vol ww » (vol Wonga-Wongué) n'est pas importé** : les 24 000 ne sont
  jamais sortis de la caisse, seul le carburant est sorti de la cuve. Ce vol,
  pas encore clôturé dans l'app, servira de recette au vol technique.
- Les trois lignes sans date (fond initial, réservoir, réparation Rotax)
  prennent la plus ancienne date du fichier, le 05/03/2025.
- Le solde est recalculé ligne par ligne : **2 290 000** pour l'ancien
  « COMPTE ULM » (l'Excel affiche 2 376 000 à cause d'une formule qui saute
  la ligne « roue vis etc st ex », 86 000) et **1 348 000** pour le compte
  courant sans « vol ww », soit **3 638 000** avant comptage physique.

### 11.8 Recette en dev puis déploiement

- Toute la chaîne se recette d'abord sur **`ulmgap-dev`** : import du CSV,
  comptage simulé et Écart de caisse, reprises par « Corriger le solde »,
  « Reprise terminée », puis Crédits carburant, dépenses et corrections. En
  dev, les comptes de test portent un « Crédit initial (tests) » sans
  contrepartie en caisse : les avoirs adhérents y sont donc fictifs.
- En prod, une fois la recette faite (par l'utilisateur) : règles, Functions
  (`creditAccount`, `correctAccount`, `addCashMovement`,
  `correctCashMovement`, `closeMigration`) et app ensemble, puis l'import.
- Ni index, ni champ du contrat du pont ne changent.

### 11.9 Tests

- Unitaires (module pur `rules/`) : montant juste et écart d'une
  correction, signes autorisés par `kind`, libellés.
- Intégration (émulateur) : chaque Function ; caisse, compte et deux
  historiques dans la même transaction ; droits (instructeur refusé sur
  `cash_gap` et `closeMigration`) ; `correctAccount` refusée après la
  reprise ; corrections successives ; import refusé sur une caisse non vide.
- Règles Firestore : lecture staff seulement, aucune écriture client.
- Widgets : écran Caisse (en-tête, filtres, totaux), dialogues d'opération
  et de correction, bouton « Reprise terminée ».

## 12. Vol technique (révision du 2026-10-14)

But : un vol au profit de l'association (convoyage, essai, maintenance…)
n'est facturé à personne. Principe du §11 : **la caisse suit l'argent, la
cuve suit les litres**. Le carburant d'un vol technique, déjà payé à
l'achat, n'est débité ni au pilote ni à la caisse ; ses litres seront
comptés en consommation de l'association au plan « suivi de cuve ».

### 12.1 Saisie

- **Case « Vol technique »** (`flights.technical`, bool) dans le formulaire
  de vol (création, modification, validation, correction admin), visible des
  **instructeurs et des admins** seulement, avec un **motif obligatoire**
  (`flights.technicalReason`, texte libre, 80 caractères au maximum :
  « Convoyage Wonga-Wongué », « Essai moteur »).
- Le serveur refuse `technical: true` posé par un autre qu'un instructeur
  ou un admin : « Vol technique : réservé aux instructeurs et aux admins. »
- **Instructeur payeur obligatoire** (révision du 2026-10-15) : un vol ne
  peut être technique que si le **premier membre de l'équipage** (le payeur)
  est un **instructeur**. La règle vaut pour tout le monde, admin compris,
  sur toutes les écritures (création, modification, validation, correction
  admin). Refus serveur (`failed-precondition`) et message de l'app,
  identiques : « Impossible de modifier car vol technique sélectionné. Pour
  modifier, décochez l'option vol technique. »
- Dans l'app, la case n'apparaît que si le payeur est un instructeur. Case
  cochée, tout changement d'équipage qui laisserait un non-instructeur en
  tête (retrait de l'instructeur, remplacement, changement d'ordre) est
  refusé avec ce message : l'équipage reste inchangé.
- **Incompatibilités** (refus serveur, case masquée dans l'app) : vol
  d'instruction (§10.1) et baptême de l'air (§10.2). Un **passager sans
  compte** reste possible (mécanicien), sans facturation.
- Matrice des droits (§3.2), contrôles communs (§3.4), conflits (§3.5) et
  appareil amphibie (§3.6) : inchangés.

### 12.2 Facturation

- Mode **`technical`**, prioritaire sur tous les autres (`standard`,
  `fuel_only`, `baptism`) ; `custom` impossible.
- **Aucun contrôle de crédit** (§4.4).
- **Clôture** : dialogue inchangé (durée, atterrissages, amerrissages,
  carburant), sans « Montant à facturer » ni « Montant différent » (refus
  serveur : « Aucun montant pour un vol technique. »). Le vol enregistre
  `billedAmount: 0`, `billedTo: "association"` ; **aucun mouvement** de
  compte ni de caisse ; pas de crédit d'instruction. Résumé : « Vol
  technique : non facturé (association) ».
- **Correction admin** d'un vol clôturé (§4.5) : passer un vol en technique
  rembourse le débit du payeur (transaction `flight_adjustment`) ; l'inverse
  le débite. Aucune ligne de caisse.

### 12.3 Affichages

- Fiche du vol : « Vol technique — motif ».
- Aperçu du formulaire : « Vol technique : non facturé (association) ».
- Relevé des vols facturés et export CSV : mode « Vol technique », montant
  0, payeur « association » ; total distinct « Vols techniques : N vols,
  durée totale ».
- Suivi carburant (§9.5) : les lignes des vols techniques portent une
  marque « T » (bulle d'aide « Vol technique »).
- Carnet de vol : heures comptées normalement.
- Ni règle Firestore, ni index, ni champ du contrat du pont ne changent
  (`pricingMode` n'est pas lu par le pont).

### 12.4 Recette

Le vol « ww » (Wonga-Wongué), passé et non clôturé : un admin le corrige
en « Vol technique » (motif « Convoyage Wonga-Wongué »), puis on le
clôture. Son équipage doit commencer par un instructeur (sinon la
correction est refusée, §12.1). Attendu : aucun compte débité, aucune ligne de caisse,
`billedTo: "association"`.

## 13. Suivi de cuve et carburant « bidon perso » (révision du 2026-10-15)

But : suivre les litres de la cuve (citerne roulante) pour qu'aucun litre
ne disparaisse sans explication, sans double comptage avec la caisse
(§11) : **la caisse suit l'argent, la cuve suit les litres**. Un pilote
qui apporte son propre carburant (bidon perso) est crédité sur son compte.

### 13.1 Données

**`tank/main`** : `liters` (int, peut devenir négatif : signe d'un oubli de
saisie, affiché en orange, jamais bloquant), `updatedAt`. Une seule cuve,
sans capacité maximale.

**`tankMovements/{id}`**, historique non modifiable :

| Champ | Contenu |
|---|---|
| `kind` | `refill` (remplissage) / `flight` (avitaillement à la clôture) / `aircraft_fill` (plein hors vol) / `gauge` (relevé de jauge) / `flight_adjustment` (régularisation d'un vol corrigé ou supprimé) |
| `liters` | int signé : positif = entrée, négatif = sortie ; pour `gauge`, l'écart (mesuré − calculé) |
| `date` | Jour de l'opération « AAAA-MM-JJ » (jour du club) ; pour un vol, le jour du vol |
| `flightId`, `aircraftId` | Vol ou appareil concerné, sinon `null` |
| `cashMovementId` | Ligne d'Achat carburant jumelle d'un `refill`, sinon `null` |
| `measuredLiters` | Niveau mesuré, pour `gauge` seulement |
| `technical` | `true` si le vol est un vol technique (consommation de l'association) |
| `note` | Texte libre facultatif (motif d'un relevé, d'un plein) |
| `by`, `at`, `litersAfter` | Auteur, horodatage serveur, niveau après le mouvement |

Règle absolue, comme pour la caisse : **le niveau n'est jamais modifié sans
sa ligne**, dans la même transaction. Règles Firestore : lecture
instructeurs et admins, aucune écriture client.

### 13.2 Provenance du carburant à la clôture

Le bloc « Carburant » du dialogue de clôture (§9.1) change pour le
carburant ajouté :
1. **Première question : « Carburant ajouté »** : « Aucun » (par défaut),
   « Depuis la cuve », « Bidon perso » ou « Les deux ».
2. Selon le choix :
   - **Depuis la cuve** : « Litres pris à la cuve » ;
   - **Bidon perso** : « Litres du bidon perso » et « Pilote ayant fourni
     le carburant » (membres de l'équipage avec compte ; par défaut celui
     qui clôture s'il est dans l'équipage, sinon le premier) ;
   - **Les deux** : les deux champs de litres et le pilote.
   Chaque nombre de litres saisi est un entier de 1 à 100.
3. Le **carburant ajouté total** (`fuelAddedLiters`, §9) = litres cuve +
   litres bidon, affiché ; total ≤ 100 L. Les autres champs carburant
   (départ, rangé) et l'alerte de consommation sont inchangés.
4. Avec un bidon perso, l'app affiche « Crédit : 20 L × 600 = 12 000 FCFA
   pour XXX ».

`closeFlight` reçoit `fuelFromTank` et `fuelFromPersonal` (entiers ≥ 0,
somme ≤ 100) et `fuelSupplierUid` (obligatoire si `fuelFromPersonal` > 0,
membre de `crew`, sinon `null`) à la place de `fuelAdded`, qu'il calcule.
Le vol enregistre `fuelFromTankLiters`, `fuelFromPersonalLiters`,
`fuelSupplierUid`, `fuelSupplyCredit` (montant crédité) en plus de
`fuelAddedLiters`.

Dans la même transaction que la clôture :
- `fuelFromTank` > 0 : mouvement de cuve `flight` (−litres, `technical`
  selon le vol) ;
- `fuelFromPersonal` > 0 : le pilote est crédité de `fuelFromPersonal ×
  fuelLiterPrice` (arrondi au franc), transaction **`fuel_supply`**
  rattachée au vol, motif « Carburant fourni (bidon perso) », avec la
  notification habituelle d'un mouvement. Ni caisse ni cuve ne bougent.
  Vaut aussi pour un vol technique.

Historique du compte : « Carburant fourni (bidon perso) — vol du 12 oct. ».

### 13.3 Tarif

`settings/pricing.fuelLiterPrice` : « Prix du litre (bidon perso) » dans
Administration → Tarifs, **600** par défaut, 0 à 10 000. Il est lu au
moment de la clôture (tarifs courants, pas `pricingSnapshot`) ; le montant
crédité est figé sur le vol (`fuelSupplyCredit`).

### 13.4 Correction et suppression admin

`adminUpdateFlight` d'un vol clôturé accepte `fuelFromTank`,
`fuelFromPersonal`, `fuelSupplierUid` (mêmes règles ; absents =
inchangés). Régularisations dans la même transaction :
- cuve : mouvement `flight_adjustment` de l'écart entre les anciens et les
  nouveaux litres pris à la cuve ;
- compte : transactions `fuel_supply`, motif « Régularisation carburant
  fourni », pour l'écart de crédit (retrait, ajout, ou les deux en cas de
  changement de pilote), au prix figé du vol (`fuelSupplyCredit` ÷ litres)
  ou, s'il n'y en avait pas, au prix courant.
`adminDeleteFlight` d'un vol clôturé : remet les litres pris à la cuve
(`flight_adjustment` +litres) et retire le crédit versé.

Un vol clôturé avant cette révision n'a ni provenance ni mouvement de
cuve : sa correction ne crée de mouvement que pour l'écart avec « 0 L pris
à la cuve, 0 L de bidon » si l'admin saisit la provenance.

### 13.5 Opérations de cuve

| Opération | Qui | Effet |
|---|---|---|
| **Remplissage** | Instructeurs et admins | Champ facultatif **« Litres »** de l'Achat carburant (§11.3) : s'il est rempli, la même transaction écrit la sortie de caisse et le mouvement `refill` (+litres, `cashMovementId`). La correction de l'achat (§11.4) ne touche pas les litres ; une erreur de litres se corrige par un relevé de jauge |
| **Plein d'un appareil** (hors vol) | Instructeurs et admins | Appareil, litres (1 à 100), date, note : mouvement `aircraft_fill` (−litres) ; carburant actuel de l'appareil augmenté d'autant, plafonné à 100 L, `fuelFlightStart` = maintenant (un vol plus ancien clôturé ensuite ne l'écrase pas, §9.2) |
| **Relevé de jauge** | Instructeurs et admins | Niveau mesuré (entier ≥ 0), date, note : mouvement `gauge` de l'écart, `measuredLiters` ; le niveau devient la mesure. Le premier relevé fixe le niveau de départ |

### 13.6 Écrans

- **Clôture** : §13.2.
- **Caisse** (§11.6) : ligne « Cuve : 180 L » sous l'en-tête ; un appui
  ouvre **« Suivi cuve »** (instructeurs et admins).
- **Suivi cuve** : niveau actuel (orange s'il est négatif), boutons « Plein
  d'un appareil » et « Relevé de jauge », sélecteur de période du carnet,
  liste des mouvements (date, libellé, appareil ou vol, litres signés,
  niveau après), totaux de la période : remplissages, sorties vers les vols
  (dont vols techniques), pleins hors vol, écarts de jauge. Un appui sur une
  ligne de vol ouvre la fiche du vol.
- **Achat carburant** (dialogue d'opération de caisse) : champ « Litres
  (facultatif) ».
- **Fiche d'un vol clôturé** : « Carburant : départ 40 L · ajouté 20 L
  (cuve 10 L, bidon 10 L — XXX) · rangé 35 L ».
- **Suivi carburant** (§9.5) : la colonne « Ajouté » reste le total.
- **Tarifs** : « Prix du litre (bidon perso) ».

### 13.7 Déploiement et recette

- Règles Firestore (`tank`, `tankMovements`) et Functions `closeFlight`,
  `adminUpdateFlight`, `adminDeleteFlight`, `adminUpdatePricing`,
  `addCashMovement` et les nouvelles (`addAircraftFill`, `addGaugeReading`)
  avec l'app : `closeFlight` exige les nouveaux champs, un ancien build ne
  peut plus clôturer.
- Recette en dev d'abord : relevé de jauge initial, achat carburant avec
  litres, clôture « Les deux », plein hors vol, correction admin.
- Ni index nouveau, ni champ du contrat du pont.
