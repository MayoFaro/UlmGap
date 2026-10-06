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
- un **suivi carburant** par appareil (révision du 2026-10-02, §9).

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
- Le planning (accueil) reste limité aux vols à venir.
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
