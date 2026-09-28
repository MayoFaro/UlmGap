import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/flight_api.dart';
import '../../data/services.dart';
import 'flight_actions.dart';
import 'flight_form_screen.dart';
import 'flight_texts.dart';

class FlightDetailScreen extends StatefulWidget {
  const FlightDetailScreen({
    super.key,
    required this.flightId,
    required this.me,
    this.now = DateTime.now,
  });

  final String flightId;
  final AppUser me;
  final DateTime Function() now;

  @override
  State<FlightDetailScreen> createState() => _FlightDetailScreenState();
}

class _FlightDetailScreenState extends State<FlightDetailScreen> {
  Stream<Flight?>? _flight;
  StreamSubscription<List<CrewMember>>? _dirSub;
  Map<String, CrewMember> _dir = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flight != null) return;
    final api = AppServices.of(context).flights!;
    _flight = api.watchFlight(widget.flightId);
    _dirSub = api.watchDirectory().listen((l) {
      if (mounted) setState(() => _dir = {for (final m in l) m.uid: m});
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _dirSub?.cancel();
    super.dispose();
  }

  String _short(String uid) => _dir[uid]?.shortName ?? '…';

  Future<void> _run(Future<void> Function() action, {bool popAfter = false}) async {
    try {
      await action();
      if (popAfter && mounted) Navigator.of(context).maybePop();
    } on FlightConflict catch (e) {
      if (mounted) _snack(describeConflict(e.conflict, _dir));
    } on FlightFailure catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _refuse(Flight f) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RefuseDialog(),
    );
    if (reason == null || !mounted) return;
    await _run(() => AppServices.of(context).flights!.refuse(f.id, reason));
  }

  Future<void> _cancel(Flight f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler ce vol ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => AppServices.of(context).flights!.cancel(f.id), popAfter: true);
  }

  void _openForm(Flight f, FlightFormMode mode) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlightFormScreen(me: widget.me, flight: f, mode: mode, now: widget.now),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vol')),
      body: StreamBuilder<Flight?>(
        stream: _flight,
        builder: (context, snap) {
          if (snap.hasError) return connectionErrorMessage();
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final f = snap.data;
          if (f == null || f.deleted) return const Center(child: Text('Vol introuvable.'));
          return _details(f);
        },
      ),
    );
  }

  Widget _details(Flight f) {
    final now = widget.now();
    final status = f.effectiveStatus(now);
    final actions = flightActions(f, widget.me, now);
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        ListTile(title: const Text('Date'), subtitle: Text(formatDay(f.start))),
        ListTile(title: const Text('Horaire'), subtitle: Text(formatRange(f.start, f.end))),
        ListTile(title: const Text('Appareil'), subtitle: Text(f.aircraft)),
        ListTile(title: const Text('Destination'), subtitle: Text(f.destination)),
        for (var i = 0; i < f.crew.length; i++)
          ListTile(
            leading: ProfileBadge(profile: _dir[f.crew[i]]?.profile, compact: true),
            title: Text(_dir[f.crew[i]]?.displayName ?? _short(f.crew[i])),
            subtitle: i == 0 ? const Text('Payeur') : null,
          ),
        for (final p in f.passengers)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(p),
            subtitle: const Text('Passager sans compte'),
          ),
        ListTile(
          title: const Text('Statut'),
          subtitle: Text(
            f.isExpiredRequest(now) ? 'Refusé (non validée avant le départ)' : statusLabel(status),
            style: TextStyle(color: statusColor(status)),
          ),
        ),
        if (f.status == FlightStatus.refuse && f.refusalReason != null)
          ListTile(title: const Text('Motif du refus'), subtitle: Text(f.refusalReason!)),
        if (f.instructorUid != null)
          ListTile(title: Text('Instructeur désigné : ${_short(f.instructorUid!)}')),
        ListTile(title: const Text('Tarification'), subtitle: Text(pricingModeLabel(f.pricingMode))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (actions.contains(FlightAction.validate))
            FilledButton(
                onPressed: () => _openForm(f, FlightFormMode.validate), child: const Text('Valider')),
          if (actions.contains(FlightAction.refuse))
            OutlinedButton(onPressed: () => _refuse(f), child: const Text('Refuser')),
          if (actions.contains(FlightAction.edit))
            OutlinedButton(
                onPressed: () => _openForm(f, FlightFormMode.edit), child: const Text('Modifier')),
          if (actions.contains(FlightAction.cancel))
            TextButton(onPressed: () => _cancel(f), child: const Text('Annuler le vol')),
        ]),
      ],
    );
  }
}

/// Dialogue « refuser la demande » : possède son propre contrôleur (dispose
/// naturel à la fermeture, comme _PassengerDialog dans flight_form_screen.dart
/// et AircraftFormDialog) plutôt qu'un contrôleur créé dans _refuse et
/// disposé juste après le pop, qui plante pendant l'animation de fermeture
/// ("TextEditingController used after being disposed").
class _RefuseDialog extends StatefulWidget {
  const _RefuseDialog();

  @override
  State<_RefuseDialog> createState() => _RefuseDialogState();
}

class _RefuseDialogState extends State<_RefuseDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Refuser la demande'),
      content: TextField(
        key: const Key('refuse-reason'),
        controller: _c,
        decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text), child: const Text('Refuser')),
      ],
    );
  }
}
