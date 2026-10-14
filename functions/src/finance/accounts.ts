// Crédit carburant (alimente aussi la caisse, plan 11) et correction de compte
// par un instructeur ou un admin (task 5).
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
import { postCashMovement, readCashbox } from "./cash-ledger";
import { postMovement } from "./ledger";
import { notifyMovements } from "../notify/movements";
import { validateCorrection, validateCredit } from "./validation";

export interface AccountResult { balance: number }

/** Crédit carburant (spec §11.3) : caisse + et compte +, dans une seule transaction. */
export async function creditAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const { userUid, amount, reason, date } = asInvalid(() => validateCredit(data));
  const ref = db.collection("users").doc(userUid);
  const lockRef = db.collection("flightLocks").doc(`user_${userUid}`);

  const written = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compte introuvable.");
    await tx.get(lockRef);
    const cash = await readCashbox(tx, db);
    const transactionId = db.collection("transactions").doc().id;
    const balanceAfter = postMovement(tx, db, {
      id: transactionId,
      uid: userUid,
      amount,
      type: "credit",
      reason,
      flightId: null,
      by: me.uid,
      currentBalance: (snap.get("balance") as number | undefined) ?? 0,
    });
    postCashMovement(tx, db, {
      kind: "fuel_credit", amount, date, userUid, transactionId, note: reason,
      correctsId: null, by: me.uid, currentBalance: cash.balance,
    });
    tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
    return { uid: userUid, amount, balanceAfter, type: "credit" as const };
  });
  await notifyMovements(db, me.uid, [written]);
  return { balance: written.balanceAfter };
}

/**
 * Correction : nouveau solde saisi, écart calculé sur le solde lu dans la
 * transaction. Sans effet sur la caisse (reprise de l'existant, spec §11.5) ;
 * refusée une fois la reprise terminée.
 */
export async function correctAccount(caller: Caller | undefined, data: unknown): Promise<AccountResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const { userUid, newBalance, reason } = asInvalid(() => validateCorrection(data));
  const ref = db.collection("users").doc(userUid);
  const lockRef = db.collection("flightLocks").doc(`user_${userUid}`);

  const written = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compte introuvable.");
    await tx.get(lockRef);
    if ((await readCashbox(tx, db)).migrationClosed) {
      throw new HttpsError("failed-precondition",
        "La reprise est terminée : corrigez le crédit carburant concerné.");
    }
    const currentBalance = (snap.get("balance") as number | undefined) ?? 0;
    if (newBalance === currentBalance) {
      throw new HttpsError("failed-precondition", `Le solde est déjà de ${formatFcfa(currentBalance)}.`);
    }
    const amount = newBalance - currentBalance;
    const balanceAfter = postMovement(tx, db, {
      uid: userUid, amount, type: "correction", reason, flightId: null, by: me.uid, currentBalance,
    });
    tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
    return { uid: userUid, amount, balanceAfter, type: "correction" as const };
  });
  await notifyMovements(db, me.uid, [written]);
  return { balance: written.balanceAfter };
}

export const creditAccountFn = onCall((req) => creditAccount(req.auth as Caller | undefined, req.data));
export const correctAccountFn = onCall((req) => correctAccount(req.auth as Caller | undefined, req.data));
