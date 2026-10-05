// Lecture de settings/pricing en transaction (fusion sur DEFAULT_PRICING) et
// callable admin de mise à jour. Écriture : adminUpdatePricing seulement.
import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { DEFAULT_PRICING, Pricing, pricingWithDefaults } from "../rules/pricing";
import { validatePricing } from "./validation";

type Db = FirebaseFirestore.Firestore;
type Tx = FirebaseFirestore.Transaction;

const pricingRef = (db: Db) => db.collection("settings").doc("pricing");

/**
 * settings/pricing fusionné sur DEFAULT_PRICING : un champ absent (document
 * manquant, ou champ manquant dedans) prend la valeur par défaut (spec §2.4).
 */
export async function readPricing(tx: Tx, db: Db): Promise<Pricing> {
  const snap = await tx.get(pricingRef(db));
  if (!snap.exists) return DEFAULT_PRICING;
  return pricingWithDefaults(snap.data() as Partial<Pricing> | undefined);
}

/** Admin seulement ; remplace intégralement settings/pricing (spec §2.4). */
export async function updatePricing(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const pricing = asInvalid(() => validatePricing(data));
  await pricingRef(db).set({
    ...pricing,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: caller!.uid,
  });
}

export const adminUpdatePricing = onCall((req) =>
  updatePricing(req.auth as Caller | undefined, req.data));
