// Miroir de functions/src/rules/pricing.ts (coûts, crédit disponible,
// facturation à la clôture et régularisation admin). Cas partagés :
// test/fixtures/pricing_cases.json.
import 'profiles.dart';

class Pricing {
  const Pricing({
    required this.flatFee,
    required this.includedMinutes,
    this.toleranceMinutes = 75,
    required this.minPlannedMinutes,
    required this.overtimeHourly,
    required this.fuelHourlyRate,
    this.instructionCredit = 20000,
    this.baptismFee = 70000,
  });

  final Map<UserCategory, int> flatFee;

  /// Temps couvert par le forfait : le dépassement se compte à partir de là.
  final int includedMinutes;

  /// Plan 9 : jusqu'à cette durée (incluse), le forfait seul est facturé.
  final int toleranceMinutes;
  final int minPlannedMinutes;
  final Map<UserCategory, int> overtimeHourly;
  final int fuelHourlyRate;

  /// Plan 8 : crédit versé à l'instructeur par vol d'instruction clôturé.
  final int instructionCredit;

  /// Plan 8 : prix d'un baptême de l'air (facturé hors app).
  final int baptismFee;

  /// Fusionné sur [defaultPricing] : un champ absent (document manquant, ou
  /// champ manquant dedans) prend la valeur par défaut (spec §2.4).
  factory Pricing.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaultPricing;

    Map<UserCategory, int> categoryMap(Object? v, Map<UserCategory, int> fallback) {
      // Défensif (Task 9) : sur certaines plateformes, une carte Firestore
      // imbriquée peut arriver typée `Map<Object?, Object?>` plutôt que
      // `Map<String, dynamic>` ; un cast direct lèverait alors une exception.
      final raw = (v as Map?)?.cast<String, dynamic>();
      return {
        for (final c in UserCategory.values)
          c: (raw?[c.code] as num?)?.toInt() ?? fallback[c]!,
      };
    }

    return Pricing(
      flatFee: categoryMap(m['flatFee'], defaultPricing.flatFee),
      includedMinutes: (m['includedMinutes'] as num?)?.toInt() ?? defaultPricing.includedMinutes,
      toleranceMinutes: (m['toleranceMinutes'] as num?)?.toInt() ?? defaultPricing.toleranceMinutes,
      minPlannedMinutes: (m['minPlannedMinutes'] as num?)?.toInt() ?? defaultPricing.minPlannedMinutes,
      overtimeHourly: categoryMap(m['overtimeHourly'], defaultPricing.overtimeHourly),
      fuelHourlyRate: (m['fuelHourlyRate'] as num?)?.toInt() ?? defaultPricing.fuelHourlyRate,
      instructionCredit: (m['instructionCredit'] as num?)?.toInt() ?? defaultPricing.instructionCredit,
      baptismFee: (m['baptismFee'] as num?)?.toInt() ?? defaultPricing.baptismFee,
    );
  }

  Map<String, dynamic> toMap() => {
        'flatFee': {for (final e in flatFee.entries) e.key.code: e.value},
        'includedMinutes': includedMinutes,
        'toleranceMinutes': toleranceMinutes,
        'minPlannedMinutes': minPlannedMinutes,
        'overtimeHourly': {for (final e in overtimeHourly.entries) e.key.code: e.value},
        'fuelHourlyRate': fuelHourlyRate,
        'instructionCredit': instructionCredit,
        'baptismFee': baptismFee,
      };
}

/// Tarifs par défaut (spec §2.4).
final Pricing defaultPricing = Pricing(
  flatFee: const {
    UserCategory.gap: 12000,
    UserCategory.gr: 30000,
    UserCategory.mil: 50000,
    UserCategory.ext: 70000,
  },
  includedMinutes: 60,
  toleranceMinutes: 75,
  minPlannedMinutes: 45,
  overtimeHourly: const {
    UserCategory.gap: 12000,
    UserCategory.gr: 30000,
    UserCategory.mil: 30000,
    UserCategory.ext: 30000,
  },
  fuelHourlyRate: 12000,
  instructionCredit: 20000,
  baptismFee: 70000,
);

/// Plafond des montants saisis à la clôture (shortFlightAmount, customAmount).
const maxManualAmount = 200000;

