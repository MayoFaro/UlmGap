// Panneau « Vols effectués » (spec §5, plan 4) : seul accès aux vols passés,
// donc à la clôture (l'action « Clôturer » est dans FlightScreen).
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../core/period_bar.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/finance_api.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_screen.dart';
import 'performed.dart';
import 'performed_flight_tile.dart';

class PerformedFlightsScreen extends StatefulWidget {
  const PerformedFlightsScreen({
    super.key,
    required this.me,
    this.now = DateTime.now,
    this.onOpen,
  });

  final AppUser me;
  final DateTime Function() now;

  /// Ouverture d'un vol ; par défaut, FlightScreen.
  final void Function(Flight flight)? onOpen;

  @override
  State<PerformedFlightsScreen> createState() => _PerformedFlightsScreenState();
}

class _PerformedFlightsScreenState extends State<PerformedFlightsScreen> {
  // [_to] est exclusif (comme FinanceApi.watchFlightsBetween).
  late DateTime _from;
  late DateTime _to;
  String? _aircraftId; // null : tous les appareils
  bool _onlyToClose = false;

  FinanceApi? _finance;
  Stream<List<Flight>>? _periodFlights;
  Stream<List<Flight>>? _unclosed;
  Stream<List<CrewMember>>? _dir;
  Stream<List<Aircraft>>? _aircraft;

  @override
  void initState() {
    super.initState();
    final n = widget.now();
    _from = DateTime(n.year, n.month);
    _to = DateTime(n.year, n.month, n.day + 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    final finance = services.finance!;
    if (!identical(_finance, finance)) {
      _finance = finance;
      _periodFlights = finance.watchFlightsBetween(_from, _to);
      _unclosed = finance.watchValidUnclosedFlights();
      _dir = services.flights!.watchDirectory();
      _aircraft = services.flights!.watchAircraft();
    }
  }

  void _setPeriod(DateTime from, DateTime to) => setState(() {
        _from = from;
        _to = to;
        _periodFlights = _finance!.watchFlightsBetween(from, to);
      });

  void _open(Flight f) {
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen(f);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlightScreen(me: widget.me, flight: f),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vols effectués')),
        body: StreamBuilder<List<CrewMember>>(
          stream: _dir,
          builder: (context, dirSnap) {
            final dir = {for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m};
            return StreamBuilder<List<Aircraft>>(
              stream: _aircraft,
              builder: (context, acSnap) => StreamBuilder<List<Flight>>(
                stream: _unclosed,
                builder: (context, unclosedSnap) => StreamBuilder<List<Flight>>(
                  stream: _periodFlights,
                  builder: (context, periodSnap) => _body(
                      dir, acSnap.data ?? const <Aircraft>[], unclosedSnap, periodSnap),
                ),
              ),
            );
          },
        ),
      );

  Widget _body(Map<String, CrewMember> dir, List<Aircraft> aircraft,
      AsyncSnapshot<List<Flight>> unclosedSnap, AsyncSnapshot<List<Flight>> periodSnap) {
    final now = widget.now();
    final me = widget.me;
    final toClose = performedList(unclosedSnap.data ?? const <Flight>[],
            me: me, now: now, aircraftId: _aircraftId)
        .where((f) => needsClosing(f, now))
        .toList();
    final shown = _onlyToClose
        ? toClose
        : performedList(periodSnap.data ?? const <Flight>[],
            me: me, now: now, aircraftId: _aircraftId);
    final state = asyncState(
      _onlyToClose ? unclosedSnap : periodSnap,
      isEmpty: shown.isEmpty,
      empty: _onlyToClose ? 'Aucun vol à clôturer.' : 'Aucun vol effectué sur cette période.',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeriodBar(
          from: _from,
          to: _to,
          lastDay: dayOf(now),
          enabled: !_onlyToClose,
          onChanged: _setPeriod,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String?>(
                key: const Key('aircraft-filter'),
                // Appareil disparu de la liste : retour à « Tous » plutôt
                // qu'une assertion de DropdownButton.
                value: aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : null,
                onChanged: (v) => setState(() => _aircraftId = v),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tous les appareils')),
                  for (final a in aircraft)
                    DropdownMenuItem<String?>(
                        value: a.id, child: Text('${a.label} (${a.registration})')),
                ],
              ),
              FilterChip(
                key: const Key('only-to-close'),
                label: const Text('À clôturer seulement'),
                selected: _onlyToClose,
                onSelected: (v) => setState(() => _onlyToClose = v),
              ),
            ],
          ),
        ),
        if (toClose.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              toCloseCountText(toClose.length),
              key: const Key('to-close-count'),
              style: TextStyle(color: toCloseColor, fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: state ??
              ListView(children: [
                for (final f in shown)
                  PerformedFlightTile(flight: f, dir: dir, now: now, onTap: () => _open(f)),
              ]),
        ),
      ],
    );
  }
}
