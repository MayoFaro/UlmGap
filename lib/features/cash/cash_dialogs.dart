// Dialogues de la caisse (spec §11.6) : nouvelle opération, détail et
// correction d'une opération (montant juste).
import 'package:flutter/material.dart';

import '../../core/cash.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../core/profiles.dart';
import '../../data/app_user.dart';
import '../../data/cash_movement.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';

const _uncertain = 'Opération incertaine : vérifiez la caisse avant de réessayer.';

Widget _errorText(BuildContext context, String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );

class CashOperationDialog extends StatefulWidget {
  const CashOperationDialog({super.key, required this.isAdmin, required this.accounts, required this.now});
  final bool isAdmin;
  final List<AppUser> accounts;
  final DateTime Function() now;

  @override
  State<CashOperationDialog> createState() => _CashOperationDialogState();
}

class _CashOperationDialogState extends State<CashOperationDialog> {
  CashKind _kind = CashKind.fuelCredit;
  String? _account;
  late DateTime _date = dayOf(widget.now());
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _noteLabel => switch (_kind) {
        CashKind.cashGap => 'Motif (obligatoire)',
        CashKind.maintenance || CashKind.offAppIncome => 'Objet (obligatoire)',
        _ => 'Note (facultative)',
      };

  String? _check(int? amount, String note) {
    if (amount == null || amount == 0 || (_kind != CashKind.cashGap && amount < 0)) {
      return _kind == CashKind.cashGap ? 'Montant invalide (non nul).' : 'Montant invalide (positif).';
    }
    if (_kind == CashKind.fuelCredit && _account == null) return 'Choisissez l\'adhérent.';
    if (_kind == CashKind.cashGap && note.isEmpty) return 'Motif obligatoire pour un écart de caisse.';
    if ((_kind == CashKind.maintenance || _kind == CashKind.offAppIncome) && note.isEmpty) {
      return 'Objet obligatoire.';
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = parseAmount(_amount.text);
    final note = _note.text.trim();
    final error = _check(amount, note);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final services = AppServices.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      if (_kind == CashKind.fuelCredit) {
        await services.finance!.credit(_account!, amount!, note.isEmpty ? null : note, date: _date);
      } else {
        await services.cash!.add(kind: _kind, amount: amount!, date: _date, note: note.isEmpty ? null : note);
      }
      if (!mounted) return;
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

  Future<void> _pickDate() async {
    final today = dayOf(widget.now());
    final picked = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: today);
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [
      CashKind.fuelCredit, CashKind.fuelPurchase, CashKind.maintenance, CashKind.offAppIncome,
      if (widget.isAdmin) CashKind.cashGap,
    ];
    final accounts = sortedByProfile(widget.accounts, (a) => a.profile, (a) => a.displayName);
    return AlertDialog(
      title: const Text('Nouvelle opération'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in kinds)
              ChoiceChip(
                avatar: Icon(k.icon, size: 18),
                label: Text(k.label),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ]),
          if (_kind == CashKind.fuelCredit)
            DropdownButtonFormField<String>(
              key: const Key('cash-account'),
              value: _account,
              decoration: const InputDecoration(labelText: 'Adhérent'),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.uid, child: Text('${a.shortName} · ${a.displayName}')),
              ],
              onChanged: (v) => setState(() => _account = v),
            ),
          TextField(
            key: const Key('cash-amount'),
            controller: _amount,
            keyboardType: TextInputType.numberWithOptions(signed: _kind == CashKind.cashGap),
            inputFormatters: const [AmountInputFormatter()],
            decoration: InputDecoration(
                labelText: _kind == CashKind.cashGap ? 'Montant (signé)' : 'Montant'),
          ),
          TextButton.icon(
            key: const Key('cash-date'),
            icon: const Icon(Icons.event),
            label: Text('Date : ${formatShortDate(_date)}'),
            onPressed: _pickDate,
          ),
          TextField(
            key: const Key('cash-note'),
            controller: _note,
            maxLength: 200,
            decoration: InputDecoration(labelText: _noteLabel),
          ),
          _errorText(context, _error),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Valider')),
      ],
    );
  }
}

class CashMovementDialog extends StatefulWidget {
  const CashMovementDialog({
    super.key,
    required this.movement,
    required this.all,
    required this.title,
    required this.shortNames,
    required this.isAdmin,
  });
  final CashMovement movement;
  final List<CashMovement> all;
  final String title;
  final Map<String, String> shortNames;
  final bool isAdmin;

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _submitting = false;

  CashMovement get m => widget.movement;
  int get _current => effectiveAmount(m, widget.all);
  bool get _isGap => m.kind == CashKind.cashGap;

  bool get _canCorrect =>
      !m.isCorrection &&
      m.kind != null &&
      (widget.isAdmin || (m.kind != CashKind.cashGap && m.kind != CashKind.opening));

  @override
  void initState() {
    super.initState();
    _amount.text = formatAmountInput(_isGap ? _current : _current.abs());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _correct() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || (!_isGap && amount < 0)) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    if ((_isGap ? amount : amount * (m.kind!.sign)) == _current) {
      setState(() => _error = 'Le montant est déjà de ${formatFcfa(_current.abs())}.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final note = _note.text.trim();
      await AppServices.of(context).cash!.correct(m.id, amount: amount, note: note.isEmpty ? null : note);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Correction enregistrée.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is FlightFailure ? e.message : _uncertain;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final by = m.by == 'import' ? 'Import' : (widget.shortNames[m.by] ?? m.by);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Date : ${formatShortDate(m.day)}'),
          Text('Montant : ${formatFcfa(m.amount)}'),
          if (m.note != null && m.note!.isNotEmpty) Text('Note : ${m.note}'),
          Text('Saisie : $by, le ${formatShortDate(m.at)}'),
          if (m.isCorrection) const Text('Correction d\'une opération.'),
          if (!m.isCorrection) Text('Montant juste : ${formatFcfa(_current.abs())}'),
          if (_canCorrect) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('cash-correct-amount'),
              controller: _amount,
              keyboardType: TextInputType.numberWithOptions(signed: _isGap),
              inputFormatters: const [AmountInputFormatter()],
              decoration: const InputDecoration(labelText: 'Montant juste (0 annule)'),
            ),
            TextField(
              key: const Key('cash-correct-note'),
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
            ),
          ],
          _errorText(context, _error),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        if (_canCorrect)
          FilledButton(onPressed: _submitting ? null : _correct, child: const Text('Corriger')),
      ],
    );
  }
}
