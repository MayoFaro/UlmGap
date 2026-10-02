import 'package:flutter/material.dart';

import '../../data/aircraft.dart';
import 'validators.dart';

Future<Map<String, dynamic>?> showAircraftFormDialog(BuildContext context, {Aircraft? aircraft}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AircraftFormDialog(aircraft: aircraft),
    );

class _AircraftFormDialog extends StatefulWidget {
  const _AircraftFormDialog({this.aircraft});
  final Aircraft? aircraft;
  @override
  State<_AircraftFormDialog> createState() => _AircraftFormDialogState();
}

class _AircraftFormDialogState extends State<_AircraftFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _reg = TextEditingController(text: widget.aircraft?.registration ?? '');
  late final _label = TextEditingController(text: widget.aircraft?.label ?? '');
  late bool _active = widget.aircraft?.active ?? true;
  late bool _amphibious = widget.aircraft?.amphibious ?? false;

  @override
  void dispose() {
    _reg.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.aircraft == null ? 'Nouvel appareil' : 'Modifier l\'appareil'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('a-reg'),
              controller: _reg,
              decoration: const InputDecoration(labelText: 'Immatriculation'),
              validator: (v) => validateRequired(v ?? '', 'Immatriculation'),
            ),
            TextFormField(
              key: const Key('a-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Libellé'),
              validator: (v) => validateRequired(v ?? '', 'Libellé'),
            ),
            SwitchListTile(
              title: const Text('Actif'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            SwitchListTile(
              key: const Key('a-amphibious'),
              title: const Text('Amphibie'),
              value: _amphibious,
              onChanged: (v) => setState(() => _amphibious = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop(<String, dynamic>{
              if (widget.aircraft != null) 'id': widget.aircraft!.id,
              'registration': _reg.text.trim().toUpperCase(),
              'label': _label.text.trim(),
              'active': _active,
              'amphibious': _amphibious,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
