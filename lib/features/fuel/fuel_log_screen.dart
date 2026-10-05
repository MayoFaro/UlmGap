// Écran « Suivi carburant » d'un appareil (spec §9.5), ouvert par tout
// utilisateur depuis le carburant affiché (CurrentFuelTile) ou depuis
// Administration → Appareils : tableau des vols clôturés de la période.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/fuel.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_screen.dart';
import '../flight/flight_texts.dart';
import '../home/app_nav.dart';
import '../logbook/period_selector.dart';

/// Écart au départ, conso inhabituelle (orange des vols à clôturer).
const fuelWarningColor = Color(0xFFEF6C00);

/// Fond de la case « Ajouté » quand du carburant a été ajouté.
const _addedFill = Color(0xFFBBDEFB);

/// « Carburant : 40 L » ; un appui ouvre le suivi carburant de l'appareil.
class CurrentFuelTile extends StatelessWidget {
  const CurrentFuelTile({super.key, required this.me, required this.aircraft});
  final AppUser me;
  final Aircraft aircraft;

  @override
  Widget build(BuildContext context) => ListTile(
        key: const Key('current-fuel'),
        leading: const Icon(Icons.local_gas_station),
        title: Text('Carburant : ${fuelText(aircraft.fuelLiters)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => FuelLogScreen(me: me, aircraftId: aircraft.id))),
      );
}

class FuelLogScreen extends StatefulWidget {
  const FuelLogScreen({
    super.key,
    required this.me,
    required this.aircraftId,
    this.now = DateTime.now,
    this.pickRange,
  });
  final AppUser me;
  final String aircraftId;
  final DateTime Function() now;

  /// Calendrier de période précise ; par défaut, showDateRangePicker.
  final RangePicker? pickRange;

  @override
  State<FuelLogScreen> createState() => _FuelLogScreenState();
}

class _FuelLogScreenState extends State<FuelLogScreen> {
  late ({DateTime from, DateTime to}) _period;

  @override
  void initState() {
    super.initState();
    _period = initialPeriod(widget.now());
  }

  @override
  Widget build(BuildContext context) {
    final api = AppServices.of(context).flights!;
    return StreamBuilder<List<Aircraft>>(
      stream: api.watchAircraft(),
      builder: (context, acSnap) {
        Aircraft? aircraft;
        for (final a in acSnap.data ?? const <Aircraft>[]) {
          if (a.id == widget.aircraftId) aircraft = a;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text('Suivi carburant · ${aircraft?.registration ?? ''}'),
            actions: appNavActions(context, widget.me),
          ),
          body: StreamBuilder<List<CrewMember>>(
            stream: api.watchDirectory(),
            builder: (context, dirSnap) {
              final dir = {for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m};
              return StreamBuilder<List<Flight>>(
                stream: api.watchAircraftFlights(widget.aircraftId),
                builder: (context, snap) =>
                    _body(context, aircraft, dir, snap.data ?? const <Flight>[]),
              );
            },
          ),
        );
      },
    );
  }

