// Cuve du club (spec §13.1) : règle absolue, comme cash-ledger.ts pour la caisse.
// Toute écriture de `tank/main.liters` s'accompagne d'une ligne `tankMovements`
// dans la même transaction. L'appelant a lu la cuve (readTank) avant toute
// écriture : la lecture de `tank/main` sérialise les opérations de cuve.
import * as admin from "firebase-admin";
import type { TankKind } from "../rules/tank";

type Db = FirebaseFirestore.Firestore;
type Tx = FirebaseFirestore.Transaction;
const { FieldValue } = admin.firestore;

export const tankRef = (db: Db) => db.collection("tank").doc("main");

/** Document absent : cuve à 0 L (le niveau peut devenir négatif). */
export async function readTank(tx: Tx, db: Db): Promise<{ liters: number }> {
  const s = await tx.get(tankRef(db));
  return { liters: (s.get("liters") as number | undefined) ?? 0 };
}

export function postTankMovement(tx: Tx, db: Db, a: {
  kind: TankKind;
  liters: number;
  date: string;
  flightId: string | null;
  aircraftId: string | null;
  cashMovementId: string | null;
  measuredLiters: number | null;
  technical: boolean;
  note: string | null;
  by: string;
  currentLiters: number;
}): { id: string; litersAfter: number } {
  const litersAfter = a.currentLiters + a.liters;
  tx.set(tankRef(db), { liters: litersAfter, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  const ref = db.collection("tankMovements").doc();
  tx.create(ref, {
    kind: a.kind,
    liters: a.liters,
    date: a.date,
    flightId: a.flightId,
    aircraftId: a.aircraftId,
    cashMovementId: a.cashMovementId,
    measuredLiters: a.measuredLiters,
    technical: a.technical,
    note: a.note,
    by: a.by,
    at: FieldValue.serverTimestamp(),
    litersAfter,
  });
  return { id: ref.id, litersAfter };
}
