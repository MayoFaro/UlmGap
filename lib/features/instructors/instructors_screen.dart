// Écran « Instructeurs » (instructeurs et admins) : liste des comptes avec
// leur solde ; un appui ouvre l'historique du compte et « Créditer / corriger ».
import 'package:flutter/material.dart';

import '../../core/profiles.dart';
import '../../core/async_state.dart';
import '../../core/money.dart';
import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import '../account/movements_list.dart';
import 'credit_dialog.dart';
import '../home/app_nav.dart';

class InstructorsScreen extends StatelessWidget {
  const InstructorsScreen({super.key, this.me});

  /// Compte connecté : icônes de navigation (absentes si null).
  final AppUser? me;

  @override
  Widget build(BuildContext context) {
    final finance = AppServices.of(context).finance!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilotes'),
        actions: me == null ? null : appNavActions(context, me!, current: AppDestination.instructors),
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: finance.watchAccounts(),
        builder: (context, snap) {
          final accounts = sortedByProfile(
              snap.data ?? const <AppUser>[], (a) => a.profile, (a) => a.displayName);
          final state = asyncState(snap, isEmpty: accounts.isEmpty, empty: 'Aucun compte.');
          if (state != null) return state;
          return ListView(
            children: [
              for (final a in accounts)
                ListTile(
                  leading: ProfileBadge(profile: a.profile, compact: true),
                  title: Text(a.displayName),
                  subtitle: Text('${a.shortName} · ${a.category.code}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      formatFcfa(a.balance),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: a.balance < 0 ? Theme.of(context).colorScheme.error : null,
                      ),
                    ),
                    // Écran réservé aux instructeurs et aux admins (icône
                    // « Pilotes ») ; le serveur refuse le crédit à tout autre.
                    IconButton(
                      key: Key('credit-${a.uid}'),
                      tooltip: 'Créditer',
                      icon: const Icon(Icons.payments),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => CreditDialog(uid: a.uid, balance: a.balance),
                      ),
                    ),
                  ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _AccountDetailScreen(account: a, me: me),
                  )),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Historique d'un compte et bouton « Créditer / corriger », ouverts depuis
/// la liste ci-dessus.
class _AccountDetailScreen extends StatelessWidget {
  const _AccountDetailScreen({required this.account, this.me});
  final AppUser account; // valeur initiale, tant que le flux n'a pas émis.
  final AppUser? me;

  @override
  Widget build(BuildContext context) {
    final finance = AppServices.of(context).finance!;
    // Fix round 1 (revue de la Task 11) : le solde de l'en-tête venait de
    // l'AppUser figé au moment de la navigation, en désaccord avec
    // MovementsList (en direct) après un crédit ou une correction. On relit
    // désormais `watchAccounts()`, filtré sur ce compte, avec repli sur
    // `account` tant que le flux n'a pas encore émis.
    return StreamBuilder<List<AppUser>>(
      stream: finance.watchAccounts(),
      builder: (context, snap) {
        AppUser? found;
        for (final a in snap.data ?? const <AppUser>[]) {
          if (a.uid == account.uid) {
            found = a;
            break;
          }
        }
        final current = found ?? account;
        return Scaffold(
          appBar: AppBar(
            title: Text(current.displayName),
            actions: me == null ? null : appNavActions(context, me!),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Solde : ${formatFcfa(current.balance)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: current.balance < 0 ? Theme.of(context).colorScheme.error : null,
                      ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: MovementsList(uid: current.uid)),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.payments),
            label: const Text('Créditer / corriger'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CreditDialog(uid: current.uid, balance: current.balance),
            ),
          ),
        );
      },
    );
  }
}
