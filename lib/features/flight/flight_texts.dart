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

String describeConflict(ConflictInfo c, Map<String, CrewMember> dir) =>
    'Conflit avec le vol du ${formatDay(c.start)}, ${formatRange(c.start, c.end)}, '
    '${c.aircraft}, ${crewText(c.crew, c.passengers, dir)}.';
