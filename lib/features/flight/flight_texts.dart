// SEUL endroit des libellés et couleurs de statut et de mode.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/flight_api.dart';

String statusLabel(FlightStatus s) => switch (s) {
      FlightStatus.demande => 'Demande',
      FlightStatus.valide => 'Validé',
      FlightStatus.refuse => 'Refusé',
    };

Color statusColor(FlightStatus s) => switch (s) {
      FlightStatus.demande => const Color(0xFFEF6C00),
      FlightStatus.valide => const Color(0xFF2E7D32),
      FlightStatus.refuse => Colors.grey,
    };

String pricingModeLabel(String mode) => switch (mode) {
      'fuel_only' => 'Carburant seulement',
      'custom' => 'Facturé hors app',
      _ => 'Standard',
    };

/// « DPS/LDX », passagers sans compte compris.
String crewText(List<String> crew, List<String> passengers, Map<String, CrewMember> dir) =>
    [...crew.map((u) => dir[u]?.shortName ?? '?'), ...passengers].join('/');

/// Libellé du compte débité (anciennement « Payeur »).
const debitedLabel = 'Compte débité';

/// Mise en évidence des vols où l'utilisateur est dans l'équipage.
const highlightFill = Color(0xFFE3F2FD);
const highlightBorder = Color(0xFF1E88E5);

/// Explique la cause d'un conflit : appareil (prioritaire) ou personne commune.
String describeConflict(ConflictInfo c, Map<String, CrewMember> dir) {
  final when = '${formatDay(c.start)}, ${formatRange(c.start, c.end)}';
  final crew = crewText(c.crew, c.passengers, dir);
  if (c.kind == 'crew') {
    final members = c.members.map((u) => dir[u]?.shortName ?? '?').join('/');
    return 'Conflit : $members est déjà sur le vol du $when (${c.aircraft}, $crew).';
  }
  return 'Conflit : ${c.aircraft} est déjà réservé sur le vol du $when ($crew).';
}
