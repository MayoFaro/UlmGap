// Historique d'un compte (écrans « Mon compte » et « Instructeurs »).
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../data/account_movement.dart';
import '../../data/flight.dart';
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

/// Libellé d'un mouvement : type, date du vol s'il est connu (« Vol du
/// lundi 12 octobre », « Régularisation — vol du … »), puis la raison si elle
/// n'est pas redondante avec le type.
String movementTitle(AccountMovement m, {DateTime? flightStart}) {
  final type = movementTypeLabel(m.type);
  final title = flightStart == null
      ? type
      : m.type == 'flight'
          ? 'Vol du ${formatDay(flightStart)}'
          : '$type — vol du ${formatDay(flightStart)}';
  final reason = m.reason;
  return reason == null || reason.isEmpty || reason == type ? title : '$title — $reason';
}

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
          itemBuilder: (context, i) => _MovementTile(movements[i]),
        );
      },
    );
  }
}

/// Une ligne de l'historique ; la date du vol lié est lue une seule fois
/// (les vols sont lisibles par tout utilisateur connecté).
class _MovementTile extends StatefulWidget {
  const _MovementTile(this.movement);
  final AccountMovement movement;

  @override
  State<_MovementTile> createState() => _MovementTileState();
}

class _MovementTileState extends State<_MovementTile> {
  Future<Flight?>? _flight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = widget.movement.flightId;
    final flights = AppServices.of(context).flights;
    if (_flight == null && id != null && flights != null) {
      _flight = flights.watchFlight(id).first.then<Flight?>((f) => f, onError: (Object _) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movement;
    final positive = m.amount > 0;
    final color = positive ? const Color(0xFF2E7D32) : Theme.of(context).colorScheme.error;
    return FutureBuilder<Flight?>(
      future: _flight,
      builder: (context, snap) => ListTile(
        title: Text(movementTitle(m, flightStart: snap.data?.start)),
        subtitle: Text('${formatDay(m.at)}, ${formatTime(m.at)} · '
            'Solde : ${formatFcfa(m.balanceAfter)}'),
        trailing: Text(
          signedFcfa(m.amount),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
