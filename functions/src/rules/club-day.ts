// Jour calendaire à l'heure du club (Africa/Libreville, UTC+1 sans heure
// d'été, comme AppGAP). Module pur, sans Firestore.
export const CLUB_UTC_OFFSET_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** Numéro du jour (depuis l'époque) à l'heure du club. */
export function clubDay(ms: number): number {
  return Math.floor((ms + CLUB_UTC_OFFSET_MS) / DAY_MS);
}

/** Décision 6 (plan 4) : un vol se clôture dès son jour, sans condition d'heure. */
export function isOnOrBeforeClubToday(startMs: number, nowMs: number): boolean {
  return clubDay(startMs) <= clubDay(nowMs);
}
