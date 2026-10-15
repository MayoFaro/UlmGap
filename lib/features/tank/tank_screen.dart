// Écran « Suivi cuve » (spec §13.6), instructeurs et admins : niveau
// actuel, plein d'un appareil, relevé de jauge, mouvements et totaux de la
// période.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import '../../data/tank_movement.dart';
import '../flight/flight_screen.dart';
import '../logbook/period_selector.dart';
import 'tank_dialogs.dart';

const _minus = '−';

/// « 180 L », « −12 L ».
String litersText(int liters) => liters < 0 ? '$_minus${-liters} L' : '$liters L';

/// « +200 L », « −15 L ».
String signedLiters(int liters) => liters < 0 ? litersText(liters) : '+$liters L';

/// Niveau négatif (oubli de saisie) : orange, jamais bloquant.
Color? tankLevelColor(int liters) => liters < 0 ? Colors.orange.shade800 : null;

/// Mouvements dont le jour tombe dans [from, to[, du plus récent au plus
/// ancien (jour, puis saisie).
List<TankMovement> tankPeriod(List<TankMovement> all, DateTime from, DateTime to) => all
    .where((m) => !m.day.isBefore(from) && m.day.isBefore(to))
    .toList()
  ..sort((a, b) {
    final byDay = b.date.compareTo(a.date);
    return byDay != 0 ? byDay : b.at.compareTo(a.at);
  });

/// Totaux de la période ; « Vols » comprend les régularisations de vols.
({int refills, int flights, int technical, int fills, int gauges}) tankTotals(
    Iterable<TankMovement> ms) {
  var refills = 0, flights = 0, technical = 0, fills = 0, gauges = 0;
  for (final m in ms) {
    switch (m.kind) {
      case TankKind.refill:
        refills += m.liters;
      case TankKind.flight || TankKind.flightAdjustment:
        flights += m.liters;
        if (m.technical) technical += m.liters;
      case TankKind.aircraftFill:
        fills += m.liters;
      case TankKind.gauge:
        gauges += m.liters;
      case null:
        break;
    }
  }
  return (refills: refills, flights: flights, technical: technical, fills: fills, gauges: gauges);
}

/// « Vol — F-JABC (technique) », « Plein hors vol — F-JABC », « Remplissage »…
String tankTitle(TankMovement m, Map<String, String> registrations) {
  final label = m.kind?.label ?? m.kindCode;
  final aircraftId = m.aircraftId;
  final base = aircraftId == null ? label : '$label — ${registrations[aircraftId] ?? '?'}';
  return m.technical ? '$base (technique)' : base;
}

class TankScreen extends StatefulWidget {
  const TankScreen({super.key, required this.me, this.now = DateTime.now});
  final AppUser me;
  final DateTime Function() now;

  @override
  State<TankScreen> createState() => _TankScreenState();
}

class _TankScreenState extends State<TankScreen> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final p = initialPeriod(widget.now());
    _from = p.from;
    _to = p.to;
  }

  Future<void> _openFlight(String id) async {
    final flight = await AppServices.of(context).flights!.watchFlight(id).first;
    if (flight == null || !mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => FlightScreen(me: widget.me, flight: flight)));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final tank = services.tank!;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi cuve')),
      body: StreamBuilder<List<Aircraft>>(
        stream: services.flights!.watchAircraft(),
        builder: (context, airSnap) {
          final aircraft = airSnap.data ?? const <Aircraft>[];
          final registrations = {for (final a in aircraft) a.id: a.registration};
          return StreamBuilder<int>(
            stream: tank.watchTank(),
            builder: (context, levelSnap) {
              final level = levelSnap.data ?? 0;
              return StreamBuilder<List<TankMovement>>(
                stream: tank.watchMovements(),
                builder: (context, mvSnap) {
                  final shown = tankPeriod(mvSnap.data ?? const [], _from, _to);
                  final t = tankTotals(shown);
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Niveau actuel : ${litersText(level)}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold, color: tankLevelColor(level))),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.local_gas_station),
                              label: const Text('Plein d\'un appareil'),
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => AircraftFillDialog(
                                    aircraft: aircraft.where((a) => a.active).toList(),
                                    now: widget.now),
                              ),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.straighten),
                              label: const Text('Relevé de jauge'),
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => GaugeReadingDialog(level: level, now: widget.now),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                      PeriodSelector(
                        now: widget.now,
                        onChanged: (from, to) => setState(() {
                          _from = from;
                          _to = to;
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Remplissages : ${signedLiters(t.refills)}'),
                          Text('Vols : ${signedLiters(t.flights)} '
                              '(dont vols techniques : ${signedLiters(t.technical)})'),
                          Text('Pleins hors vol : ${signedLiters(t.fills)}'),
                          Text('Écarts de jauge : ${signedLiters(t.gauges)}'),
                        ]),
                      ),
                      if (shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucun mouvement sur cette période.'),
                        ),
                      for (final m in shown)
                        ListTile(
                          title: Text(tankTitle(m, registrations)),
                          subtitle: Text([
                            formatShortDate(m.day),
                            if (m.note != null && m.note!.isNotEmpty) m.note!,
                            'Niveau après : ${litersText(m.litersAfter)}',
                          ].join(' · ')),
                          trailing: Text(
                            signedLiters(m.liters),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: m.liters < 0
                                  ? Theme.of(context).colorScheme.error
                                  : Colors.green.shade700,
                            ),
                          ),
                          onTap: m.flightId == null ? null : () => _openFlight(m.flightId!),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
