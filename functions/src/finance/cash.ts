// Caisse (spec §11.3, §11.4) : opérations, corrections d'une opération
// (jamais d'un solde), clôture de la reprise.
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin, requireStaff } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { CashKind, formatCashDay, signedCashAmount } from "../rules/cash";
import { formatFcfa } from "../rules/pricing";
import { notifyMovements, WrittenMovement } from "../notify/movements";
import { cashboxRef, postCashMovement, readCashbox } from "./cash-ledger";
import { validateAddCashMovement, validateCashCorrection } from "./cash-validation";
import { postMovement } from "./ledger";

export interface CashResult { id: string; balance: number }

const ADMIN_ONLY: readonly CashKind[] = ["cash_gap", "opening"];

export async function addCashMovement(caller: Caller | undefined, data: unknown): Promise<CashResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const m = asInvalid(() => validateAddCashMovement(data, Date.now()));
  if (m.kind === "cash_gap" && !me.isAdmin) {
    throw new HttpsError("permission-denied", "Écart de caisse : réservé aux administrateurs.");
  }
  return db.runTransaction(async (tx) => {
    const cash = await readCashbox(tx, db);
    const r = postCashMovement(tx, db, {
      ...m, userUid: null, transactionId: null, correctsId: null, by: me.uid, currentBalance: cash.balance,
    });
    return { id: r.id, balance: r.balanceAfter };
  });
}

export async function correctCashMovement(caller: Caller | undefined, data: unknown): Promise<CashResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const c = asInvalid(() => validateCashCorrection(data));
  const origRef = db.collection("cashMovements").doc(c.movementId);

  const { result, written } = await db.runTransaction(async (tx) => {
    // Lectures d'abord : ligne d'origine, ses corrections, caisse, compte.
    const orig = await tx.get(origRef);
    if (!orig.exists) throw new HttpsError("not-found", "Opération introuvable.");
    if (orig.get("correctsId")) {
      throw new HttpsError("failed-precondition", "Corrigez l'opération d'origine, pas une correction.");
    }
    const kind = orig.get("kind") as CashKind;
    if (ADMIN_ONLY.includes(kind) && !me.isAdmin) {
      throw new HttpsError("permission-denied", "Réservé aux administrateurs.");
    }
    const target = asInvalid(() => signedCashAmount(kind, c.amount, true));
    const corrections = await tx.get(db.collection("cashMovements").where("correctsId", "==", origRef.id));
    const current = (orig.get("amount") as number) +
      corrections.docs.reduce((s, d) => s + (d.get("amount") as number), 0);
    const delta = target - current;
    if (delta === 0) {
      throw new HttpsError("failed-precondition", `Le montant est déjà de ${formatFcfa(kind === "cash_gap" ? current : Math.abs(current))}.`);
    }
    const cash = await readCashbox(tx, db);
    const date = orig.get("date") as string;
    const userUid = kind === "fuel_credit" ? (orig.get("userUid") as string | null) ?? null : null;
    let user: FirebaseFirestore.DocumentSnapshot | null = null;
    const lockRef = userUid ? db.collection("flightLocks").doc(`user_${userUid}`) : null;
    if (userUid && lockRef) {
      user = await tx.get(db.collection("users").doc(userUid));
      if (!user.exists) throw new HttpsError("not-found", "Compte de l'adhérent introuvable.");
      await tx.get(lockRef);
    }

    // Écritures : compte de l'adhérent (Crédit carburant), puis caisse.
    let transactionId: string | null = null;
    let written: WrittenMovement | null = null;
    if (userUid && user && lockRef) {
      transactionId = db.collection("transactions").doc().id;
      const balanceAfter = postMovement(tx, db, {
        id: transactionId,
        uid: userUid,
        amount: delta,
        type: "credit",
        reason: `Correction crédit carburant du ${formatCashDay(date)}`,
        flightId: null,
        by: me.uid,
        currentBalance: (user.get("balance") as number | undefined) ?? 0,
      });
      tx.set(lockRef, { at: admin.firestore.FieldValue.serverTimestamp() });
      written = { uid: userUid, amount: delta, balanceAfter, type: "credit" };
    }
    const r = postCashMovement(tx, db, {
      kind, amount: delta, date, userUid, transactionId,
      note: c.note ? `Correction : ${c.note}` : "Correction",
      correctsId: origRef.id, by: me.uid, currentBalance: cash.balance,
    });
    return { result: { id: r.id, balance: r.balanceAfter }, written };
  });
  if (written) await notifyMovements(db, me.uid, [written]);
  return result;
}

/** « Reprise terminée » (spec §11.5) : irréversible. */
export async function closeMigration(caller: Caller | undefined): Promise<void> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(cashboxRef(db));
    if (s.get("migrationClosedAt") != null) {
      throw new HttpsError("failed-precondition", "La reprise est déjà terminée.");
    }
    tx.set(cashboxRef(db), {
      balance: (s.get("balance") as number | undefined) ?? 0,
      migrationClosedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

export const addCashMovementFn = onCall((req) => addCashMovement(req.auth as Caller | undefined, req.data));
export const correctCashMovementFn = onCall((req) => correctCashMovement(req.auth as Caller | undefined, req.data));
export const closeMigrationFn = onCall((req) => closeMigration(req.auth as Caller | undefined));
