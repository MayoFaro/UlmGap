// Panneau « Vols effectués » (spec §5, plan 4) : règles pures de filtrage
// et libellés, testées sans widget.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/app_user.dart';
import '../../data/flight.dart';
import '../flight/flight_texts.dart';

/// Surlignage des vols à clôturer (orange des demandes).
final toCloseColor = statusColor(FlightStatus.demande);
const toCloseFill = Color(0xFFFFF3E0);

/// Vol affiché dans le panneau : validé, non supprimé, départ le jour même
/// ou avant (spec §5 : date ≤ aujourd'hui, clôturé ou non).
bool isPerformed(Flight f, DateTime now) =>
    !f.deleted &&
    f.status == FlightStatus.valide &&
    !dayOf(f.start).isAfter(dayOf(now));

/// Vol effectué non clôturé : même règle que l'action « Clôturer »
/// (décision 6 : la date seule compte, pas l'heure).
bool needsClosing(Flight f, DateTime now) => isPerformed(f, now) && !f.isClosed;

/// Décision 1 : instructeurs et admins voient tout ; les autres, les vols
/// dont ils sont membres de l'équipage.
bool visibleTo(Flight f, AppUser me) =>
    me.isAdmin || me.isInstructor || f.crew.contains(me.uid);

/// Vols effectués visibles par [me], sur [aircraftId] si donné, du plus
/// récent au plus ancien.
List<Flight> performedList(
  Iterable<Flight> flights, {
  required AppUser me,
  required DateTime now,
  String? aircraftId,
}) =>
    flights
        .where((f) =>
            isPerformed(f, now) &&
            visibleTo(f, me) &&
            (aircraftId == null || f.aircraftId == aircraftId))
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));

/// Mention à droite de chaque vol du panneau.
String performedLabel(Flight f, DateTime now) => f.isClosed
    ? 'Clôturé · ${formatDurationHm(f.actualFlightMinutes ?? 0)}'
    : 'À clôturer';

String toCloseCountText(int n) => n == 1 ? '1 vol à clôturer' : '$n vols à clôturer';
