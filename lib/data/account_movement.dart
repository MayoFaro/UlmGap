import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _date(Object? v) => v is Timestamp
    ? v.toDate()
    : v is DateTime
        ? v
        : DateTime.fromMillisecondsSinceEpoch(0);

/// Ligne de `transactions` (règle absolue : toute écriture de `users.balance`
/// s'accompagne d'une ligne ici, dans la même transaction Firestore).
class AccountMovement {
  const AccountMovement({
    required this.id,
    required this.userUid,
    required this.amount,
    required this.type,
    required this.reason,
    required this.flightId,
    required this.by,
    required this.at,
    required this.balanceAfter,
  });

  final String id;
  final String userUid;
  final int amount; // positif pour un crédit
  final String type; // 'credit' | 'correction' | 'flight' | 'flight_adjustment' | 'instruction'
  final String? reason;
  final String? flightId;
  final String by; // uid ou 'system'
  final DateTime at;
  final int balanceAfter;

  factory AccountMovement.fromMap(String id, Map<String, dynamic> m) => AccountMovement(
        id: id,
        userUid: (m['userUid'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        type: (m['type'] as String?) ?? '',
        reason: m['reason'] as String?,
        flightId: m['flightId'] as String?,
        by: (m['by'] as String?) ?? '',
        at: _date(m['at']),
        balanceAfter: (m['balanceAfter'] as num?)?.toInt() ?? 0,
      );
}
