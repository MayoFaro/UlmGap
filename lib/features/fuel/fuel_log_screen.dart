// Écran « Suivi carburant » d'un appareil (spec §9.5), ouvert par tout
// utilisateur depuis le carburant affiché (CurrentFuelTile).
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

const _gapColor = Color(0xFFEF6C00);

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

class FuelLogScreen extends StatelessWidget {
  const FuelLogScreen({super.key, required this.me, required this.aircraftId});
  final AppUser me;
  final String aircraftId;

  @override
  Widget build(BuildContext context) {
    final api = AppServices.of(context).flights!;
    return StreamBuilder<List<Aircraft>>(
      stream: api.watchAircraft(),
      builder: (context, acSnap) {
        Aircraft? aircraft;
        for (final a in acSnap.data ?? const <Aircraft>[]) {
          if (a.id == aircraftId) aircraft = a;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text('Suivi carburant · ${aircraft?.registration ?? ''}'),
            actions: appNavActions(context, me),
          ),
          body: StreamBuilder<List<CrewMember>>(
            stream: api.watchDirectory(),
            builder: (context, dirSnap) {
              final dir = {for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m};
              return StreamBuilder<List<Flight>>(
                stream: api.watchAircraftFlights(aircraftId),
                builder: (context, snap) {
                  final flights = (snap.data ?? const <Flight>[])
                      .where((f) => f.isClosed && !f.deleted && f.hasFuel)
                      .toList()
                    ..sort((a, b) => b.start.compareTo(a.start));
                  final stats = fuelStats(flights);
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    Text('Carburant actuel : ${fuelText(aircraft?.fuelLiters)}',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (stats != null)
                      Text('Consommation estimée : ${formatLitersPerHour(stats.litersPerHour)} '
                          '(${stats.flights} vol${stats.flights > 1 ? 's' : ''}, '
                          '${formatDurationHm(stats.minutes)})'),
                    const Divider(),
                    if (flights.isEmpty) const Text('Aucun vol avec carburant.'),
                    for (final f in flights)
                      ListTile(
                        tileColor: fuelGap(f) ? _gapColor.withValues(alpha: 0.12) : null,
                        title: Text('${formatDay(f.start)} · ${crewText(f.crew, f.passengers, dir)}'),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Départ ${f.fuelStartLiters} L · +${f.fuelAddedLiters} L · '
                              'Rangé ${f.fuelEndLiters} L'),
                          if (fuelGap(f))
                            Text('Écart au départ : prévu ${fuelText(f.fuelStartExpectedLiters)}, '
                                'réel ${f.fuelStartLiters} L',
                                style: const TextStyle(color: _gapColor)),
                        ]),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => FlightScreen(me: me, flight: f))),
                      ),
                  ]);
                },
              );
            },
          ),
        );
      },
    );
  }
}
