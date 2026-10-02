// DEV/RECETTE UNIQUEMENT (task 7, plan 3). Crédite chaque compte d'un
// montant initial, une seule fois, par une transaction `credit` de motif
// fixe. Règle absolue (context.md) : toute écriture de `users.balance`
// s'accompagne d'une ligne `transactions` dans la même transaction
// Firestore (postMovement) ; le verrou `flightLocks/user_<uid>` est lu puis
// écrit, comme pour `creditAccount`/`correctAccount` (finance/accounts.ts).
import * as admin from "firebase-admin";
import { postMovement } from "../finance/ledger";

export const INITIAL_CREDIT_REASON = "Crédit initial (tests)";

/**
 * Pour chaque document `users`, crédite `amount` par `postMovement` (type
 * `credit`, `by` `system`) si aucune transaction de ce compte ne porte déjà
 * le motif `INITIAL_CREDIT_REASON` ; sinon le compte est ignoré. Idempotente :
 * une relance ne crédite jamais deux fois le même compte.
 */
export async function seedInitialCredit(
  db: FirebaseFirestore.Firestore,
  amount: number,
): Promise<{ credited: string[]; skipped: string[] }> {
  const credited: string[] = [];
  const skipped: string[] = [];

  const usersSnap = await db.collection("users").get();
  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const already = await db.collection("transactions")
      .where("userUid", "==", uid)
      .where("reason", "==", INITIAL_CREDIT_REASON)
      .limit(1)
      .get();
    if (!already.empty) {
      skipped.push(uid);
      continue;
    }

    const ref = db.collection("users").doc(uid);
    const lockRef = db.collection("flightLocks").doc(`user_${uid}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      await tx.get(lockRef);
      postMovement(tx, db, {
        uid,
        amount,
        type: "credit",
        reason: INITIAL_CREDIT_REASON,
        flightId: null,
        by: "system",
        currentBalance: (snap.get("balance") as number | undefined) ?? 0,
      });
      tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
    });
    credited.push(uid);
  }

  return { credited, skipped };
}
