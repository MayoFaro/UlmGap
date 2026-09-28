import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/flight_api.dart';
import '../../data/services.dart';
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

class _PlanningScreenState extends State<PlanningScreen> {
  String? _aircraftId; // filtre ; null = tous
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
    final flights = (snap.data ?? const <Flight>[])
        .where((f) => !f.deleted && (_aircraftId == null || f.aircraftId == _aircraftId))
        .toList();
    final state = asyncState(snap, isEmpty: flights.isEmpty, empty: 'Aucun vol à venir.');

    final toValidate = flights
        .where((f) =>
            f.status == FlightStatus.demande &&
            !f.isExpiredRequest(now) &&
            f.instructorUid == me.uid)
        .toList();
    final mine = flights
        .where((f) => f.createdBy == me.uid && f.effectiveStatus(now) != FlightStatus.valide)
        .toList();
    final byDay = <DateTime, List<Flight>>{};
    for (final f in flights) {
      byDay.putIfAbsent(dayOf(f.start), () => []).add(f);
    }

    Widget tile(Flight f) =>
        FlightTile(flight: f, dir: dir, now: now, onTap: () => widget.onOpen?.call(f));
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        );

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButton<String?>(
            key: const Key('aircraft-filter'),
            value: _aircraftId,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Tous les appareils')),
              for (final a in aircraft)
                DropdownMenuItem<String?>(value: a.id, child: Text(a.label)),
            ],
            onChanged: (v) => setState(() => _aircraftId = v),
          ),
        ),
        if (state != null)
          state
        else ...[
          if (toValidate.isNotEmpty) ...[header('À valider'), ...toValidate.map(tile)],
          if (mine.isNotEmpty) ...[header('Mes demandes'), ...mine.map(tile)],
          for (final day in byDay.keys) ...[
            header(formatDay(day)),
            ...byDay[day]!.map(tile),
          ],
        ],
      ],
    );
  }
}
