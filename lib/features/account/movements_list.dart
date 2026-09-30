// Historique d'un compte (écrans « Mon compte » et « Instructeurs »).
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../data/account_movement.dart';
import '../../data/services.dart';

/// Libellé du type de mouvement (règle absolue : toute écriture de
/// `users.balance` a une ligne `transactions`, cf. account_movement.dart).
String movementTypeLabel(String type) => switch (type) {
      'credit' => 'Crédit',
      'correction' => 'Correction',
      'flight' => 'Vol',
      'flight_adjustment' => 'Régularisation',
      _ => type,
    };

/// Montant précédé de son signe (« +12 000 FCFA » / « −15 000 FCFA »).
String signedFcfa(int amount) => amount > 0 ? '+${formatFcfa(amount)}' : formatFcfa(amount);

/// Historique d'un compte, trié par date décroissante (voir
/// `FinanceApi.watchMovements`) : date et heure, libellé du type, raison,
/// montant signé (vert ou rouge) et solde après le mouvement.
class MovementsList extends StatelessWidget {
  const MovementsList({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final finance = AppServices.of(context).finance!;
    return StreamBuilder<List<AccountMovement>>(
      stream: finance.watchMovements(uid),
      builder: (context, snap) {
        final movements = snap.data ?? const <AccountMovement>[];
        final state = asyncState(snap, isEmpty: movements.isEmpty, empty: 'Aucun mouvement.');
        if (state != null) return state;
        return ListView.builder(
          itemCount: movements.length,
          itemBuilder: (context, i) {
            final m = movements[i];
            final positive = m.amount > 0;
            final color = positive ? const Color(0xFF2E7D32) : Theme.of(context).colorScheme.error;
            final reason = m.reason;
            return ListTile(
              title: Text(reason == null || reason.isEmpty
                  ? movementTypeLabel(m.type)
                  : '${movementTypeLabel(m.type)} — $reason'),
              subtitle: Text('${formatDay(m.at)}, ${formatTime(m.at)} · '
                  'Solde : ${formatFcfa(m.balanceAfter)}'),
              trailing: Text(
                signedFcfa(m.amount),
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            );
          },
        );
      },
    );
  }
}
