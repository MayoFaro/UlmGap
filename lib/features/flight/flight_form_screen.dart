import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/flight_rules.dart';
import '../../core/formats.dart';
import '../../core/profile_badge.dart';
import '../../core/profiles.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/flight_api.dart';
import '../../data/services.dart';
import 'flight_texts.dart';

enum FlightFormMode { create, edit, validate }

class FlightFormScreen extends StatefulWidget {
  const FlightFormScreen({
    super.key,
    required this.me,
    this.flight,
    this.mode = FlightFormMode.create,
    this.now = DateTime.now,
  });

  final AppUser me;
  final Flight? flight;
  final FlightFormMode mode;
  final DateTime Function() now;

  @override
  State<FlightFormScreen> createState() => _FlightFormScreenState();
}

class _FlightFormScreenState extends State<FlightFormScreen> {
  late DateTime _start;
  late DateTime _end;
  String? _aircraftId;
  late List<String> _crew;
  String? _passenger;
  final _destination = TextEditingController();
  final _destinationFocus = FocusNode();
  bool _fuelOnly = false;
  bool _saving = false;

  final _subs = <StreamSubscription<Object?>>[];
  Map<String, CrewMember> _dir = {};
  List<Aircraft> _aircraft = [];
  Map<String, UserCategory> _categories = {};
  List<Flight> _flights = [];
  List<String> _destinations = [];
  bool _listening = false;

  AppUser get _me => widget.me;
  bool get _validating => widget.mode == FlightFormMode.validate;
  bool get _isStaff => _me.isAdmin || _me.isInstructor;
  bool get _mayChoose => _validating || _isStaff;

