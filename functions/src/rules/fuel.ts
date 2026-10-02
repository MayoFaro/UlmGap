// Suivi carburant (spec §9.2) : un vol clôturé devient la source du
// carburant actuel de l'appareil s'il part au même moment ou après le vol
// source actuel, ou si l'appareil n'a pas encore de valeur. Module pur.
export function becomesFuelSource(flightStartMs: number, sourceStartMs: number | null): boolean {
  return sourceStartMs === null || flightStartMs >= sourceStartMs;
}
