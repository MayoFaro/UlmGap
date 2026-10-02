// Carnet de vol (spec §5, révision du 2026-09-30) : règles pures de
// filtrage, de temps de vol et de période, testées sans widget.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/app_user.dart';
import '../../data/flight.dart';
import '../flight/flight_texts.dart';

/// Surlignage des vols à clôturer (orange des demandes).
final toCloseColor = statusColor(FlightStatus.demande);
const toCloseFill = Color(0xFFFFF3E0);

/// Vol du carnet : validé, non supprimé, départ le jour même ou avant
/// (date ≤ aujourd'hui, clôturé ou non).
bool isPerformed(Flight f, DateTime now) =>
    !f.deleted &&
    f.status == FlightStatus.valide &&
    !dayOf(f.start).isAfter(dayOf(now));

/// Vol effectué non clôturé : même règle que l'action « Clôturer »
/// (la date seule compte, pas l'heure).
bool needsClosing(Flight f, DateTime now) => isPerformed(f, now) && !f.isClosed;

/// Instructeurs et admins voient tout ; les autres, les vols dont ils sont
/// membres de l'équipage.
bool visibleTo(Flight f, AppUser me) =>
    me.isAdmin || me.isInstructor || f.crew.contains(me.uid);

/// Vols du carnet visibles par [me] ; [pilotUid] restreint à un membre de
/// l'équipage (null : tous les pilotes, pour un instructeur ou un admin),
/// [aircraftId] à un appareil (null : tous). Du plus récent au plus ancien.
List<Flight> logbookList(
  Iterable<Flight> flights, {
  required AppUser me,
  required DateTime now,
  required String? pilotUid,
  String? aircraftId,
}) =>
    flights
        .where((f) =>
            isPerformed(f, now) &&
            visibleTo(f, me) &&
            (pilotUid == null || f.crew.contains(pilotUid)) &&
            (aircraftId == null || f.aircraftId == aircraftId))
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));

/// Minutes comptées pour [f] : 0 s'il n'est pas clôturé, s'il est supprimé
/// ou s'il n'a pas de durée réelle.
int countedMinutes(Flight f) =>
    f.isClosed && !f.deleted ? (f.actualFlightMinutes ?? 0) : 0;

/// Temps de vol total des vols clôturés de [flights], chaque vol une fois.
int totalMinutes(Iterable<Flight> flights) =>
    flights.fold(0, (sum, f) => sum + countedMinutes(f));

/// Plan 4b : atterrissages et amerrissages des vols clôturés non supprimés
/// (0 pour un vol clôturé avant le plan 4b).
({int landings, int waterLandings}) totalLandings(Iterable<Flight> flights) {
  var landings = 0;
  var waterLandings = 0;
  for (final f in flights) {
    if (!f.isClosed || f.deleted) continue;
    landings += f.landings ?? 0;
    waterLandings += f.waterLandings ?? 0;
  }
  return (landings: landings, waterLandings: waterLandings);
}

/// Bornes [from, to[ d'un mois (1 à 12) de [year], ou de l'année entière
/// si [month] vaut 0.
({DateTime from, DateTime to}) monthPeriod(int year, int month) => month == 0
    ? (from: DateTime(year), to: DateTime(year + 1))
    : (from: DateTime(year, month), to: DateTime(year, month + 1));

/// Première année proposée : mise en service de l'app.
const firstLogbookYear = 2026;

/// Années proposées, de l'année en cours à [firstLogbookYear].
List<int> logbookYears(DateTime now) => [
      for (var y = now.year; y >= firstLogbookYear; y--) y,
    ];

/// Mention à droite de chaque vol du carnet.
String performedLabel(Flight f, DateTime now) {
  if (!f.isClosed) return 'À clôturer';
  final base = 'Clôturé · ${formatDurationHm(f.actualFlightMinutes ?? 0)}';
  final counts = landingsText(f.landings, f.waterLandings);
  return counts.isEmpty ? base : '$base · $counts';
}

String toCloseCountText(int n) => n == 1 ? '1 vol à clôturer' : '$n vols à clôturer';
