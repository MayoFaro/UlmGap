// Lecture de settings/pricing (Firestore), fusionnée sur les valeurs par
// défaut si le document ou un champ est absent (miroir, en lecture seule, de
// finance/pricing-store.ts#readPricing). L'écriture passe uniquement par la
// Cloud Function adminUpdatePricing (règle : les clients n'écrivent jamais
// settings) ; voir FinanceApi.updatePricing.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/pricing.dart';

DocumentReference<Map<String, dynamic>> pricingDocRef(FirebaseFirestore db) =>
    db.collection('settings').doc('pricing');

Stream<Pricing> watchPricingSettings(FirebaseFirestore db) =>
    pricingDocRef(db).snapshots().map((s) => Pricing.fromMap(s.data()));
