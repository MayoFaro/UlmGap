import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/flight_api.dart';
import '../../data/services.dart';
import 'flight_card.dart';
import 'flight_tile.dart';

/// Accueil : vols à partir d'aujourd'hui, groupés par jour (corps de HomeShell).
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key, required this.me, this.now = DateTime.now, this.onOpen});

  final AppUser me;
  final DateTime Function() now;

  /// Ouverture d'un vol (branchée par HomeShell vers le détail, Task 10).
  final void Function(Flight flight)? onOpen;

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

/// Une colonne du planning : un appareil, avec l'en-tête à afficher.
class _AircraftColumn {
  const _AircraftColumn(this.aircraftId, this.header);
  final String aircraftId;
  final String header;
}

/// Appareils actifs triés par libellé, puis tout aircraftId présent dans les
/// vols et absent de cette liste (en-tête = immatriculation du vol).
List<_AircraftColumn> _columnsFor(List<Aircraft> aircraft, List<Flight> flights) {
  final active = aircraft.where((a) => a.active).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  final knownIds = active.map((a) => a.id).toSet();
  final columns = [
    for (final a in active) _AircraftColumn(a.id, '${a.label} (${a.registration})'),
  ];
  final extraSeen = <String>{};
  for (final f in flights) {
    if (!knownIds.contains(f.aircraftId) && extraSeen.add(f.aircraftId)) {
      columns.add(_AircraftColumn(f.aircraftId, f.aircraft));
    }
  }
  return columns;
}

class _PlanningScreenState extends State<PlanningScreen> {
  FlightApi? _api;
  Stream<List<Flight>>? _flights;
  Stream<List<CrewMember>>? _dir;
  Stream<List<Aircraft>>? _aircraft;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppServices.of(context).flights!;
    if (!identical(_api, api)) {
      _api = api;
      _flights = api.watchFrom(dayOf(widget.now()));
      _dir = api.watchDirectory();
      _aircraft = api.watchAircraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CrewMember>>(
      stream: _dir,
      builder: (context, dirSnap) {
        final dir = {for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m};
        return StreamBuilder<List<Aircraft>>(
          stream: _aircraft,
          builder: (context, acSnap) => StreamBuilder<List<Flight>>(
            stream: _flights,
            builder: (context, snap) =>
                _body(snap, dir, acSnap.data ?? const <Aircraft>[]),
          ),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<List<Flight>> snap, Map<String, CrewMember> dir,
      List<Aircraft> aircraft) {
    final now = widget.now();
    final me = widget.me;
    final flights = (snap.data ?? const <Flight>[]).where((f) => !f.deleted).toList();
    final state = asyncState(snap, isEmpty: flights.isEmpty, empty: 'Aucun vol à venir.');

    final toValidate = flights
        .where((f) =>
            f.status == FlightStatus.demande &&
            !f.isExpiredRequest(now) &&
            f.instructorUid == me.uid)
        .toList();
    final mineList = flights
        .where((f) => f.createdBy == me.uid && f.effectiveStatus(now) != FlightStatus.valide)
        .toList();

    Widget tile(Flight f) => FlightTile(
          flight: f,
          dir: dir,
          now: now,
          mine: f.crew.contains(me.uid),
          onTap: () => widget.onOpen?.call(f),
        );
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        );

    return ListView(
      children: [
        if (state != null)
          state
        else ...[
          if (toValidate.isNotEmpty) ...[header('À valider'), ...toValidate.map(tile)],
          if (mineList.isNotEmpty) ...[header('Mes demandes'), ...mineList.map(tile)],
          _grid(context, flights, dir, aircraft, now, me, header),
        ],
      ],
    );
  }

  /// Grille jour par jour, une colonne par appareil, défilement horizontal
  /// unique pour que tous les jours défilent ensemble.
  Widget _grid(
    BuildContext context,
    List<Flight> flights,
    Map<String, CrewMember> dir,
    List<Aircraft> aircraft,
    DateTime now,
    AppUser me,
    Widget Function(String) header,
  ) {
    final columns = _columnsFor(aircraft, flights);
    if (columns.isEmpty) return const SizedBox.shrink();

    final byDay = <DateTime, List<Flight>>{};
    for (final f in flights) {
      byDay.putIfAbsent(dayOf(f.start), () => []).add(f);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final colWidth = columns.length <= 1 ? w : math.max((w - 8) / 2, 160.0);
        final gridWidth = columns.length <= 1
            ? w
            : colWidth * columns.length + 8.0 * (columns.length - 1);

        Widget rowOf(List<Widget> cells) {
          final children = <Widget>[];
          for (var i = 0; i < cells.length; i++) {
            if (i > 0) children.add(const SizedBox(width: 8));
            children.add(cells[i]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        }

        Widget cell(_AircraftColumn col, {String? headerText, List<Flight>? dayFlights}) {
          Widget content;
          if (headerText != null) {
            content = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                headerText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            );
          } else {
            final dayList = (dayFlights ?? const <Flight>[])
                .where((f) => f.aircraftId == col.aircraftId)
                .toList()
              ..sort((a, b) => a.start.compareTo(b.start));
            content = dayList.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('—', style: TextStyle(color: Colors.grey)),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in dayList)
                        FlightCard(
                          flight: f,
                          dir: dir,
                          now: now,
                          mine: f.crew.contains(me.uid),
                          onTap: () => widget.onOpen?.call(f),
                        ),
                    ],
                  );
          }
          return SizedBox(
            key: Key('col-${col.aircraftId}'),
            width: colWidth,
            child: content,
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rowOf([for (final c in columns) cell(c, headerText: c.header)]),
                for (final day in byDay.keys) ...[
                  SizedBox(width: gridWidth, child: header(formatDay(day))),
                  rowOf([for (final c in columns) cell(c, dayFlights: byDay[day])]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
