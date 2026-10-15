// Écran « Caisse » (spec §11.6), instructeurs et admins : en-tête (caisse,
// avoirs adhérents, disponible), reprise (admins), période, filtres,
// totaux et opérations.
import 'package:flutter/material.dart';

import '../../core/cash.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../data/app_user.dart';
import '../../data/cash_movement.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';
import '../account/movements_list.dart' show signedFcfa;
import '../home/app_nav.dart';
import '../logbook/period_selector.dart';
import '../tank/tank_screen.dart';
import 'cash_dialogs.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key, required this.me, this.now = DateTime.now});
  final AppUser me;
  final DateTime Function() now;

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  late DateTime _from;
  late DateTime _to;
  final _kinds = <CashKind>{};

  @override
  void initState() {
    super.initState();
    final p = initialPeriod(widget.now());
    _from = p.from;
    _to = p.to;
  }

  Future<void> _closeMigration() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reprise terminée'),
        content: const Text('Après cela, « Corriger le solde » ne sera plus possible : '
            'seules les corrections d\'opération resteront. Irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppServices.of(context).cash!.closeMigration();
      messenger.showSnackBar(const SnackBar(content: Text('Reprise terminée.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e is FlightFailure ? e.message : 'Opération incertaine : vérifiez la caisse.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final cash = services.cash!;
    final me = widget.me;
    return StreamBuilder<List<AppUser>>(
      stream: services.finance!.watchAccounts(),
      builder: (context, accSnap) {
        final accounts = accSnap.data ?? const <AppUser>[];
        final names = {for (final a in accounts) a.uid: a.shortName};
        return Scaffold(
          appBar: AppBar(
            title: const Text('Caisse'),
            actions: appNavActions(context, me, current: AppDestination.cash),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Opération'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  CashOperationDialog(isAdmin: me.isAdmin, accounts: accounts, now: widget.now),
            ),
          ),
          body: StreamBuilder<Cashbox>(
            stream: cash.watchCashbox(),
            builder: (context, boxSnap) {
              final box = boxSnap.data ?? Cashbox.empty;
              final holdings = accounts.fold(0, (s, a) => s + a.balance);
              return StreamBuilder<List<CashMovement>>(
                stream: cash.watchMovements(),
                builder: (context, mvSnap) {
                  final all = mvSnap.data ?? const <CashMovement>[];
                  final shown = cashPeriod(all, _from, _to, _kinds);
                  final totals = cashTotals(shown);
                  final closedAt = box.migrationClosedAt;
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Caisse : ${formatFcfa(box.balance)}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          Text('Avoirs adhérents : ${formatFcfa(holdings)}'),
                          Text('Disponible : ${formatFcfa(box.balance - holdings)}'),
                          if (me.isAdmin)
                            closedAt == null
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton(
                                        onPressed: _closeMigration,
                                        child: const Text('Reprise terminée')),
                                  )
                                : Text('Reprise terminée le ${formatShortDate(closedAt)}'),
                        ]),
                      ),
                      if (services.tank != null) _TankLine(me: me, now: widget.now),
                      PeriodSelector(
                        now: widget.now,
                        onChanged: (from, to) => setState(() {
                          _from = from;
                          _to = to;
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(spacing: 8, children: [
                          for (final k in CashKind.filters)
                            FilterChip(
                              avatar: Icon(k.icon, size: 18),
                              label: Text(k.label),
                              selected: _kinds.contains(k),
                              onSelected: (on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                            ),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Entrées : +${formatFcfa(totals.entries)}'
                            ' · Sorties : ${formatFcfa(totals.exits)}'),
                      ),
                      if (shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucune opération sur cette période.'),
                        ),
                      for (final m in shown) _CashTile(m, all: all, names: names, isAdmin: me.isAdmin),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// Plan 13 : « Cuve : 180 L » (orange si négatif) ; appui → Suivi cuve.
class _TankLine extends StatelessWidget {
  const _TankLine({required this.me, required this.now});
  final AppUser me;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: AppServices.of(context).tank!.watchTank(),
        builder: (context, snap) {
          final liters = snap.data ?? 0;
          return ListTile(
            key: const Key('cash-tank'),
            leading: const Icon(Icons.propane_tank),
            title: Text('Cuve : ${litersText(liters)}',
                style: TextStyle(color: tankLevelColor(liters))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => TankScreen(me: me, now: now))),
          );
        },
      );
}

class _CashTile extends StatelessWidget {
  const _CashTile(this.m, {required this.all, required this.names, required this.isAdmin});
  final CashMovement m;
  final List<CashMovement> all;
  final Map<String, String> names;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final title = cashTitle(m, names);
    // La note d'une correction commence toujours par « Correction » (serveur).
    final subtitle = [
      formatShortDate(m.day),
      if (m.note != null && m.note!.isNotEmpty) m.note!,
    ].join(' · ');
    return ListTile(
      leading: Icon(m.kind?.icon ?? Icons.help_outline),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        signedFcfa(m.amount),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: m.amount < 0 ? Theme.of(context).colorScheme.error : Colors.green.shade700,
        ),
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => CashMovementDialog(
            movement: m, all: all, title: title, shortNames: names, isAdmin: isAdmin),
      ),
    );
  }
}
