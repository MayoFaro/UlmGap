// Écran « Mon compte » (accessible à tous) : profil, appartenance, solde et
// historique des mouvements de l'utilisateur connecté.
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import 'movements_list.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.me});
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final negative = me.balance < 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(me.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  ProfileBadge(profile: me.profile),
                ]),
                const SizedBox(height: 4),
                Text(me.category.code),
                const SizedBox(height: 8),
                Text(
                  'Solde : ${formatFcfa(me.balance)}',
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
      ),
    );
  }
}
