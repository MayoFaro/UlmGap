// Notifications des mouvements de crédit (spec §6.1, plan 5) : crédit,
// correction et régularisation, à l'intéressé et à tous les instructeurs
// actifs, l'auteur excepté. Appelé après la transaction ; ne lève jamais.
import { logger } from "firebase-functions";
import { movementPush } from "../rules/notifications";
import { shortNames } from "./flight-info";
import { sendPush } from "./push";

type Db = FirebaseFirestore.Firestore;

export interface WrittenMovement {
  uid: string; amount: number; balanceAfter: number;
  type: "credit" | "correction" | "flight_adjustment" | "instruction";
}

export async function notifyMovements(db: Db, actor: string, moves: WrittenMovement[]): Promise<void> {
  if (moves.length === 0) return;
  try {
    const snap = await db.collection("users").where("profile", "==", "instructeur").get();
    const instructors = snap.docs.filter((d) => d.get("active") === true).map((d) => d.id);
    const names = await shortNames(db, moves.map((m) => m.uid));
    for (const m of moves) {
      await sendPush(db, movementPush({
        userUid: m.uid, shortName: names[m.uid] ?? "?", amount: m.amount,
        balanceAfter: m.balanceAfter, type: m.type, actor, instructors,
      }));
    }
  } catch (e) {
    logger.error("Notification de mouvement non envoyée", { error: String(e) });
  }
}