/// Coût calculé ; null si standard et durée < minPlannedMinutes (montant à saisir).
int? computedCost(String mode, int minutes, UserCategory category, Pricing p) {
  if (mode == 'fuel_only') {
    return (p.fuelHourlyRate * minutes / 60).round();
  }
  if (minutes < p.minPlannedMinutes) return null;
  if (minutes <= p.toleranceMinutes) return p.flatFee[category]!;
  // Jamais de dépassement négatif (snapshot incohérent : tolérance < temps couvert).
  final extra = minutes - p.includedMinutes;
  final overtimeMinutes = extra > 0 ? extra : 0;
  return (p.flatFee[category]! + p.overtimeHourly[category]! * overtimeMinutes / 60).round();
}

/// Coût estimé d'un vol prévu (durée prévue ≥ minimum). Le formulaire vérifie
/// déjà `plannedMinutes ≥ minPlannedMinutes`, donc computedCost ne rend
/// jamais null ici.
int estimatedCost(String mode, int plannedMinutes, UserCategory category, Pricing p) =>
    computedCost(mode, plannedMinutes, category, p)!;

/// Spec §4.4 : solde moins le coût estimé des autres vols imputés sur le compte.
int availableCredit(int balance, List<int> otherEstimatedCosts) =>
    balance - otherEstimatedCosts.fold(0, (sum, c) => sum + c);

typedef ClosingBill = ({int billedAmount, String billedTo, String pricingMode});

/// Montant facturé à la clôture. Lève [ArgumentError] si un montant requis
/// manque (même message que le serveur).
ClosingBill closingBill({
  required String mode,
  required int actualMinutes,
  required UserCategory category,
  required Pricing pricing,
  int? shortFlightAmount,
  int? customAmount,
  required bool hasPassenger,
}) {
  // Baptême de l'air : prix fixe hors app, montants saisis ignorés.
  if (mode == 'baptism') {
    return (billedAmount: pricing.baptismFee, billedTo: 'off_app', pricingMode: 'baptism');
  }
  if (customAmount != null) {
    if (!hasPassenger) {
      throw ArgumentError('Montant différent réservé aux vols avec un passager sans compte.');
    }
    return (billedAmount: customAmount, billedTo: 'off_app', pricingMode: 'custom');
  }
  final computed = computedCost(mode, actualMinutes, category, pricing);
  if (computed == null) {
    if (shortFlightAmount == null) {
      throw ArgumentError(
          'Montant à facturer obligatoire pour un vol de moins de ${pricing.minPlannedMinutes} min.');
    }
    return (billedAmount: shortFlightAmount, billedTo: 'account', pricingMode: mode);
  }
  return (billedAmount: computed, billedTo: 'account', pricingMode: mode);
}

/// Une facture (avant ou après correction) telle que stockée sur le vol :
/// `billedTo` vaut `'account'`, `'off_app'` ou `null` (jamais facturé).
typedef BillLeg = ({String? billedTo, String? payerUid, int amount});

/// Miroir exact de functions/src/rules/pricing.ts#adjustments : régularisation
/// admin d'un vol clôturé (spec §4.5). Rend un mouvement par compte impacté
/// (montants nuls omis, ordre de première apparition) : l'ancien montant
/// facturé est remboursé au compte débité *avant* correction (s'il était
/// imputé sur un solde), le nouveau est débité du compte débité *après*
/// correction (de même). `amount` est le montant à appliquer tel quel au
/// solde (positif = crédit/remboursement, négatif = débit).
List<({String uid, int amount})> adjustments(BillLeg before, BillLeg after) {
  final totals = <String, int>{};
  final order = <String>[];
  void add(String? uid, int amount) {
    if (uid == null) return;
    if (!totals.containsKey(uid)) {
      totals[uid] = 0;
      order.add(uid);
    }
    totals[uid] = totals[uid]! + amount;
  }

  if (before.billedTo == 'account') add(before.payerUid, before.amount);
  if (after.billedTo == 'account') add(after.payerUid, -after.amount);

  return [
    for (final uid in order)
      if (totals[uid] != 0) (uid: uid, amount: totals[uid]!),
  ];
}
