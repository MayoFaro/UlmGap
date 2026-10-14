// Dialogue « Crédit carburant / corriger » (écran Pilotes) : crédit carburant
// (montant positif, date de versement, motif facultatif) ou correction (nouveau solde, pré-rempli avec
// le solde actuel, motif obligatoire ; révision du 2026-10-01), sans plafond (décision utilisateur : pas de plafond sur les
// versements, ni sur les corrections pour pouvoir annuler un versement
// erroné en une seule fois). La puce « Corriger » n'existe que pendant la
// reprise de la caisse (masquée une fois la reprise clôturée). Appelle l'API lui-même et affiche le nouveau
// solde par SnackBar une fois le dialogue refermé.
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/money.dart';
import '../../data/cash_movement.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';

enum _Mode { credit, correction }

class CreditDialog extends StatefulWidget {
  const CreditDialog({super.key, required this.uid, required this.balance});
  final String uid;

  /// Solde actuel : affiché et pré-rempli en mode « Corriger ».
  final int balance;

  @override
  State<CreditDialog> createState() => _CreditDialogState();
}

class _CreditDialogState extends State<CreditDialog> {
  _Mode _mode = _Mode.credit;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _error;
  bool _submitting = false;
  bool _migrationClosed = false;
  DateTime _date = dayOf(DateTime.now());

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2020),
        lastDate: dayOf(DateTime.now()));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_migrationClosed && _mode == _Mode.correction) return; // reset en attente
    final mode = _migrationClosed ? _Mode.credit : _mode;
    final amount = parseAmount(_amount.text);
    final reason = _reason.text.trim();
    if (mode == _Mode.credit) {
      if (amount == null || amount <= 0) {
        setState(() => _error = 'Montant invalide (positif).');
        return;
      }
    } else {
      if (amount == null) {
        setState(() => _error = 'Nouveau solde invalide.');
        return;
      }
      if (amount == widget.balance) {
        setState(() => _error = 'Le solde est déjà de ${formatFcfa(widget.balance)}.');
        return;
      }
      if (reason.isEmpty) {
        setState(() => _error = 'Motif obligatoire pour une correction.');
        return;
      }
    }
    final finance = AppServices.of(context).finance!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final balance = mode == _Mode.credit
          ? await finance.credit(widget.uid, amount, reason.isEmpty ? null : reason,
              date: _date)
          : await finance.correct(widget.uid, amount, reason);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Nouveau solde : ${formatFcfa(balance)}')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Refus du serveur : son message. Autre erreur (réseau, délai) :
        // l'opération a pu aboutir, d'où la vérification du solde avant
        // de réessayer (pas de double versement).
        _error = e is FlightFailure
            ? e.message
            : 'Opération incertaine : vérifiez le solde avant de réessayer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cashbox =
        AppServices.of(context).cash?.watchCashbox() ?? Stream.value(Cashbox.empty);
    return StreamBuilder<Cashbox>(
      stream: cashbox,
      builder: (context, snap) {
        _migrationClosed = snap.data?.migrationClosed ?? false;
        if (_migrationClosed && _mode == _Mode.correction) {
          // La reprise vient d'être clôturée : retour au crédit, sans le
          // solde pré-rempli pour la correction (hors build).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _mode != _Mode.correction) return;
            setState(() {
              _mode = _Mode.credit;
              _amount.clear();
            });
          });
        }
        return _dialog(context);
      },
    );
  }

  Widget _dialog(BuildContext context) {
    final mode = _migrationClosed ? _Mode.credit : _mode;
    return AlertDialog(
      title: const Text('Crédit carburant / corriger'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, children: [
              ChoiceChip(
                label: const Text('Crédit carburant'),
                selected: mode == _Mode.credit,
                onSelected: (_) => setState(() {
                  _mode = _Mode.credit;
                  _amount.clear();
                }),
              ),
              if (!_migrationClosed)
                ChoiceChip(
                label: const Text('Corriger'),
                selected: mode == _Mode.correction,
                onSelected: (_) => setState(() {
                  _mode = _Mode.correction;
                  _amount.text = formatAmountInput(widget.balance);
                }),
              ),
            ]),
            const SizedBox(height: 12),
            if (mode == _Mode.correction)
              Text('Solde actuel : ${formatFcfa(widget.balance)}'),
            TextField(
              key: const Key('credit-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              inputFormatters: const [AmountInputFormatter()],
              decoration: InputDecoration(
                labelText: mode == _Mode.credit ? 'Montant' : 'Nouveau solde',
              ),
            ),
            if (mode == _Mode.credit)
              TextButton.icon(
                key: const Key('credit-date'),
                icon: const Icon(Icons.event),
                label: Text('Date : ${formatShortDate(_date)}'),
                onPressed: _pickDate,
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('credit-reason'),
              controller: _reason,
              maxLength: 200,
              decoration: InputDecoration(
                labelText:
                    mode == _Mode.correction ? 'Motif (obligatoire)' : 'Motif (facultatif)',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Valider')),
      ],
    );
  }
}
