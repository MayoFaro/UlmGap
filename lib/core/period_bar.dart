// Sélecteur de période « Du … / Au … » (relevé, vols effectués, compteurs).
// Bornes en [from, to[ : `to` est le lendemain du dernier jour inclus, comme
// FinanceApi.watchFlightsBetween.
import 'package:flutter/material.dart';

import 'formats.dart';

class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
    this.lastDay,
    this.enabled = true,
  });

  final DateTime from;
  final DateTime to;
  final void Function(DateTime from, DateTime to) onChanged;

  /// Dernier jour sélectionnable (défaut : 31/12/2100).
  final DateTime? lastDay;
  final bool enabled;

  DateTime get _lastIncludedDay => DateTime(to.year, to.month, to.day - 1);

  Future<void> _pickFrom(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from,
      firstDate: DateTime(2020),
      lastDate: _lastIncludedDay,
    );
    if (d != null) onChanged(DateTime(d.year, d.month, d.day), to);
  }

  Future<void> _pickTo(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _lastIncludedDay,
      firstDate: from,
      lastDate: lastDay ?? DateTime(2100, 12, 31),
    );
    if (d != null) onChanged(from, DateTime(d.year, d.month, d.day + 1));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('period-from'),
              onPressed: enabled ? () => _pickFrom(context) : null,
              child: Text('Du ${formatDay(from)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('period-to'),
              onPressed: enabled ? () => _pickTo(context) : null,
              child: Text('Au ${formatDay(_lastIncludedDay)}'),
            ),
          ),
        ]),
      );
}
