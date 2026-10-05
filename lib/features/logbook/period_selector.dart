// Sélecteur de période du carnet de vol (spec §5) : menu des mois (plus
// « Année »), menu de l'année, bouton « Période précise ». Partagé avec le
// suivi carburant (spec §9.5). Mois en cours par défaut.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import 'logbook.dart';

/// Choix d'une période précise : début et fin, bornes incluses.
typedef RangePicker = Future<DateTimeRange?> Function(
    BuildContext context, DateTimeRange? initial);

/// Période [from, to[ par défaut : le mois en cours.
({DateTime from, DateTime to}) initialPeriod(DateTime now) => monthPeriod(now.year, now.month);

class PeriodSelector extends StatefulWidget {
  const PeriodSelector({
    super.key,
    required this.now,
    required this.onChanged,
    this.pickRange,
  });

  final DateTime Function() now;

  /// Nouvelle période [from, to[ (`to` : lendemain du dernier jour inclus).
  final void Function(DateTime from, DateTime to) onChanged;

  /// Calendrier de période précise ; par défaut, showDateRangePicker.
  final RangePicker? pickRange;

  @override
  State<PeriodSelector> createState() => _PeriodSelectorState();
}

class _PeriodSelectorState extends State<PeriodSelector> {
  late int _year;
  late int _month; // 1 à 12, ou 0 pour l'année entière
  DateTimeRange? _custom; // période précise, bornes incluses

  ({DateTime from, DateTime to}) get _period {
    final c = _custom;
    if (c == null) return monthPeriod(_year, _month);
    return (from: dayOf(c.start), to: DateTime(c.end.year, c.end.month, c.end.day + 1));
  }

  @override
  void initState() {
    super.initState();
    final n = widget.now();
    _year = n.year;
    _month = n.month;
  }

  void _set({int? year, int? month, DateTimeRange? custom}) {
    setState(() {
      if (year != null) _year = year;
      if (month != null) _month = month;
      _custom = custom;
    });
    final p = _period;
    widget.onChanged(p.from, p.to);
  }

  Future<void> _pickCustom() async {
    final today = dayOf(widget.now());
    final p = _period;
    final lastIncluded = DateTime(p.to.year, p.to.month, p.to.day - 1);
    final initial = p.from.isAfter(today)
        ? null
        : DateTimeRange(start: p.from, end: lastIncluded.isAfter(today) ? today : lastIncluded);
    final pick = widget.pickRange ??
        (context, initial) => showDateRangePicker(
              context: context,
              firstDate: DateTime(firstLogbookYear),
              lastDate: today,
              initialDateRange: initial,
            );
    final r = await pick(context, initial);
    if (r != null && mounted) _set(custom: r);
  }

  @override
  Widget build(BuildContext context) {
    final c = _custom;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<int>(
          key: const Key('month-select'),
          value: c == null ? _month : null,
          hint: const Text('Mois'),
          onChanged: (m) => _set(month: m),
          items: [
            for (var m = 1; m <= 12; m++)
              DropdownMenuItem(value: m, child: Text(formatMonth(m))),
            const DropdownMenuItem(value: 0, child: Text('Année')),
          ],
        ),
        DropdownButton<int>(
          key: const Key('year-select'),
          value: _year,
          onChanged: (y) => _set(year: y),
          items: [
            for (final y in logbookYears(widget.now()))
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
        ),
        OutlinedButton.icon(
          key: const Key('custom-period'),
          icon: const Icon(Icons.date_range),
          label: Text(c == null
              ? 'Période précise'
              : 'Du ${formatShortDate(c.start)} au ${formatShortDate(c.end)}'),
          onPressed: _pickCustom,
        ),
      ],
    );
  }
}
