// Dialogues de la caisse (spec §11.6) : nouvelle opération, détail et
// correction d'une opération (montant juste).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cash.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../core/pricing.dart' show defaultPricing;
import '../../core/profiles.dart';
import '../../data/app_user.dart';
import '../../data/cash_movement.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';

const _litersMissing = 'Litres obligatoires pour un achat de carburant (ou cochez « Hors cuve »).';

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
  final _liters = TextEditingController(); // plan 13 : Achat carburant seulement
  String? _error;
  bool _submitting = false;
  bool _outsideTank = false; // « Hors cuve » : achat sans entrée en cuve
  bool _litersEdited = false; // l'utilisateur a saisi les litres : fin du calcul automatique
  int _literPrice = defaultPricing.fuelLiterPrice; // prix du litre de carburant courant (§13.3)
  StreamSubscription<dynamic>? _pricingSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pricingSub != null) return;
    final finance = AppServices.of(context).finance;
    _pricingSub = finance?.watchPricing().listen((p) {
      if (!mounted) return;
      setState(() {
        _literPrice = p.fuelLiterPrice;
        _autoLiters();
      });
    });
  }

  @override
  void dispose() {
    _pricingSub?.cancel();
    _amount.dispose();
    _note.dispose();
    _liters.dispose();
    super.dispose();
  }

  /// Litres de l'Achat carburant : null si non proposés ou vides.
  bool get _hasLitersField => _kind == CashKind.fuelPurchase && !_outsideTank;

  int? get _litersValue => _hasLitersField ? int.tryParse(_liters.text.trim()) : null;

  bool get _litersFilled => _hasLitersField && _liters.text.trim().isNotEmpty;

  /// Calcul automatique des litres d'après le montant, tant que l'utilisateur
  /// n'a pas saisi les litres lui-même.
  void _autoLiters() {
    if (!_hasLitersField || _litersEdited || _literPrice <= 0) return;
    final amount = parseAmount(_amount.text);
    _liters.text = amount != null && amount > 0 ? '${(amount / _literPrice).round()}' : '';
  }

  /// Prix au litre saisi (arrondi au franc) ; null sans montant ni litres valides.
  int? _pricePerLiter() {
    final amount = parseAmount(_amount.text);
    final liters = _litersValue;
    if (amount == null || amount <= 0 || liters == null || liters < 1 || liters > 100000) return null;
    return (amount / liters).round();
  }

  /// Écart strictement supérieur à 5 % de la référence (calcul entier exact).
  bool _unusualPrice(int amount, int liters) =>
      _literPrice > 0 && (amount - _literPrice * liters).abs() * 100 > 5 * _literPrice * liters;

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
    if (_hasLitersField && !_litersFilled) return _litersMissing;
    final liters = _litersValue;
    if (_litersFilled && (liters == null || liters < 1 || liters > 100000)) {
      return 'Litres invalides (1 à 100 000).'; // message du serveur
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
    if (_hasLitersField && _unusualPrice(amount!, _litersValue!)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Prix au litre inhabituel'),
          content: Text('Prix au litre : ${_pricePerLiter()} FCFA/L '
              '(référence : $_literPrice FCFA/L). Confirmer l\'opération ?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Corriger')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
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
        await services.cash!.add(
            kind: _kind,
            amount: amount!,
            date: _date,
            note: note.isEmpty ? null : note,
            liters: _litersFilled ? _litersValue : null,
            outsideTank: _kind == CashKind.fuelPurchase && _outsideTank);
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
                onSelected: (_) => setState(() {
                  _kind = k;
                  _autoLiters();
                }),
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
            onChanged: (_) => setState(_autoLiters),
            decoration: InputDecoration(
                labelText: _kind == CashKind.cashGap ? 'Montant (signé)' : 'Montant'),
          ),
          if (_kind == CashKind.fuelPurchase)
            CheckboxListTile(
              key: const Key('cash-outside-tank'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Hors cuve'),
              value: _outsideTank,
              onChanged: (v) => setState(() {
                _outsideTank = v ?? false;
                _autoLiters();
              }),
            ),
          if (_hasLitersField) ...[
            TextField(
              key: const Key('cash-liters'),
              controller: _liters,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _litersEdited = true),
              decoration: const InputDecoration(labelText: 'Litres'),
            ),
            if (_pricePerLiter() case final price?) Text('Prix au litre : $price FCFA/L'),
          ],
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
      setState(() => _error = 'Le montant est déjà de ${formatFcfa(_isGap ? _current : _current.abs())}.');
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
          if (!m.isCorrection) Text('Montant juste : ${formatFcfa(_isGap ? _current : _current.abs())}'),
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
