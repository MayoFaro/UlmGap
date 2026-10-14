// Caisse (spec §11) : types d'opération, libellés, icônes, période et
// totaux. Miroir de functions/src/rules/cash.ts.
import 'package:flutter/material.dart';

import '../data/cash_movement.dart';

enum CashKind {
  fuelCredit('fuel_credit', 'Crédit carburant', Icons.payments, 1),
  fuelPurchase('fuel_purchase', 'Achat carburant', Icons.local_gas_station, -1),
  maintenance('maintenance', 'Maintenance', Icons.build, -1),
  offAppIncome('off_app_income', 'Recette hors app', Icons.receipt_long, 1),
  cashGap('cash_gap', 'Écart de caisse', Icons.balance, 0),
  opening('opening', 'Fond initial', Icons.savings, 1);

  const CashKind(this.code, this.label, this.icon, this.sign);
  final String code;
  final String label;
  final IconData icon;

  /// 1 : entrée, −1 : sortie, 0 : les deux (écart de caisse).
  final int sign;

  static CashKind? fromCode(String code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }

  /// Puces de filtre de l'écran Caisse (le Fond initial n'en a pas).
  static const filters = [fuelCredit, fuelPurchase, maintenance, offAppIncome, cashGap];
}

String _two(int n) => n.toString().padLeft(2, '0');

/// « 2026-10-14 » (jour de [d], heure locale).
String cashDayCode(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Montant juste actuel d'une opération : son montant + ses corrections.
int effectiveAmount(CashMovement original, List<CashMovement> all) => all
    .where((m) => m.correctsId == original.id)
    .fold(original.amount, (s, m) => s + m.amount);

/// Opérations dont le jour tombe dans [from, to[, des types [kinds] (vide :
/// toutes), de la plus récente à la plus ancienne (jour, puis saisie).
List<CashMovement> cashPeriod(
    List<CashMovement> all, DateTime from, DateTime to, Set<CashKind> kinds) {
  final out = all
      .where((m) => !m.day.isBefore(from) && m.day.isBefore(to))
      .where((m) => kinds.isEmpty || kinds.contains(m.kind))
      .toList()
    ..sort((a, b) {
      final byDay = b.date.compareTo(a.date);
      return byDay != 0 ? byDay : b.at.compareTo(a.at);
    });
  return out;
}

/// Entrées (≥ 0) et sorties (≤ 0) : selon le sens du type, corrections
/// comprises ; un écart de caisse selon son signe.
({int entries, int exits}) cashTotals(Iterable<CashMovement> ms) {
  var entries = 0, exits = 0;
  for (final m in ms) {
    final sign = m.kind?.sign ?? 0;
    final isEntry = sign == 1 || (sign == 0 && m.amount > 0);
    if (isEntry) {
      entries += m.amount;
    } else {
      exits += m.amount;
    }
  }
  return (entries: entries, exits: exits);
}

/// « Crédit carburant LCM », « Maintenance »…
String cashTitle(CashMovement m, Map<String, String> shortNames) {
  final label = m.kind?.label ?? m.kindCode;
  final uid = m.userUid;
  if (m.kind == CashKind.fuelCredit && uid != null) return '$label ${shortNames[uid] ?? '?'}';
  return label;
}
