// Caisse (spec §11.2) : règle absolue, comme ledger.ts pour les comptes.
// Toute écriture de `cashbox/main.balance` s'accompagne d'une ligne
// `cashMovements` dans la même transaction. L'appelant a lu la caisse
// (readCashbox) avant toute écriture : la lecture de `cashbox/main`
// sérialise les opérations de caisse.
import * as admin from "firebase-admin";
import type { CashKind } from "../rules/cash";

type Db = FirebaseFirestore.Firestore;
type Tx = FirebaseFirestore.Transaction;
const { FieldValue } = admin.firestore;

export const cashboxRef = (db: Db) => db.collection("cashbox").doc("main");

/** Document absent : caisse vide, reprise en cours. */
export async function readCashbox(tx: Tx, db: Db): Promise<{ balance: number; migrationClosed: boolean }> {
  const s = await tx.get(cashboxRef(db));
  return {
    balance: (s.get("balance") as number | undefined) ?? 0,
    migrationClosed: s.get("migrationClosedAt") != null,
  };
}

export function postCashMovement(tx: Tx, db: Db, a: {
  kind: CashKind;
  amount: number;
  date: string;
  userUid: string | null;
  transactionId: string | null;
  note: string | null;
  correctsId: string | null;
  by: string;
  currentBalance: number;
}): { id: string; balanceAfter: number } {
  const balanceAfter = a.currentBalance + a.amount;
  tx.set(cashboxRef(db), { balance: balanceAfter, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  const ref = db.collection("cashMovements").doc();
  tx.create(ref, {
    kind: a.kind,
    amount: a.amount,
    date: a.date,
    userUid: a.userUid,
    transactionId: a.transactionId,
    note: a.note,
    correctsId: a.correctsId,
    imported: false,
    by: a.by,
    at: FieldValue.serverTimestamp(),
    balanceAfter,
  });
  return { id: ref.id, balanceAfter };
}
