import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/cash.dart';

DateTime _date(Object? v) => v is Timestamp
    ? v.toDate()
    : v is DateTime
        ? v
        : DateTime.fromMillisecondsSinceEpoch(0);

/// Ligne de `cashMovements` (spec §11.2), jamais modifiée.
class CashMovement {
  const CashMovement({
    required this.id,
    required this.kindCode,
    required this.amount,
    required this.date,
    required this.userUid,
    required this.note,
    required this.correctsId,
    required this.imported,
    required this.by,
    required this.at,
  });

  final String id;
  final String kindCode;
  final int amount; // signé : positif = entrée
  final String date; // « AAAA-MM-JJ », jour de l'opération
  final String? userUid;
  final String? note;
  final String? correctsId;
  final bool imported;
  final String by; // uid ou 'import'
  final DateTime at;

  CashKind? get kind => CashKind.fromCode(kindCode);

  /// Minuit (heure locale) du jour de l'opération.
  DateTime get day => DateTime.parse(date);
  bool get isCorrection => correctsId != null;

  factory CashMovement.fromMap(String id, Map<String, dynamic> m) => CashMovement(
        id: id,
        kindCode: (m['kind'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        date: (m['date'] as String?) ?? '1970-01-01',
        userUid: m['userUid'] as String?,
        note: m['note'] as String?,
        correctsId: m['correctsId'] as String?,
        imported: m['imported'] == true,
        by: (m['by'] as String?) ?? '',
        at: _date(m['at']),
      );
}

/// `cashbox/main` : solde et état de la reprise (spec §11.2).
class Cashbox {
  const Cashbox({required this.balance, required this.migrationClosedAt});
  final int balance;
  final DateTime? migrationClosedAt;
  bool get migrationClosed => migrationClosedAt != null;

  static const empty = Cashbox(balance: 0, migrationClosedAt: null);

  factory Cashbox.fromMap(Map<String, dynamic>? m) => m == null
      ? empty
      : Cashbox(
          balance: (m['balance'] as num?)?.toInt() ?? 0,
          migrationClosedAt: m['migrationClosedAt'] == null ? null : _date(m['migrationClosedAt']),
        );
}
