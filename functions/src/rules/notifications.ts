// Notifications push (spec §6, plan 5) : destinataires et textes, en
// français, dates à l'heure du club. Module pur, sans Firestore ni FCM.
import { CLUB_UTC_OFFSET_MS } from "./club-day";
import { formatFcfa } from "./pricing";

export interface FlightInfo {
  start: number; end: number; aircraft: string; destination: string;
  crew: string[]; passengers: string[]; createdBy: string; instructorUid: string | null;
}
export interface PushMessage { title: string; body: string }
export interface Push { to: string[]; message: PushMessage }

const DAYS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];
const MONTHS = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];
const two = (n: number) => String(n).padStart(2, "0");

/** Date « à l'heure du club » : champs UTC d'un instant décalé de UTC+1. */
const club = (ms: number) => new Date(ms + CLUB_UTC_OFFSET_MS);
const time = (d: Date) => `${two(d.getUTCHours())}:${two(d.getUTCMinutes())}`;

/** « lundi 12 octobre, 09:00–10:00 » à l'heure du club. */
export function clubWhen(start: number, end: number): string {
  const s = club(start);
  return `${DAYS[s.getUTCDay()]} ${s.getUTCDate()} ${MONTHS[s.getUTCMonth()]}, ` +
    `${time(s)}–${time(club(end))}`;
}

/** « DPS/LDX, lundi 12 octobre, 09:00–10:00, F-JABC → Lomé » */
export function flightLine(f: FlightInfo, names: Record<string, string>): string {
  const people = [...f.crew.map((u) => names[u] ?? "?"), ...f.passengers].join("/");
  return `${people}, ${clubWhen(f.start, f.end)}, ${f.aircraft} → ${f.destination}`;
}

/** Destinataires dédoublonnés, jamais l'auteur de l'action. */
function push(to: (string | null)[], actor: string | null, title: string, body: string): Push {
  const unique = [...new Set(to.filter((u): u is string => !!u && u !== actor))];
  return { to: unique, message: { title, body } };
}

export function requestPush(
  f: FlightInfo, names: Record<string, string>, actor: string, modified: boolean,
): Push | null {
  if (!f.instructorUid) return null;
  return push([f.instructorUid], actor,
    modified ? "Demande de vol modifiée" : "Nouvelle demande de vol", flightLine(f, names));
}

export function validatedPush(
  f: FlightInfo, names: Record<string, string>, actor: string, modified: boolean,
): Push {
  return push([f.createdBy, ...f.crew], actor,
    modified ? "Vol validé avec modifications" : "Vol validé", flightLine(f, names));
}

export function refusedPush(
  f: FlightInfo, names: Record<string, string>, actor: string, reason: string | null,
): Push {
  const line = flightLine(f, names);
  return push([f.createdBy], actor, "Demande refusée", reason ? `${line}. Motif : ${reason}` : line);
}

export function cancelledPush(f: FlightInfo, names: Record<string, string>, actor: string): Push {
  return push([...f.crew, f.instructorUid], actor, "Vol annulé", flightLine(f, names));
}

export function reminderPush(f: FlightInfo, names: Record<string, string>): Push {
  return push(f.crew, null, "Vol à clôturer",
    `${flightLine(f, names)}. Pensez à le clôturer dans le carnet de vol.`);
}

const MOVEMENT_LABELS = { credit: "Crédit", correction: "Correction", flight_adjustment: "Régularisation",
  instruction: "Crédit instruction" };

export function movementPush(a: {
  userUid: string; shortName: string; amount: number; balanceAfter: number;
  type: "credit" | "correction" | "flight_adjustment" | "instruction"; actor: string; instructors: string[];
}): Push {
  const signed = a.amount > 0 ? `+${formatFcfa(a.amount)}` : formatFcfa(a.amount);
  return push([a.userUid, ...a.instructors], a.actor, `Compte de ${a.shortName}`,
    `${MOVEMENT_LABELS[a.type]} : ${signed}. Nouveau solde : ${formatFcfa(a.balanceAfter)}.`);
}

const H = 3_600_000;

/** Plan 5, décision 2 : premier rappel 24 h après la fin, puis toutes les 48 h. */
export function reminderDue(end: number, lastReminderAt: number | null, now: number): boolean {
  if (now < end + 24 * H) return false;
  return lastReminderAt === null || now >= lastReminderAt + 48 * H;
}
