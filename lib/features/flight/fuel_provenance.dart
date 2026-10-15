// Provenance du carburant ajouté (spec §13.2) : choix « Aucun » / « Depuis
// la cuve » / « Bidon perso » / « Les deux », litres et pilote fournisseur.
// Partagé par le dialogue de clôture et la correction admin d'un vol clôturé.
import 'package:flutter/material.dart';

import '../../core/fuel.dart' show maxFuelLiters;
import '../../core/money.dart';
import '../../data/flight.dart';

enum FuelSource {
  none('Aucun'),
  tank('Depuis la cuve'),
  personal('Bidon perso'),
  both('Les deux');

  const FuelSource(this.label);
  final String label;

  bool get usesTank => this == tank || this == both;
  bool get usesPersonal => this == personal || this == both;
}

/// Messages identiques au serveur (functions/src/flights/validation.ts).
const fuelTotalMessage = 'Carburant ajouté : $maxFuelLiters L au maximum au total.';
const fuelSupplierMessage = 'Choisissez le pilote qui a fourni le carburant.';

/// Pilote fournisseur par défaut : [me] s'il est dans l'équipage, sinon le
/// premier équipier ; null sans équipier.
String? defaultFuelSupplier(List<String> crew, String? me) =>
    crew.contains(me) ? me : (crew.isEmpty ? null : crew.first);

/// Saisie de la provenance, détenue par l'écran parent (qui la libère).
/// [source] null : aucun choix fait (correction d'un vol clôturé avant le
/// plan 13) ; rien n'est alors envoyé.
class FuelProvenanceInput {
  FuelProvenanceInput({this.source, this.supplierUid, this.legacy = false});

  /// Pré-remplie depuis un vol clôturé ; sans provenance enregistrée (vol
  /// d'avant le plan 13), aucun choix n'est fait.
  factory FuelProvenanceInput.fromFlight(Flight f, {String? defaultSupplier}) {
    final tank = f.fuelFromTankLiters;
    if (tank == null) return FuelProvenanceInput(supplierUid: defaultSupplier, legacy: true);
    final personal = f.fuelFromPersonalLiters ?? 0;
    final source = tank > 0 && personal > 0
        ? FuelSource.both
        : tank > 0
            ? FuelSource.tank
            : personal > 0
                ? FuelSource.personal
                : FuelSource.none;
    return FuelProvenanceInput(source: source, supplierUid: f.fuelSupplierUid ?? defaultSupplier)
      ..tank.text = tank > 0 ? '$tank' : ''
      ..personal.text = personal > 0 ? '$personal' : '';
  }

  /// Vol clôturé avant le plan 13 : « Aucun » revient à l'absence de choix
  /// (mode historique), sans quoi un 0 L écraserait l'ajouté enregistré.
  final bool legacy;

  FuelSource? source;
  final tank = TextEditingController();
  final personal = TextEditingController();
  String? supplierUid;

  void dispose() {
    tank.dispose();
    personal.dispose();
  }

  int? _read(TextEditingController c, bool used) => used ? int.tryParse(c.text.trim()) : 0;

  /// Litres saisis (0 si le champ n'est pas proposé, null si illisible).
  int? get tankLiters => _read(tank, source?.usesTank ?? false);
  int? get personalLiters => _read(personal, source?.usesPersonal ?? false);

  /// Total affiché ; null tant qu'un champ proposé est illisible.
  int? get total {
    final t = tankLiters, p = personalLiters;
    return t == null || p == null ? null : t + p;
  }

  /// null si la saisie est valide ; [crew] : équipiers avec compte.
  String? error(List<String> crew) {
    final s = source;
    if (s == null) return null;
    bool ok(int? v) => v != null && v >= 1 && v <= maxFuelLiters;
    if (s.usesTank && !ok(tankLiters)) {
      return 'Litres pris à la cuve invalides (1 à $maxFuelLiters L).';
    }
    if (s.usesPersonal && !ok(personalLiters)) {
      return 'Litres du bidon perso invalides (1 à $maxFuelLiters L).';
    }
    if (total! > maxFuelLiters) return fuelTotalMessage;
    if (s.usesPersonal && !crew.contains(supplierUid)) return fuelSupplierMessage;
    return null;
  }

  /// Pilote envoyé : seulement avec un bidon perso.
  String? get sentSupplier => (source?.usesPersonal ?? false) ? supplierUid : null;
}

/// Champs de la provenance. [crewNames] : équipiers avec compte (uid → nom
/// court), dans l'ordre ; [literPrice] : prix du litre du bidon perso.
class FuelProvenanceFields extends StatelessWidget {
  const FuelProvenanceFields({
    super.key,
    required this.input,
    required this.crewNames,
    required this.literPrice,
    required this.onChanged,
  });

  final FuelProvenanceInput input;
  final Map<String, String> crewNames;
  final num literPrice;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final source = input.source;
    final total = input.total;
    final personal = input.personalLiters;
    final supplier = crewNames.containsKey(input.supplierUid) ? input.supplierUid : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('Carburant ajouté')),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final s in FuelSource.values)
            ChoiceChip(
              key: Key('fuel-source-${s.name}'),
              label: Text(s.label),
              selected: source == s,
              onSelected: (_) {
                input.source = s == FuelSource.none && input.legacy ? null : s;
                onChanged();
              },
            ),
        ]),
        if (source?.usesTank ?? false)
          TextField(
            key: const Key('fuel-tank'),
            controller: input.tank,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Litres pris à la cuve'),
            onChanged: (_) => onChanged(),
          ),
        if (source?.usesPersonal ?? false) ...[
          TextField(
            key: const Key('fuel-personal'),
            controller: input.personal,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Litres du bidon perso'),
            onChanged: (_) => onChanged(),
          ),
          DropdownButtonFormField<String>(
            key: const Key('fuel-supplier'),
            value: supplier,
            decoration: const InputDecoration(labelText: 'Pilote ayant fourni le carburant'),
            items: [
              for (final e in crewNames.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              input.supplierUid = v;
              onChanged();
            },
          ),
        ],
        if (source != null && source != FuelSource.none && total != null)
          Text('Carburant ajouté : $total L', key: const Key('fuel-added-total')),
        if ((source?.usesPersonal ?? false) && personal != null && personal > 0 && supplier != null)
          Text('Crédit : $personal L × ${formatAmountInput(literPrice.round())} = '
              '${formatFcfa((personal * literPrice).round())} pour ${crewNames[supplier]}'),
      ],
    );
  }
}