  @override
  void initState() {
    super.initState();
    final f = widget.flight;
    if (f != null) {
      _start = f.start;
      _end = f.end;
      _aircraftId = f.aircraftId;
      _crew = [...f.crew];
      _passenger = f.passengers.isEmpty ? null : f.passengers.first;
      _destination.text = f.destination;
      _fuelOnly = f.pricingMode == 'fuel_only';
    } else {
      final n = widget.now();
      _start = DateTime(n.year, n.month, n.day, n.hour + 1);
      _end = _start.add(const Duration(hours: 1));
      _crew = [_me.uid];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listening) return;
    _listening = true;
    final api = AppServices.of(context).flights!;
    void listen<T>(Stream<T> s, void Function(T) on) => _subs.add(s.listen(
          (v) {
            if (mounted) setState(() => on(v));
          },
          onError: (Object _) {}, // l'aperçu reste indicatif
        ));
    listen(api.watchDirectory(), (l) => _dir = {for (final m in l) m.uid: m});
    listen(api.watchAircraft(), (l) => _aircraft = l.where((a) => a.active).toList());
    listen(api.watchFrom(dayOf(widget.now())), (l) => _flights = l);
    if (_mayChoose) listen(api.watchCategories(), (m) => _categories = m);
    api.recentDestinations().then((d) {
      if (mounted) setState(() => _destinations = d);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _destination.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  // --- calculs de l'aperçu (indicatifs : le serveur décide) ---

  String _short(String uid) => uid == _me.uid ? _me.shortName : (_dir[uid]?.shortName ?? '…');
  PilotProfile? _profile(String uid) => uid == _me.uid ? _me.profile : _dir[uid]?.profile;
  UserCategory? _category(String uid) => uid == _me.uid ? _me.category : _categories[uid];

  bool get _allGap => _crew.every((u) => _category(u) == UserCategory.gap);
  bool get _showFuelChoice => _mayChoose && _allGap && _passenger == null;

  Decision get _decision => _validating
      ? Decision.ok('valide', widget.flight!.instructorUid)
      : decideStatus(
          creatorUid: _me.uid,
          creatorProfile: _me.profile?.code,
          creatorIsAdmin: _me.isAdmin,
          crew: [for (final u in _crew) RulePerson(u, _profile(u)?.code)],
          passengers: _passenger == null ? 0 : 1,
        );

  String get _mode => resolvePricingMode(
        allGap: _allGap,
        hasPassenger: _passenger != null,
        mayChoose: _mayChoose,
        requested: _showFuelChoice ? (_fuelOnly ? 'fuel_only' : 'standard') : null,
        previous: widget.flight?.pricingMode,
      );

  Flight? get _conflict {
    if (_aircraftId == null) return null;
    final hit = findConflict(
      RuleFlight(
        id: widget.flight?.id,
        start: _start.millisecondsSinceEpoch,
        end: _end.millisecondsSinceEpoch,
        aircraftId: _aircraftId!,
        crew: _crew,
      ),
      _flights.map((f) => f.toRule()),
    );
    if (hit == null) return null;
    return _flights.firstWhere((f) => f.id == hit.id);
  }

  String _statusText(Decision d) {
    if (!d.ok) return 'Impossible : ${d.reason}';
    if (d.status == 'demande') return 'Sera une demande à ${_short(d.instructorUid!)}';
    return switch (widget.mode) {
      FlightFormMode.validate => 'Sera validé',
      FlightFormMode.edit => 'Sera enregistré (validé)',
      FlightFormMode.create => 'Sera créé (validé)',
    };
  }

  // --- saisie ---

  Future<void> _pickDate() async {
    // Un admin peut saisir un vol oublié (jusqu'à un an en arrière).
    final computedFirst = _me.isAdmin && widget.mode == FlightFormMode.create
        ? dayOf(widget.now()).subtract(const Duration(days: 365))
        : dayOf(widget.now());
    // En édition/validation, le vol existant peut déjà commencer avant cette
    // borne (ex. vol de la veille) : showDatePicker exige
    // !initialDate.isBefore(firstDate), donc on élargit la borne au besoin.
    final startDay = dayOf(_start);
    final firstDate = startDay.isBefore(computedFirst) ? startDay : computedFirst;
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: firstDate,
      lastDate: widget.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      final length = _end.difference(_start);
      _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
      _end = _start.add(length);
    });
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null) return;
    setState(() {
      final length = _end.difference(_start);
      _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
      _end = _start.add(length);
    });
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_end));
    if (t == null) return;
    setState(() => _end = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _addMember() async {
    final candidates = _dir.values.where((m) => m.active && !_crew.contains(m.uid)).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final uid = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ajouter un équipier'),
        children: [
          for (final m in candidates)
            SimpleDialogOption(
              key: Key('pick-${m.uid}'),
              onPressed: () => Navigator.pop(ctx, m.uid),
              child: Row(children: [
                Text('${m.displayName} (${m.shortName})'),
                const SizedBox(width: 6),
                ProfileBadge(profile: m.profile, compact: true),
              ]),
            ),
        ],
      ),
    );
    if (uid != null) setState(() => _crew.add(uid));
  }

  Future<void> _addPassenger() async {
    // Contrôleur possédé par le dialogue lui-même (et non disposé ici juste
    // après le pop) : sinon le TextField est encore affiché pendant
    // l'animation de fermeture et Flutter l'utilise après dispose().
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _PassengerDialog(),
    );
    if (name != null && name.isNotEmpty) setState(() => _passenger = name);
  }

  // --- enregistrement ---

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _localError() {
    if (_aircraftId == null) return 'Choisissez un appareil.';
    if (_destination.text.trim().isEmpty) return 'Indiquez une destination.';
    if (_end.difference(_start).inMinutes < minPlannedMinutes) {
      return 'Durée prévue minimale : $minPlannedMinutes min.';
    }
    // Seul un admin crée après coup un vol passé (vol oublié).
    final pastAllowed = _me.isAdmin && widget.mode == FlightFormMode.create;
    if (!pastAllowed && !_start.isAfter(widget.now())) return 'L\'heure de départ est passée.';
    final d = _decision;
    return d.ok ? null : d.reason;
  }

  FlightDraft _draft() => FlightDraft(
        start: _start,
        end: _end,
        destination: _destination.text.trim(),
        aircraftId: _aircraftId!,
        crew: _crew,
        passengers: [if (_passenger != null) _passenger!],
        pricingMode: _showFuelChoice ? (_fuelOnly ? 'fuel_only' : 'standard') : null,
      );

  Future<void> _save() async {
    final error = _localError();
    if (error != null) {
      _snack(error);
      return;
    }
    // Spec §5 : la fin prévue est confirmée à l'enregistrement.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Heure de fin'),
        content: Text('Fin prévue à ${formatTime(_end)}. Confirmer ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Corriger')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final api = AppServices.of(context).flights!;
    try {
      switch (widget.mode) {
        case FlightFormMode.create:
          await api.create(_draft());
        case FlightFormMode.edit:
          await api.update(widget.flight!.id, _draft());
        case FlightFormMode.validate:
          final d = _draft();
          await api.validate(widget.flight!.id, changes: {
            'start': d.start.millisecondsSinceEpoch,
            'end': d.end.millisecondsSinceEpoch,
            'destination': d.destination,
            'aircraftId': d.aircraftId,
            if (d.pricingMode != null) 'pricingMode': d.pricingMode,
          });
      }
      if (mounted) Navigator.of(context).maybePop(true);
    } on FlightConflict catch (e) {
      if (mounted) _snack(describeConflict(e.conflict, _dir));
    } on FlightFailure catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --- affichage ---

  @override
  Widget build(BuildContext context) {
    final decision = _decision;
    final conflict = decision.status == 'valide' ? _conflict : null;
    final aboard = _crew.length + (_passenger == null ? 0 : 1);
    final crewEditable = !_validating;
    final title = switch (widget.mode) {
      FlightFormMode.create => 'Nouveau vol',
      FlightFormMode.edit => 'Modifier le vol',
      FlightFormMode.validate => 'Valider la demande',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Enregistrer',
            icon: const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Date'),
            subtitle: Text(formatDay(_start)),
            onTap: _pickDate,
          ),
          Row(children: [
            Expanded(
              child: ListTile(
                title: const Text('Départ'),
                subtitle: Text(formatTime(_start)),
                onTap: _pickStart,
              ),
            ),
            Expanded(
              child: ListTile(
                title: const Text('Fin'),
                subtitle: Text(formatTime(_end)),
                onTap: _pickEnd,
              ),
            ),
          ]),
          DropdownButtonFormField<String>(
            key: const Key('f-aircraft'),
            value: _aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : null,
            decoration: const InputDecoration(labelText: 'Appareil'),
            items: [
              for (final a in _aircraft)
                DropdownMenuItem(value: a.id, child: Text('${a.label} (${a.registration})')),
            ],
            onChanged: (v) => setState(() => _aircraftId = v),
          ),
          const SizedBox(height: 16),
          Text('Équipage', style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < _crew.length; i++)
            ListTile(
              leading: ProfileBadge(profile: _profile(_crew[i]), compact: true),
              title: Text(_short(_crew[i])),
              subtitle: i == 0 ? const Text('Payeur') : null,
              trailing: !crewEditable
                  ? null
                  : Wrap(children: [
                      if (i > 0)
                        IconButton(
                          tooltip: 'Mettre en premier',
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: () => setState(() => _crew.insert(0, _crew.removeAt(i))),
                        ),
                      if (_crew.length > 1 && (_crew[i] != _me.uid || _me.isAdmin))
                        IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _crew.removeAt(i)),
                        ),
                    ]),
            ),
          if (_passenger != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_passenger!),
              subtitle: const Text('Passager sans compte'),
              trailing: !crewEditable
                  ? null
                  : IconButton(
                      tooltip: 'Retirer le passager',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _passenger = null),
                    ),
            ),
          if (crewEditable && aboard < 2)
            Wrap(spacing: 8, children: [
              TextButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Ajouter un équipier'),
                onPressed: _addMember,
              ),
              TextButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Ajouter un passager sans compte'),
                onPressed: _addPassenger,
              ),
            ]),
          Text('Payeur : ${_short(_crew.first)}', key: const Key('payer')),
          const SizedBox(height: 16),
          RawAutocomplete<String>(
            textEditingController: _destination,
            focusNode: _destinationFocus,
            optionsBuilder: (v) {
              final q = v.text.trim().toLowerCase();
              if (q.isEmpty) return const Iterable<String>.empty();
              return _destinations.where((d) => d.toLowerCase().contains(q));
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
              key: const Key('f-destination'),
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(labelText: 'Destination'),
              onChanged: (_) => setState(() {}),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: SizedBox(
                  height: 200,
                  width: 300,
                  child: ListView(children: [
                    for (final o in options) ListTile(title: Text(o), onTap: () => onSelected(o)),
                  ]),
                ),
              ),
            ),
          ),
          if (_showFuelChoice)
            CheckboxListTile(
              key: const Key('f-fuel'),
              title: const Text('Carburant seulement'),
              value: _fuelOnly,
              onChanged: (v) => setState(() => _fuelOnly = v ?? false),
            ),
          const SizedBox(height: 16),
          Card(
            key: const Key('preview'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_statusText(decision)),
                Text('Payeur : ${_short(_crew.first)}'),
                Text('Mode : ${pricingModeLabel(_mode)}'),
                if (conflict != null)
                  Text(
                    describeConflict(
                      ConflictInfo(
                        start: conflict.start,
                        end: conflict.end,
                        aircraft: conflict.aircraft,
                        crew: conflict.crew,
                        passengers: conflict.passengers,
                      ),
                      _dir,
                    ),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  )
                else if (decision.status == 'valide')
                  const Text('Aucun conflit connu.'),
                Text('Aperçu indicatif : la décision finale revient au serveur.',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialogue « passager sans compte » : possède son propre contrôleur (dispose
/// naturel à la fermeture, voir _addPassenger ci-dessus).
class _PassengerDialog extends StatefulWidget {
  const _PassengerDialog();

  @override
  State<_PassengerDialog> createState() => _PassengerDialogState();
}

class _PassengerDialogState extends State<_PassengerDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passager sans compte'),
      content: TextField(
        key: const Key('passenger-name'),
        controller: _c,
        decoration: const InputDecoration(labelText: 'Nom'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text.trim()),
            child: const Text('Ajouter')),
      ],
    );
  }
}
