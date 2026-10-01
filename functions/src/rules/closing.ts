// Heure de fin à la clôture (plan 4b, décision 4) : allongée si le temps de
// vol réel dépasse fin − début, jamais raccourcie. Module pur.
export function closingEnd(startMs: number, endMs: number, actualMinutes: number): number {
  return Math.max(endMs, startMs + actualMinutes * 60_000);
}
