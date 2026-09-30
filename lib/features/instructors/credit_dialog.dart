// Dialogue « Créditer / corriger » (écran Instructeurs) : crédit (montant
// positif, motif facultatif) ou correction (montant signé non nul, motif
// obligatoire), sans plafond (décision utilisateur : pas de plafond sur les
// versements, ni sur les corrections pour pouvoir annuler un versement
// erroné en une seule fois). Appelle l'API lui-même et affiche le nouveau
// solde par SnackBar une fois le dialogue refermé.
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/flight_api.dart' show FlightFailure;
import '../../data/services.dart';

enum _Mode { credit, correction }

class CreditDialog extends StatefulWidget {
  const CreditDialog({super.key, required this.uid});
  final String uid;

  @override
  State<CreditDialog> createState() => _CreditDialogState();
}

class _CreditDialogState extends State<CreditDialog> {
  _Mode _mode = _Mode.credit;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parseAmount(_amount.text);
    final reason = _reason.text.trim();
    if (_mode == _Mode.credit) {
      if (amount == null || amount <= 0) {
        setState(() => _error = 'Montant invalide (positif).');
        return;
      }
    } else {
      if (amount == null || amount == 0) {
        setState(() => _error = 'Montant invalide (non nul).');
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
      final balance = _mode == _Mode.credit
          ? await finance.credit(widget.uid, amount, reason.isEmpty ? null : reason)
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
    return AlertDialog(
      title: const Text('Créditer / corriger'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, children: [
              ChoiceChip(
                label: const Text('Créditer'),
                selected: _mode == _Mode.credit,
                onSelected: (_) => setState(() => _mode = _Mode.credit),
              ),
              ChoiceChip(
                label: const Text('Corriger'),
                selected: _mode == _Mode.correction,
                onSelected: (_) => setState(() => _mode = _Mode.correction),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              key: const Key('credit-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(
                labelText: _mode == _Mode.credit ? 'Montant' : 'Montant (signé)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('credit-reason'),
              controller: _reason,
              maxLength: 200,
              decoration: InputDecoration(
                labelText:
                    _mode == _Mode.correction ? 'Motif (obligatoire)' : 'Motif (facultatif)',
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
