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
import { formatFcfa } from "../rules/pricing";
import { postMovement } from "./ledger";
import { notifyMovements } from "../notify/movements";
import { validateCorrection, validateCredit } from "./validation";

export interface AccountResult { balance: number }

type Movement = { userUid: string; reason: string | null; amountFor: (balance: number) => number };

async function applyMovement(
  caller: Caller | undefined,
  data: unknown,
  parse: (data: unknown) => Movement,
  type: "credit" | "correction",
): Promise<AccountResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const { userUid, reason, amountFor } = asInvalid(() => parse(data));
  const ref = db.collection("users").doc(userUid);
  const lockRef = db.collection("flightLocks").doc(`user_${userUid}`);

  const written = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compte introuvable.");
    await tx.get(lockRef);
    const currentBalance = (snap.get("balance") as number | undefined) ?? 0;
    const amount = amountFor(currentBalance);
    const balance = postMovement(tx, db, {
      uid: userUid,
      amount,
      type,
      reason,
      flightId: null,
      by: me.uid,
      currentBalance,
    });
    tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
    return { uid: userUid, amount, balanceAfter: balance, type };
  });
  await notifyMovements(db, me.uid, [written]);
  return { balance: written.balanceAfter };
}

export async function creditAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  return applyMovement(caller, data, (d) => {
    const v = validateCredit(d);
    return { userUid: v.userUid, reason: v.reason, amountFor: () => v.amount };
  }, "credit");
}

/** Correction : nouveau solde saisi, écart calculé sur le solde lu dans la transaction. */
export async function correctAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  return applyMovement(caller, data, (d) => {
    const v = validateCorrection(d);
    return {
      userUid: v.userUid,
      reason: v.reason,
      amountFor: (balance) => {
        if (v.newBalance === balance) {
          throw new HttpsError("failed-precondition", `Le solde est déjà de ${formatFcfa(balance)}.`);
        }
        return v.newBalance - balance;
      },
    };
  }, "correction");
}

export const creditAccountFn = onCall((req) => creditAccount(req.auth as Caller | undefined, req.data));
export const correctAccountFn = onCall((req) => correctAccount(req.auth as Caller | undefined, req.data));