  Widget _body(
      BuildContext context, Aircraft? aircraft, Map<String, CrewMember> dir, List<Flight> all) {
    final closed = all.where((f) => f.isClosed && !f.deleted).toList();
    // Tendance sur tous les vols ; tableau et totaux sur la période.
    final stats = fuelStats(closed);
    final p = _period;
    final flights = closed.where((f) => !f.start.isBefore(p.from) && f.start.isBefore(p.to)).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    final showWater = (aircraft?.amphibious ?? false) || flights.any((f) => (f.waterLandings ?? 0) > 0);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Carburant actuel : ${fuelText(aircraft?.fuelLiters)}',
          style: Theme.of(context).textTheme.titleMedium),
      if (stats != null)
        Text('Consommation estimée : ${formatLitersPerHour(stats.litersPerHour)} '
            '(${stats.flights} vol${stats.flights > 1 ? 's' : ''}, '
            '${formatDurationHm(stats.minutes)})'),
      const SizedBox(height: 8),
      PeriodSelector(
        now: widget.now,
        pickRange: widget.pickRange,
        onChanged: (from, to) => setState(() => _period = (from: from, to: to)),
      ),
      const Divider(),
      if (flights.isEmpty)
        const Text('Aucun vol clôturé sur cette période.')
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columnSpacing: 16,
            columns: [
              const DataColumn(label: Text('Date')),
              const DataColumn(label: Text('Équipage')),
              const DataColumn(label: Text('Temps de vol')),
              const DataColumn(label: Text('Départ (L)'), numeric: true),
              const DataColumn(label: Text('Ajouté (L)'), numeric: true),
              const DataColumn(label: Text('Rangé (L)'), numeric: true),
              const DataColumn(label: Text('Conso (L)'), numeric: true),
              const DataColumn(label: Text('Conso (L/h)'), numeric: true),
              const DataColumn(label: Text('Att.'), numeric: true),
              if (showWater) const DataColumn(label: Text('Am.'), numeric: true),
            ],
            rows: [
              for (final f in flights) _row(context, f, dir, showWater),
              _totalRow(flights, showWater),
            ],
          ),
        ),
    ]);
  }

  Text _cell(String id, String col, String text, {TextStyle? style}) =>
      Text(text, key: Key('fuel-$id-$col'), style: style);

  DataRow _row(BuildContext context, Flight f, Map<String, CrewMember> dir, bool showWater) {
    final id = f.id;
    final minutes = f.actualFlightMinutes ?? 0;
    final fuel = f.hasFuel;
    final used = fuel ? f.fuelStartLiters! + f.fuelAddedLiters! - f.fuelEndLiters! : null;
    final rate = used != null && minutes > 0 ? used * 60 / minutes : null;
    final added = f.fuelAddedLiters ?? 0;
    Widget start = _cell(id, 'start', fuel ? '${f.fuelStartLiters}' : '—');
    if (fuel && fuelGap(f)) {
      start = Tooltip(
        key: Key('fuel-$id-start-gap'),
        message: 'Prévu : ${fuelText(f.fuelStartExpectedLiters)}',
        child: Container(
          color: fuelWarningColor.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: start,
        ),
      );
    }
    final Widget addedCell = !fuel
        ? _cell(id, 'added', '—')
        : added == 0
            ? _cell(id, 'added', '')
            : Container(
                key: Key('fuel-$id-added-mark'),
                color: _addedFill,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _cell(id, 'added', '$added',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              );
    return DataRow(
      onSelectChanged: (_) => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FlightScreen(me: widget.me, flight: f))),
      cells: [
        DataCell(_cell(id, 'date', formatShortDate(f.start))),
        DataCell(_cell(id, 'crew', crewText(f.crew, f.passengers, dir))),
        DataCell(_cell(id, 'time', formatDurationHm(minutes))),
        DataCell(start),
        DataCell(addedCell),
        DataCell(_cell(id, 'end', fuel ? '${f.fuelEndLiters}' : '—')),
        DataCell(_cell(id, 'used', used == null ? '—' : '$used')),
        DataCell(_cell(id, 'rate', rate == null ? '—' : _decimal(rate),
            style: rate != null && isUnusualConsumption(rate)
                ? const TextStyle(color: fuelWarningColor, fontWeight: FontWeight.bold)
                : null)),
        DataCell(_cell(id, 'landings', f.landings == null ? '—' : '${f.landings}')),
        if (showWater) DataCell(_cell(id, 'water', '${f.waterLandings ?? 0}')),
      ],
    );
  }

  /// Totaux de la période : temps et atterrissages de tous les vols ;
  /// ajouts, consommation et moyenne sur les vols avec carburant.
  DataRow _totalRow(List<Flight> flights, bool showWater) {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    var minutes = 0;
    var added = 0;
    var used = 0;
    var landings = 0;
    var water = 0;
    for (final f in flights) {
      minutes += f.actualFlightMinutes ?? 0;
      landings += f.landings ?? 0;
      water += f.waterLandings ?? 0;
      if (f.hasFuel) {
        added += f.fuelAddedLiters!;
        used += f.fuelStartLiters! + f.fuelAddedLiters! - f.fuelEndLiters!;
      }
    }
    final stats = fuelStats(flights);
    return DataRow(
      color: WidgetStatePropertyAll(Colors.grey.withValues(alpha: 0.15)),
      cells: [
        DataCell(_cell('total', 'date', 'Total', style: bold)),
        const DataCell(Text('')),
        DataCell(_cell('total', 'time', formatDurationHm(minutes), style: bold)),
        const DataCell(Text('')),
        DataCell(_cell('total', 'added', '$added', style: bold)),
        const DataCell(Text('')),
        DataCell(_cell('total', 'used', stats == null ? '—' : '$used', style: bold)),
        DataCell(_cell('total', 'rate', stats == null ? '—' : _decimal(stats.litersPerHour),
            style: bold)),
        DataCell(_cell('total', 'landings', '$landings', style: bold)),
        if (showWater) DataCell(_cell('total', 'water', '$water', style: bold)),
      ],
    );
  }
}

/// « 12,3 » (L/h, une décimale, virgule).
String _decimal(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
