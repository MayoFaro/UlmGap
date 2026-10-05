// SEUL endroit des libellés et couleurs de statut et de mode.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/fuel.dart';
import '../../core/money.dart';
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
      'baptism' => 'Baptême de l\'air',
      _ => 'Standard',
    };

/// Plan 9 : forfait de baptême (local par défaut, comme la facturation).
String baptismTierLabel(String? tier) => switch (tier) {
      'nyonye' => 'Nyonye',
      'awagne' => 'Awagne',
      _ => 'Local',
    };

/// Mode de tarification d'un vol, avec le forfait en cas de baptême.
String flightPricingLabel(String mode, String? baptismTier) =>
    mode == 'baptism' ? 'Baptême ${baptismTierLabel(baptismTier)}' : pricingModeLabel(mode);

/// « DPS/LDX », passagers sans compte compris.
String crewText(List<String> crew, List<String> passengers, Map<String, CrewMember> dir) =>
    [...crew.map((u) => dir[u]?.shortName ?? '?'), ...passengers].join('/');

/// Confirmation d'un enregistrement de vol, d'après le statut rendu par le
/// serveur (le vol est alors bien dans Firestore).
String savedMessage(FlightStatus status, String? instructorShortName, {required bool created}) {
  final to = instructorShortName == null ? 'à l\'instructeur' : 'à $instructorShortName';
  if (status == FlightStatus.demande) {
    return created ? 'Demande envoyée $to.' : 'Demande modifiée, envoyée $to.';
  }
  return created ? 'Vol enregistré.' : 'Modifications enregistrées.';
}

/// Pas de réponse du serveur (hors ligne, coupure, délai) : l'opération a pu
/// aboutir ou non ; on ne peut pas le savoir côté app.
const uncertainMessage = 'Pas de réponse du serveur. Vérifiez votre connexion, puis le '
    'planning avant de recommencer : l\'opération a pu aboutir.';

/// Libellé du compte débité (anciennement « Payeur »).
const debitedLabel = 'Compte débité';

/// Mise en évidence des vols où l'utilisateur est dans l'équipage.
const highlightFill = Color(0xFFE3F2FD);
const highlightBorder = Color(0xFF1E88E5);

/// Vol refusé (ou demande expirée) : carte grisée, jamais surlignée.
const refusedFill = Color(0xFFEEEEEE);
const refusedBorder = Color(0xFFBDBDBD);

/// « 1 h 30 », « 0 h 45 » (Task 9 : durée réelle d'un vol clôturé).
String formatDurationHm(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '$h h ${m.toString().padLeft(2, '0')}';
}

/// « 2 att. » ou « 2 att. · 1 am. » ; vide pour un vol clôturé avant le
/// plan 4b (sans nombres).
String landingsText(int? landings, int? waterLandings, {String separator = ' · '}) {
  if (landings == null) return '';
  final water = waterLandings ?? 0;
  return water > 0 ? '$landings att.$separator$water am.' : '$landings att.';
}

/// En tête de fenêtre pour un vol clôturé (Task 9, spec plan 3 §4.3 ;
/// atterrissages et amerrissages au plan 4b).
String closedSummary({
  required int actualMinutes,
  required int billedAmount,
  required String billedTo,
  required String debitedShortName,
  int? landings,
  int? waterLandings,
}) {
  final duration = formatDurationHm(actualMinutes);
  final amount = formatFcfa(billedAmount);
  final base = billedTo == 'off_app'
      ? 'Clôturé : $duration, $amount facturé hors app'
      : 'Clôturé : $duration, $amount débité sur le compte de $debitedShortName';
  final counts = landingsText(landings, waterLandings, separator: ', ');
  return counts.isEmpty ? base : '$base, $counts';
}

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

/// Plan 7 (spec §9.4) : carburant déclaré à la clôture.
String fuelSummary(Flight f) {
  final base = 'Carburant : départ ${fuelText(f.fuelStartLiters)} · '
      'ajouté ${fuelText(f.fuelAddedLiters)} · rangé ${fuelText(f.fuelEndLiters)}';
  return fuelGap(f) ? '$base (prévu ${fuelText(f.fuelStartExpectedLiters)})' : base;
}
