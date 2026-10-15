// Dialogues du suivi cuve (spec §13.5) : plein d'un appareil hors vol et
// relevé de jauge. Mêmes bornes et messages que le serveur
// (functions/src/finance/tank-validation.ts).
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/aircraft.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';
import 'tank_screen.dart' show litersText;

const _uncertain = 'Opération incertaine : vérifiez la cuve avant de réessayer.';

/// Squelette commun : date, note, erreur et validation ; [submit] rend
/// l'erreur de saisie, ou appelle le serveur et rend null.
class _TankDialog extends StatefulWidget {
  const _TankDialog({required this.title, required this.now, required this.fields, required this.submit});
  final String title;
  final DateTime Function() now;
  final List<Widget> fields;
  final Future<String?> Function(DateTime date, String? note) submit;

  @override
  State<_TankDialog> createState() => _TankDialogState();
}

class _TankDialogState extends State<_TankDialog> {
  late DateTime _date = dayOf(widget.now());
  final _note = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dayOf(widget.now());
    final picked = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: today);
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final note = _note.text.trim();
      final invalid = await widget.submit(_date, note.isEmpty ? null : note);
      if (!mounted) return;
      if (invalid != null) {
        setState(() {
          _submitting = false;
          _error = invalid;
        });
        return;
      }
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Opération enregistrée.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is FlightFailure ? e.message : _uncertain;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...widget.fields,
            TextButton.icon(
              key: const Key('tank-date'),
              icon: const Icon(Icons.event),
              label: Text('Date : ${formatShortDate(_date)}'),
              onPressed: _pickDate,
            ),
            TextField(
              key: const Key('tank-note'),
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Note (facultative)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Valider')),
        ],
      );
}

/// Plein d'un appareil hors vol : appareil actif, litres (1 à 100).
class AircraftFillDialog extends StatefulWidget {
  const AircraftFillDialog({super.key, required this.aircraft, required this.now});

  /// Appareils actifs.
  final List<Aircraft> aircraft;
  final DateTime Function() now;

  @override
  State<AircraftFillDialog> createState() => _AircraftFillDialogState();
}

class _AircraftFillDialogState extends State<AircraftFillDialog> {
  late String? _aircraftId = widget.aircraft.isEmpty ? null : widget.aircraft.first.id;
  final _liters = TextEditingController();

  @override
  void dispose() {
    _liters.dispose();
    super.dispose();
  }

  Future<String?> _submit(DateTime date, String? note) async {
    final id = _aircraftId;
    if (id == null) return 'Appareil manquant.';
    final liters = int.tryParse(_liters.text.trim());
    if (liters == null || liters < 1 || liters > 100) return 'Litres invalides (1 à 100).';
    await AppServices.of(context).tank!.aircraftFill(aircraftId: id, liters: liters, date: date, note: note);
    return null;
  }

  @override
  Widget build(BuildContext context) => _TankDialog(
        title: 'Plein d\'un appareil',
        now: widget.now,
        submit: _submit,
        fields: [
          DropdownButtonFormField<String>(
            key: const Key('tank-aircraft'),
            value: _aircraftId,
            decoration: const InputDecoration(labelText: 'Appareil'),
            items: [
              for (final a in widget.aircraft)
                DropdownMenuItem(value: a.id, child: Text('${a.label} (${a.registration})')),
            ],
            onChanged: (v) => setState(() => _aircraftId = v),
          ),
          TextField(
            key: const Key('tank-liters'),
            controller: _liters,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Litres'),
          ),
        ],
      );
}

/// Relevé de jauge : niveau mesuré (0 à 100 000 L), niveau calculé rappelé.
class GaugeReadingDialog extends StatefulWidget {
  const GaugeReadingDialog({super.key, required this.level, required this.now});

  /// Niveau calculé actuel.
  final int level;
  final DateTime Function() now;

  @override
  State<GaugeReadingDialog> createState() => _GaugeReadingDialogState();
}

class _GaugeReadingDialogState extends State<GaugeReadingDialog> {
  final _measured = TextEditingController();

  @override
  void dispose() {
    _measured.dispose();
    super.dispose();
  }

  Future<String?> _submit(DateTime date, String? note) async {
    final measured = int.tryParse(_measured.text.trim());
    if (measured == null || measured < 0 || measured > 100000) {
      return 'Niveau mesuré invalide (0 à 100 000 L).';
    }
    await AppServices.of(context).tank!.gaugeReading(measuredLiters: measured, date: date, note: note);
    return null;
  }

  @override
  Widget build(BuildContext context) => _TankDialog(
        title: 'Relevé de jauge',
        now: widget.now,
        submit: _submit,
        fields: [
          Text('Niveau calculé : ${litersText(widget.level)}'),
          TextField(
            key: const Key('tank-measured'),
            controller: _measured,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Niveau mesuré (L)'),
          ),
        ],
      );
}
