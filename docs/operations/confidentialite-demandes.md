# Confidentialité des demandes de vol

Les vols au statut `valide` restent visibles par tous les comptes actifs.
Les demandes (`demande`, y compris expirées) et les refus (`refuse`) ne sont
lisibles que par `createdBy` et `instructorUid`, même après annulation.
Aucune exception de lecture pour les autres instructeurs ou administrateurs.
Les règles utilisent les champs existants : aucune migration des vols requise.

L'application limite ses requêtes à ce périmètre. Les lectures du carnet,
du suivi carburant, du crédit réservé et des destinations récentes ne portent
que sur les vols validés. Le planning filtre aussi les données reçues.

## Mise en production par l'utilisateur

Depuis la racine du dépôt :

1. Déployer les index, puis attendre qu'ils soient prêts dans Firebase :

   ```bash
   firebase deploy --project prod --only firestore:indexes
   ```

2. Reconstruire et publier le web :

   ```bash
   fvm flutter build web --release --dart-define=ENV=prod
   firebase deploy --project prod --only hosting
   ```

   Reconstruire et distribuer également les applications mobiles utilisées.
   Pour Android :

   ```bash
   fvm flutter build apk --release --flavor prod --dart-define=ENV=prod
   ```

3. Activer la protection côté serveur :

   ```bash
   firebase deploy --project prod --only firestore:rules
   ```

La confidentialité serveur prend effet à l'étape 3. Les anciennes versions de
l'application utilisant les requêtes globales auront des erreurs de lecture
une fois les nouvelles règles actives ; elles doivent être mises à jour.
Les nouvelles règles ne peuvent pas effacer des données déjà téléchargées
avant leur activation.

Aucun déploiement de Cloud Functions supplémentaire n'est nécessaire pour
cette modification de visibilité.
