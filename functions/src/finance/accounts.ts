// Crédit et correction de compte par un instructeur ou un admin (task 5).
// Règle absolue (context.md) : toute écriture de `users.balance` s'accompagne
// d'une ligne `transactions` dans la même transaction Firestore
// (postMovement). Le verrou `flightLocks/user_<compte>` est lu puis écrit,
// comme pour `closeFlight` et le contrôle de crédit (core.ts) : deux
// opérations sur le même compte se sérialisent.
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireStaff } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { postMovement } from "./ledger";
import { validateCorrection, validateCredit } from "./validation";

export interface AccountResult { balance: number }

type Movement = { userUid: string; amount: number; reason: string | null };

async function applyMovement(
  caller: Caller | undefined,
  data: unknown,
  parse: (data: unknown) => Movement,
  type: "credit" | "correction",
): Promise<AccountResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const { userUid, amount, reason } = asInvalid(() => parse(data));
  const ref = db.collection("users").doc(userUid);
  const lockRef = db.collection("flightLocks").doc(`user_${userUid}`);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compte introuvable.");
    await tx.get(lockRef);
    const balance = postMovement(tx, db, {
      uid: userUid,
      amount,
      type,
      reason,
      flightId: null,
      by: me.uid,
      currentBalance: (snap.get("balance") as number | undefined) ?? 0,
    });
    tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
    return { balance };
  });
}

export async function creditAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  return applyMovement(caller, data, validateCredit, "credit");
}

export async function correctAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  return applyMovement(caller, data, validateCorrection, "correction");
}

export const creditAccountFn = onCall((req) => creditAccount(req.auth as Caller | undefined, req.data));
export const correctAccountFn = onCall((req) => correctAccount(req.auth as Caller | undefined, req.data));
