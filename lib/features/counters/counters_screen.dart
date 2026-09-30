// Écran « Compteurs » (spec §5) : total d'heures d'un pilote ou d'un
// appareil sur une période (année en cours par défaut, commune aux deux
// onglets). Base : vols clôturés non supprimés (counters.dart).
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/period_bar.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/finance_api.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_texts.dart';
import 'counters.dart';

class CountersScreen extends StatefulWidget {
  const CountersScreen({super.key, required this.me, this.now = DateTime.now});
  final AppUser me;
  final DateTime Function() now;

  @override
  State<CountersScreen> createState() => _CountersScreenState();
}

class _CountersScreenState extends State<CountersScreen> {
  // [_to] est exclusif (comme FinanceApi.watchFlightsBetween).
  late DateTime _from;
  late DateTime _to;
  late String _pilotUid;
  String? _aircraftId; // null : premier appareil actif

  FinanceApi? _finance;
  Stream<List<Flight>>? _flights;
  Stream<List<CrewMember>>? _dir;
  Stream<List<Aircraft>>? _aircraft;

  bool get _canChoosePilot => widget.me.isAdmin || widget.me.isInstructor;

  @override
  void initState() {
    super.initState();
    final n = widget.now();
    _from = DateTime(n.year);
    _to = DateTime(n.year + 1);
    _pilotUid = widget.me.uid;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    final finance = services.finance!;
    if (!identical(_finance, finance)) {
      _finance = finance;
      _flights = finance.watchFlightsBetween(_from, _to);
      _dir = services.flights!.watchDirectory();
      _aircraft = services.flights!.watchAircraft();
    }
  }

  void _setPeriod(DateTime from, DateTime to) => setState(() {
        _from = from;
        _to = to;
        _flights = _finance!.watchFlightsBetween(from, to);
      });

  Widget _total(String key, int minutes) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Total : ${formatDurationHm(minutes)}',
          key: Key(key),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Compteurs'),
            bottom: const TabBar(tabs: [Tab(text: 'Pilote'), Tab(text: 'Appareil')]),
          ),
          body: Column(children: [
            PeriodBar(from: _from, to: _to, onChanged: _setPeriod),
            Expanded(
              child: StreamBuilder<List<Flight>>(
                stream: _flights,
                builder: (context, snap) {
                  if (snap.hasError) return connectionErrorMessage();
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final flights = snap.data!;
                  return TabBarView(children: [_pilotTab(flights), _aircraftTab(flights)]);
                },
              ),
            ),
          ]),
        ),
      );

  Widget _pilotTab(List<Flight> flights) => StreamBuilder<List<CrewMember>>(
        stream: _dir,
        builder: (context, snap) {
          final dir = snap.data ?? const <CrewMember>[];
          final selector = !_canChoosePilot
              ? Text('Pilote : ${widget.me.shortName}')
              : DropdownButton<String>(
                  key: const Key('pilot-select'),
                  // Annuaire pas encore chargé (ou sans ce compte) : pas de
                  // valeur plutôt qu'une assertion de DropdownButton.
                  value: dir.any((m) => m.uid == _pilotUid) ? _pilotUid : null,
                  hint: Text(widget.me.shortName),
                  onChanged: (v) => setState(() => _pilotUid = v ?? _pilotUid),
                  items: [
                    for (final m in dir)
                      DropdownMenuItem(value: m.uid, child: Text('${m.shortName} · ${m.displayName}')),
                  ],
                );
          return ListView(padding: const EdgeInsets.all(16), children: [
            selector,
            _total('pilot-total', pilotMinutes(flights, _pilotUid)),
          ]);
        },
      );

  Widget _aircraftTab(List<Flight> flights) => StreamBuilder<List<Aircraft>>(
        stream: _aircraft,
        builder: (context, snap) {
          final aircraft = snap.data ?? const <Aircraft>[];
          if (snap.hasData && aircraft.isEmpty) {
            return const Center(child: Text('Aucun appareil.'));
          }
          String? fallback() {
            for (final a in aircraft) {
              if (a.active) return a.id;
            }
            return aircraft.isEmpty ? null : aircraft.first.id;
          }

          final selected =
              aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : fallback();
          return ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButton<String>(
              key: const Key('aircraft-select'),
              value: selected,
              onChanged: (v) => setState(() => _aircraftId = v),
              items: [
                for (final a in aircraft)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.label} (${a.registration})${a.active ? '' : ' (inactif)'}'),
                  ),
              ],
            ),
            if (selected != null) _total('aircraft-total', aircraftMinutes(flights, selected)),
          ]);
        },
      );
}
