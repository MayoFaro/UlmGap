import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../data/aircraft.dart';
import '../../data/services.dart';
import 'aircraft_form_dialog.dart';

class AircraftAdminScreen extends StatelessWidget {
  const AircraftAdminScreen({super.key});

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
      appBar: AppBar(title: const Text('Appareils')),
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
        builder: (context, snap) => ListView(
          children: [
            for (final a in snap.data ?? const <Aircraft>[])
              ListTile(
                // Reste cliquable même inactif (pour le réactiver).
                textColor: a.active ? null : Theme.of(context).disabledColor,
                leading: const Icon(Icons.airplanemode_active),
                title: Text(a.label),
                subtitle: Text(a.registration),
                trailing: a.active ? null : const Chip(label: Text('Inactif')),
                onTap: () async {
                  final input = await showAircraftFormDialog(context, aircraft: a);
                  if (context.mounted) await _save(context, input);
                },
              ),
          ],
        ),
      ),
    );
  }
}
