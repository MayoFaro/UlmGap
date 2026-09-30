// Écran « Mon compte » (accessible à tous) : profil, appartenance, solde et
// historique des mouvements de l'utilisateur connecté.
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import 'movements_list.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.me});
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final users = AppServices.of(context).users;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon compte'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Service lu avant de démonter l'écran ; retour à la racine
              // d'abord, sinon cet écran resterait empilé au-dessus de
              // l'écran de connexion.
              final auth = AppServices.of(context).auth;
              Navigator.of(context).popUntil((r) => r.isFirst);
              auth.signOut();
            },
          ),
        ],
      ),
      // Fix round 1 (revue de la Task 11) : le solde de l'en-tête vient
      // désormais du flux `watchUser` (déjà en direct dans la porte
      // d'authentification), sinon il restait figé sur la valeur passée à la
      // navigation, en désaccord avec MovementsList après un crédit ou une
      // clôture. Repli sur `me` tant que le flux n'a pas encore émis.
      body: StreamBuilder<AppUser?>(
        stream: users.watchUser(me.uid),
        builder: (context, snap) {
          final current = snap.data ?? me;
          final negative = current.balance < 0;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(current.displayName,
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      ProfileBadge(profile: current.profile),
                    ]),
                    const SizedBox(height: 4),
                    Text(current.category.code),
                    const SizedBox(height: 8),
                    Text(
                      'Solde : ${formatFcfa(current.balance)}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: negative ? Theme.of(context).colorScheme.error : null,
                          ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: MovementsList(uid: me.uid)),
            ],
          );
        },
      ),
    );
  }
}
