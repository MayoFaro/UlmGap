// Dialogue « Clôturer le vol » (Task 9, spec §4.3), extrait de
// flight_screen.dart (Task 9, fix round 1) pour ne pas faire grossir cet
// écran davantage (Task 10 y ajoute encore des actions admin).
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/pricing.dart';
import '../../core/profiles.dart';

/// Saisie validée du dialogue de clôture, prête pour FinanceApi.closeFlight.
class ClosingResult {
  const ClosingResult(this.actualMinutes, this.shortFlightAmount, this.customAmount,
      {this.landings = 1, this.waterLandings = 0});
  final int actualMinutes;
  final int? shortFlightAmount;
  final int? customAmount;
  final int landings;
  final int waterLandings;
}

/// Plan 4b, décision 3 : contrôle des nombres saisis à la clôture (et à la
/// correction admin) ; null si valides. Même règle et mêmes messages que le
/// serveur (validateClosing).
String? landingsError(int? landings, int? waterLandings) {
  bool ok(int? v) => v != null && v >= 0 && v <= 99;
  if (!ok(landings)) return 'Nombre d\'atterrissages invalide (0 à 99).';
  if (!ok(waterLandings)) return 'Nombre d\'amerrissages invalide (0 à 99).';
  if (landings! + waterLandings! < 1) return 'Au moins un atterrissage ou amerrissage.';
  return null;
}

/// Dialogue « Clôturer le vol » (Task 9, spec §4.3) : durée réelle
/// (préremplie avec la durée prévue), montant à facturer si le vol est plus
/// court que le minimum tarifaire, montant différent si un passager sans
/// compte est à bord, aperçu du montant calculé par [closingBill] et plafond
/// local de 200 000 FCFA sur les montants saisis (décision 5).
///
/// [category] peut être `null` (fix round 1, décision utilisateur 2) : un
/// membre d'équipage non-staff qui n'est pas le compte débité ne connaît pas
/// forcément l'appartenance de celui-ci (`watchCategories` réservé aux
/// instructeurs/admins). La clôture reste alors possible — seul l'aperçu
/// local du montant est indisponible ; le serveur calcule et facture
/// normalement.
class ClosingDialog extends StatefulWidget {
  const ClosingDialog({
    super.key,
    required this.plannedMinutes,
    required this.mode,
    required this.category,
    required this.pricing,
    required this.hasPassenger,
    this.amphibious = false,
  });

  final int plannedMinutes;
  final String mode; // 'standard' | 'fuel_only'
  final UserCategory? category;
  final Pricing pricing;
  final bool hasPassenger;

  /// Appareil amphibie : champ « Amerrissages » (plan 4b).
  final bool amphibious;

  @override
  State<ClosingDialog> createState() => _ClosingDialogState();
}

class _ClosingDialogState extends State<ClosingDialog> {
  late final _minutes = TextEditingController(text: '${widget.plannedMinutes}');
  final _shortAmount = TextEditingController();
  final _customAmount = TextEditingController();
  final _landings = TextEditingController(text: '1');
  final _waterLandings = TextEditingController(text: '0');
  bool _customChecked = false;
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _shortAmount.dispose();
    _customAmount.dispose();
    _landings.dispose();
    _waterLandings.dispose();
    super.dispose();
  }

  int? get _actualMinutes => int.tryParse(_minutes.text.trim());

  /// Mode standard et durée réelle sous le minimum tarifaire (spec §4.3) :
  /// un vol carburant seulement est toujours calculé à la minute. Ne dépend
  /// pas de la catégorie : reste correct même si celle-ci est inconnue.
  bool get _needsShortAmount {
    final m = _actualMinutes;
    return widget.mode == 'standard' && m != null && m < widget.pricing.minPlannedMinutes;
  }

  /// Aperçu indicatif ; `null` si la catégorie est inconnue (fix round 1) ou
  /// tant que les champs requis manquent (pas d'erreur affichée ici : celle-ci
  /// n'apparaît qu'à la validation, dans [_submit]).
  int? get _preview {
    final category = widget.category;
    if (category == null) return null;
    final m = _actualMinutes;
    if (m == null) return null;
    final shortAmount = _needsShortAmount ? parseAmount(_shortAmount.text) : null;
    if (_needsShortAmount && shortAmount == null) return null;
    final customAmount = _customChecked ? parseAmount(_customAmount.text) : null;
    if (_customChecked && customAmount == null) return null;
    try {
      return closingBill(
        mode: widget.mode,
        actualMinutes: m,
        category: category,
        pricing: widget.pricing,
        shortFlightAmount: shortAmount,
        customAmount: customAmount,
        hasPassenger: widget.hasPassenger,
      ).billedAmount;
    } on ArgumentError {
      return null;
    }
  }

  void _submit() {
    final m = _actualMinutes;
    if (m == null || m < 1 || m > 720) {
      setState(() => _error = 'Durée réelle invalide (1 à 720 min).');
      return;
    }
    int? shortAmount;
    if (_needsShortAmount) {
      shortAmount = parseAmount(_shortAmount.text);
      if (shortAmount == null) {
        setState(() => _error = 'Montant à facturer obligatoire pour un vol de moins de '
            '${widget.pricing.minPlannedMinutes} min.');
        return;
      }
      if (shortAmount > maxManualAmount) {
        setState(() => _error = 'Montant trop élevé (200 000 FCFA au maximum).');
        return;
      }
    }
    int? customAmount;
    if (_customChecked) {
      customAmount = parseAmount(_customAmount.text);
      if (customAmount == null) {
        setState(() => _error = 'Indiquez le montant.');
        return;
      }
      if (customAmount > maxManualAmount) {
        setState(() => _error = 'Montant trop élevé (200 000 FCFA au maximum).');
        return;
      }
    }
    final landings = int.tryParse(_landings.text.trim());
    final waterLandings = widget.amphibious ? int.tryParse(_waterLandings.text.trim()) : 0;
    final countError = landingsError(landings, waterLandings);
    if (countError != null) {
      setState(() => _error = countError);
      return;
    }
    Navigator.pop(context, ClosingResult(m, shortAmount, customAmount,
        landings: landings!, waterLandings: waterLandings!));
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Clôturer le vol'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('closing-minutes'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Durée réelle (minutes)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('closing-landings'),
              controller: _landings,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Atterrissages'),
            ),
            if (widget.amphibious)
              TextField(
                key: const Key('closing-water-landings'),
                controller: _waterLandings,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amerrissages'),
              ),
            if (_needsShortAmount) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('closing-short-amount'),
                controller: _shortAmount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant à facturer'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (widget.hasPassenger) ...[
              CheckboxListTile(
                key: const Key('closing-custom-check'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Montant différent (facturé hors app)'),
                value: _customChecked,
                onChanged: (v) => setState(() => _customChecked = v ?? false),
              ),
              if (_customChecked)
                TextField(
                  key: const Key('closing-custom-amount'),
                  controller: _customAmount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Montant'),
                  onChanged: (_) => setState(() {}),
                ),
            ],
            const SizedBox(height: 12),
            if (widget.category == null)
              const Text('Montant calculé par le serveur à la clôture.')
            else if (preview != null)
              Text('Montant : ${formatFcfa(preview)}'),
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
        FilledButton(onPressed: _submit, child: const Text('Clôturer')),
      ],
    );
  }
}
