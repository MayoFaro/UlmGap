// Écran « Tarifs » (admin) : édition de settings/pricing via
// adminUpdatePricing (Task 12).
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/pricing.dart';
import '../../core/profiles.dart';
import '../../data/services.dart';

class PricingAdminScreen extends StatefulWidget {
  const PricingAdminScreen({super.key});

  @override
  State<PricingAdminScreen> createState() => _PricingAdminScreenState();
}

class _PricingAdminScreenState extends State<PricingAdminScreen> {
  final _form = GlobalKey<FormState>();
  final _flatFee = {for (final c in UserCategory.values) c: TextEditingController()};
  final _overtimeHourly = {for (final c in UserCategory.values) c: TextEditingController()};
  final _includedMinutes = TextEditingController();
  final _minPlannedMinutes = TextEditingController();
  final _fuelHourlyRate = TextEditingController();

  // Préremplissage une seule fois (au premier tarif reçu), pour ne pas
  // écraser la saisie en cours si le flux réémet (ex. après enregistrement).
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _flatFee.values) {
      c.dispose();
    }
    for (final c in _overtimeHourly.values) {
      c.dispose();
    }
    _includedMinutes.dispose();
    _minPlannedMinutes.dispose();
    _fuelHourlyRate.dispose();
    super.dispose();
  }

  void _prefill(Pricing p) {
    for (final c in UserCategory.values) {
      _flatFee[c]!.text = p.flatFee[c]!.toString();
      _overtimeHourly[c]!.text = p.overtimeHourly[c]!.toString();
    }
    _includedMinutes.text = p.includedMinutes.toString();
    _minPlannedMinutes.text = p.minPlannedMinutes.toString();
    _fuelHourlyRate.text = p.fuelHourlyRate.toString();
  }

  // Plages identiques au serveur (functions/src/finance/validation.ts).
  String? _validateAmount(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'Nombre entier requis.';
    if (n < 0 || n > 1000000) return 'Entre 0 et ${formatFcfa(1000000)}.';
    return null;
  }

  String? _validateMinutes(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'Nombre entier requis.';
    if (n < 1 || n > 600) return 'Entre 1 et 600 min.';
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final pricing = Pricing(
      flatFee: {for (final c in UserCategory.values) c: int.parse(_flatFee[c]!.text.trim())},
      includedMinutes: int.parse(_includedMinutes.text.trim()),
      minPlannedMinutes: int.parse(_minPlannedMinutes.text.trim()),
      overtimeHourly: {
        for (final c in UserCategory.values) c: int.parse(_overtimeHourly[c]!.text.trim())
      },
      fuelHourlyRate: int.parse(_fuelHourlyRate.text.trim()),
    );
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await AppServices.of(context).finance!.updatePricing(pricing);
      messenger.showSnackBar(const SnackBar(content: Text('Tarifs enregistrés.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final finance = AppServices.of(context).finance!;
    return Scaffold(
      appBar: AppBar(title: const Text('Tarifs')),
      body: StreamBuilder<Pricing>(
        stream: finance.watchPricing(),
        builder: (context, snap) {
          final pricing = snap.data;
          if (pricing == null) return const Center(child: CircularProgressIndicator());
          if (!_prefilled) {
            _prefill(pricing);
            _prefilled = true;
          }
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Forfait par appartenance', style: Theme.of(context).textTheme.titleMedium),
                for (final c in UserCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextFormField(
                      key: Key('flatFee-${c.code}'),
                      controller: _flatFee[c],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Forfait ${c.code} (FCFA)'),
                      validator: _validateAmount,
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Taux de dépassement par appartenance',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final c in UserCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextFormField(
                      key: Key('overtime-${c.code}'),
                      controller: _overtimeHourly[c],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Dépassement ${c.code} (FCFA/h)'),
                      validator: _validateAmount,
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('includedMinutes'),
                  controller: _includedMinutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minutes incluses'),
                  validator: _validateMinutes,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('minPlannedMinutes'),
                  controller: _minPlannedMinutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée prévue minimale (min)'),
                  validator: _validateMinutes,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('fuelHourlyRate'),
                  controller: _fuelHourlyRate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Carburant (FCFA/h)'),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
