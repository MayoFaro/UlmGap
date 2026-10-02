import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/fuel.dart';
import '../../data/aircraft.dart';
import '../../data/services.dart';
import 'aircraft_form_dialog.dart';
import '../../data/app_user.dart';
import '../fuel/fuel_log_screen.dart';
import '../home/app_nav.dart';

class AircraftAdminScreen extends StatelessWidget {
  const AircraftAdminScreen({super.key, this.me});

  /// Compte connecté : icônes de navigation (absentes si null).
  final AppUser? me;

  Future<void> _save(BuildContext context, Map<String, dynamic>? input) async {
    if (input == null) return;
    try {
      await AppServices.of(context).admin!.upsertAircraft(input);
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppServices.of(context).admin!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appareils'),
        actions: me == null ? null : appNavActions(context, me!, current: AppDestination.aircraft),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouvel appareil',
        child: const Icon(Icons.add),
        onPressed: () async {
          final input = await showAircraftFormDialog(context);
          if (context.mounted) await _save(context, input);
        },
      ),
      body: StreamBuilder<List<Aircraft>>(
        stream: api.watchAircraft(),
        builder: (context, snap) {
          final list = snap.data ?? const <Aircraft>[];
          final state = asyncState(snap, isEmpty: list.isEmpty, empty: 'Aucun appareil.');
          if (state != null) return state;
          return ListView(
            children: [
              for (final a in list)
                ListTile(
                  // Reste cliquable même inactif (pour le réactiver).
                  textColor: a.active ? null : Theme.of(context).disabledColor,
                  leading: const Icon(Icons.airplanemode_active),
                  title: Text(a.label),
                  subtitle: Text(
                      '${a.amphibious ? '${a.registration} · amphibie' : a.registration}'
                      ' · carburant ${fuelText(a.fuelLiters)}'),
                  trailing: me == null
                      ? (a.active ? null : const Chip(label: Text('Inactif')))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          if (!a.active) const Chip(label: Text('Inactif')),
                          IconButton(
                            tooltip: 'Suivi carburant',
                            icon: const Icon(Icons.local_gas_station),
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => FuelLogScreen(me: me!, aircraftId: a.id))),
                          ),
                        ]),
                  onTap: () async {
                    final input = await showAircraftFormDialog(context, aircraft: a);
                    if (context.mounted) await _save(context, input);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
