// Solde et historique (règle absolue, context.md) : toute écriture de
// `users.balance` s'accompagne d'une ligne `transactions` dans la même
// transaction Firestore. L'appelant a déjà lu `users/{uid}` (et tout autre
// document nécessaire au contrôle) avant d'appeler postMovement : aucune
// lecture ici, seulement des écritures.
import * as admin from "firebase-admin";

type Db = FirebaseFirestore.Firestore;
type Tx = FirebaseFirestore.Transaction;

export type MovementType = "credit" | "correction" | "flight" | "flight_adjustment" | "instruction";

/**
 * Écrit `users/{uid}.balance = currentBalance + amount` et une ligne
 * `transactions/{auto}` correspondante (champs de la règle absolue), puis
 * renvoie le nouveau solde. `amount` est positif pour un crédit, négatif
 * pour un débit (vol, régularisation à charge).
 */
export function postMovement(tx: Tx, db: Db, a: {
  uid: string;
  amount: number;
  type: MovementType;
  reason: string | null;
  flightId: string | null;
  by: string;
  currentBalance: number;
}): number {
  const balanceAfter = a.currentBalance + a.amount;
  tx.update(db.collection("users").doc(a.uid), {
    balance: balanceAfter,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  tx.create(db.collection("transactions").doc(), {
    userUid: a.uid,
    amount: a.amount,
    type: a.type,
    reason: a.reason,
    flightId: a.flightId,
    by: a.by,
    at: admin.firestore.FieldValue.serverTimestamp(),
    balanceAfter,
  });
  return balanceAfter;
}
