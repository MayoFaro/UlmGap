// Rappels de clôture (spec §6.2, plan 5) : une tâche planifiée toutes les
// heures relance l'équipage des vols validés non clôturés, 24 h après la fin
// du vol puis toutes les 48 h (décision 2). Pas de file de tâches : la tâche
// relit toujours l'horaire courant du vol, et `lastReminderAt` évite les
// doublons. La requête n'a que des égalités (pas d'index composite).
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { reminderDue, reminderPush } from "../rules/notifications";
import { flightInfoOf, shortNames } from "./flight-info";
import { sendPush } from "./push";

type Db = FirebaseFirestore.Firestore;
const ms = (v: unknown) => (v as FirebaseFirestore.Timestamp | null | undefined)?.toMillis() ?? null;

export async function sendClosingReminders(db: Db, now: number): Promise<number> {
  const snap = await db.collection("flights")
    .where("status", "==", "valide")
    .where("isClosed", "==", false)
    .get();
  let count = 0;
  for (const d of snap.docs) {
    if (d.get("deleted") === true) continue;
    if (!reminderDue(ms(d.get("end"))!, ms(d.get("lastReminderAt")), now)) continue;
    const info = flightInfoOf(d);
    try {
      await sendPush(db, reminderPush(info, await shortNames(db, info.crew)));
    } catch (e) {
      logger.error("Rappel de clôture non envoyé", { flightId: d.id, error: String(e) });
    }
    // Noté même si l'envoi échoue : pas de relance en boucle toutes les heures.
    await d.ref.update({
      lastReminderAt: admin.firestore.Timestamp.fromMillis(now),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    count++;
  }
  return count;
}

export const closingReminders = onSchedule(
  { schedule: "every 60 minutes", region: "europe-west1", timeZone: "Africa/Libreville" },
  async () => {
    const n = await sendClosingReminders(admin.firestore(), Date.now());
    logger.info("Rappels de clôture", { count: n });
  },
);
