// Lecture, après la transaction d'une action, du vol et des trigrammes de
// l'annuaire (`profiles`) utiles au texte des notifications (plan 5).
import { logger } from "firebase-functions";
import { FlightInfo, Push } from "../rules/notifications";
import { sendPush } from "./push";

type Db = FirebaseFirestore.Firestore;
const ms = (v: unknown) => (v as FirebaseFirestore.Timestamp).toMillis();

export function flightInfoOf(d: FirebaseFirestore.DocumentSnapshot): FlightInfo {
  return {
    start: ms(d.get("start")),
    end: ms(d.get("end")),
    aircraft: (d.get("aircraft") as string | undefined) ?? "",
    destination: (d.get("destination") as string | undefined) ?? "",
    crew: (d.get("crew") as string[] | undefined) ?? [],
    passengers: (d.get("passengers") as string[] | undefined) ?? [],
    createdBy: (d.get("createdBy") as string | undefined) ?? "",
    instructorUid: (d.get("instructorUid") as string | null | undefined) ?? null,
  };
}

/** Trigrammes des comptes de [uids] (absents : ignorés). */
export async function shortNames(db: Db, uids: string[]): Promise<Record<string, string>> {
  const unique = [...new Set(uids.filter(Boolean))];
  if (unique.length === 0) return {};
  const snaps = await db.getAll(...unique.map((u) => db.collection("profiles").doc(u)));
  const names: Record<string, string> = {};
  for (const s of snaps) if (s.exists) names[s.id] = s.get("shortName") as string;
  return names;
}

/** Vol et trigrammes de son équipage ; null si le vol est introuvable. */
export async function loadFlightInfo(
  db: Db, flightId: string,
): Promise<{ info: FlightInfo; names: Record<string, string> } | null> {
  const d = await db.collection("flights").doc(flightId).get();
  if (!d.exists) return null;
  const info = flightInfoOf(d);
  return { info, names: await shortNames(db, info.crew) };
}

/** Notification d'une action sur un vol, après sa transaction. Ne lève jamais. */
export async function notifyFlight(
  db: Db, flightId: string,
  build: (info: FlightInfo, names: Record<string, string>) => Push | null,
): Promise<void> {
  try {
    const f = await loadFlightInfo(db, flightId);
    if (f) await sendPush(db, build(f.info, f.names));
  } catch (e) {
    logger.error("Notification non envoyée", { flightId, error: String(e) });
  }
}
