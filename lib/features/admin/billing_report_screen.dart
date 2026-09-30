// Écran « Relevé des vols facturés » (admin, Task 12) : vols clôturés non
// supprimés sur une période, totaux débité sur comptes / facturé hors app,
// export CSV (web seulement).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/csv.dart';
import '../../core/download.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../core/period_bar.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_texts.dart';

/// En-têtes du CSV exporté : plus détaillées que le tableau affiché à
/// l'écran. Fonction pure (avec [billingCsvRows]), testée indépendamment du
/// téléchargement.
const billingCsvHeaders = [
  'Date',
  'Départ',
  'Fin',
  'Appareil',
  'Équipage',
  'Passagers',
  'Mode',
  'Durée réelle (min)',
  'Montant',
  'Imputation',
  'Compte débité',
];

/// Une ligne du CSV par vol de [flights], dans l'ordre reçu.
List<List<String>> billingCsvRows(List<Flight> flights, Map<String, CrewMember> dir) => [
      for (final f in flights)
        [
          formatDay(f.start),
          formatTime(f.start),
          formatTime(f.end),
          f.aircraft,
          f.crew.map((u) => dir[u]?.shortName ?? '?').join('/'),
          f.passengers.join('/'),
          pricingModeLabel(f.pricingMode),
          f.actualFlightMinutes?.toString() ?? '',
          (f.billedAmount ?? 0).toString(),
          f.billedTo == 'off_app' ? 'Hors app' : 'Compte',
          f.billedTo == 'off_app' ? '' : (dir[f.payerUidField ?? f.payerUid]?.shortName ?? '?'),
        ],
    ];

String _fileDatePart(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class BillingReportScreen extends StatefulWidget {
  const BillingReportScreen({super.key, this.now = DateTime.now});
  final DateTime Function() now;

  @override
  State<BillingReportScreen> createState() => _BillingReportScreenState();
}

class _BillingReportScreenState extends State<BillingReportScreen> {
  // [_to] est exclusif (comme FinanceApi.watchFlightsBetween).
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final n = widget.now();
    _from = DateTime(n.year, n.month);
    _to = DateTime(n.year, n.month + 1);
  }

  DateTime get _lastIncludedDay => _to.subtract(const Duration(days: 1));

  void _export(List<Flight> flights, Map<String, CrewMember> dir) {
    final csv = buildCsv(billingCsvHeaders, billingCsvRows(flights, dir));
    final filename = 'releve_${_fileDatePart(_from)}_${_fileDatePart(_lastIncludedDay)}.csv';
    downloadTextFile(filename, csv);
  }

  @override
  Widget build(BuildContext context) {
    final finance = AppServices.of(context).finance!;
    final flightsApi = AppServices.of(context).flights!;
    return Scaffold(
      appBar: AppBar(title: const Text('Relevé des vols facturés')),
      body: Column(
        children: [
          PeriodBar(
            from: _from,
            to: _to,
            onChanged: (f, t) => setState(() {
              _from = f;
              _to = t;
            }),
          ),
          Expanded(
            child: StreamBuilder<List<CrewMember>>(
              stream: flightsApi.watchDirectory(),
              builder: (context, dirSnap) {
                final dir = {
                  for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m,
                };
                return StreamBuilder<List<Flight>>(
                  stream: finance.watchFlightsBetween(_from, _to),
                  builder: (context, snap) => _body(context, snap, dir),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AsyncSnapshot<List<Flight>> snap, Map<String, CrewMember> dir) {
    final flights =
        (snap.data ?? const <Flight>[]).where((f) => f.isClosed && !f.deleted).toList();
    final state =
        asyncState(snap, isEmpty: flights.isEmpty, empty: 'Aucun vol clôturé sur cette période.');
    if (state != null) return state;

    var debitedTotal = 0;
    var offAppTotal = 0;
    for (final f in flights) {
      final amount = f.billedAmount ?? 0;
      if (f.billedTo == 'off_app') {
        offAppTotal += amount;
      } else {
        debitedTotal += amount;
      }
    }

    Widget totalRow(String label, int amount) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label),
            Text(formatFcfa(amount), style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Appareil')),
                DataColumn(label: Text('Équipage')),
                DataColumn(label: Text('Mode')),
                DataColumn(label: Text('Montant')),
                DataColumn(label: Text('Imputation')),
              ],
              rows: [
                for (final f in flights)
                  DataRow(cells: [
                    DataCell(Text(formatDay(f.start))),
                    DataCell(Text(f.aircraft)),
                    DataCell(Text(crewText(f.crew, f.passengers, dir))),
                    DataCell(Text(pricingModeLabel(f.pricingMode))),
                    DataCell(Text(formatFcfa(f.billedAmount ?? 0))),
                    DataCell(Text(f.billedTo == 'off_app'
                        ? 'Hors app'
                        : 'Compte de ${dir[f.payerUidField ?? f.payerUid]?.shortName ?? '?'}')),
                  ]),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              totalRow('Débité sur comptes', debitedTotal),
              totalRow('Facturé hors app', offAppTotal),
              if (kIsWeb) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Exporter en CSV'),
                  onPressed: () => _export(flights, dir),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
