// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Correction et suppression admin (adminUpdateFlight, adminDeleteFlight),
// avec régularisation automatique des soldes sur un vol clôturé (spec §4.5).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";
import { at, code, db, details, H, seedAircraft, seedFlight, seedUser } from "./testkit";
import { adminDeleteFlight, adminUpdateFlight } from "./admin-edit";
import { closeFlight } from "./close";

const getFlight = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;
const balance = async (uid: string) => (await db.collection("users").doc(uid).get()).get("balance") as number;
const flightTx = async (flightId: string) => {
  const snap = await db.collection("transactions").where("flightId", "==", flightId).get();
  return snap.docs.map((d) => d.data());
};

/**
 * Invariant (Review Focus #3) : la somme des transactions `flight` et
 * `flight_adjustment` d'un vol vaut −billedAmount s'il est facturé sur un
 * compte, 0 s'il est hors app ou supprimé.
 */
async function assertInvariant(id: string): Promise<void> {
  const f = await getFlight(id);
  const sum = (await flightTx(id))
    .filter((t) => t.type === "flight" || t.type === "flight_adjustment")
    .reduce((s, t) => s + (t.amount as number), 0);
  const expected = f.deleted !== true && f.billedTo === "account" ? -(f.billedAmount as number) : 0;
  assert.equal(sum, expected);
}

/** Vol passé, valide, clôturé par un admin (débit « flight » réel). */
async function closedFlight(
  adminCaller: { uid: string; token: { email_verified?: boolean } },
  fields: Record<string, unknown>,
  closing: Record<string, unknown>,
): Promise<{ id: string; start: number; end: number }> {
  const start = Date.now() - 3 * H;
  const end = start + 90 * 60_000;
  const id = await seedFlight({
    start, end, status: "valide", pricingMode: "standard", createdBy: adminCaller.uid, ...fields,
  });
  await closeFlight(adminCaller, { landings: 1, flightId: id, ...closing });
  return { id, start, end };
}

/** Données d'une correction : l'état courant du vol, modifié par `o`. */
async function correction(id: string, o: Record<string, unknown> = {}) {
  const f = await getFlight(id);
  return {
    flightId: id,
    start: (f.start as admin.firestore.Timestamp).toMillis(),
    end: (f.end as admin.firestore.Timestamp).toMillis(),
    destination: f.destination, aircraftId: f.aircraftId, crew: f.crew, passengers: f.passengers,
    ...o,
  };
}

test("vol clôturé GAP 90 min corrigé à 120 min : régularisation de −6 000, billedAmount 21 000", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });
  assert.equal((await getFlight(id)).billedAmount, 15_000);

  await adminUpdateFlight(boss, await correction(id, { actualMinutes: 120 }));

  const f = await getFlight(id);
  assert.equal(f.billedAmount, 21_000);
  assert.equal(f.billedTo, "account");
  assert.equal(f.actualFlightMinutes, 120);
  assert.equal(f.isClosed, true);
  assert.ok(f.updatedAt);
  const adj = (await flightTx(id)).filter((t) => t.type === "flight_adjustment");
  assert.equal(adj.length, 1);
  assert.equal(adj[0].amount, -6_000);
  assert.equal(adj[0].userUid, pilot.uid);
  assert.equal(adj[0].reason, "Régularisation");
  assert.equal(adj[0].by, boss.uid);
  assert.equal(adj[0].balanceAfter, 1_000_000 - 21_000);
  assert.equal(await balance(pilot.uid), 1_000_000 - 21_000);
  await assertInvariant(id);
});

test("vol clôturé : changement de compte débité → +15 000 à l'ancien, −débit au nouveau", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const gap = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const gr = await seedUser({ profile: "lache_toute_mission", category: "GR", active: false });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [gap.uid, gr.uid], aircraftId: a }, { actualMinutes: 90 });

  // Membre inactif accepté (comptes actifs non contrôlés).
  await adminUpdateFlight(boss, await correction(id, { crew: [gr.uid, gap.uid] }));

  // GR, 90 min : 30 000 + 30 000 × 15 / 60 = 37 500.
  const f = await getFlight(id);
  assert.equal(f.payerUid, gr.uid);
  assert.equal(f.billedAmount, 37_500);
  assert.equal(await balance(gap.uid), 1_000_000);
  assert.equal(await balance(gr.uid), 1_000_000 - 37_500);
  const adj = (await flightTx(id)).filter((t) => t.type === "flight_adjustment");
  assert.deepEqual(
    adj.map((t) => [t.userUid, t.amount]).sort(),
    [[gap.uid, 15_000], [gr.uid, -37_500]].sort(),
  );
  await assertInvariant(id);
});

test("vol clôturé avec passager passé en montant différent : remboursement complet, off_app", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss,
    { crew: [pilot.uid], passengers: ["Paul"], pricingMode: "fuel_only", aircraftId: a },
    { actualMinutes: 90 });
  const billed = (await getFlight(id)).billedAmount as number;
  assert.equal(billed, 18_000);

  await adminUpdateFlight(boss, await correction(id, { pricingMode: "custom", customAmount: 25_000 }));

  const f = await getFlight(id);
  assert.equal(f.billedTo, "off_app");
  assert.equal(f.pricingMode, "custom");
  assert.equal(f.billedAmount, 25_000);
  assert.equal(f.customAmount, 25_000);
  assert.equal(await balance(pilot.uid), 1_000_000);
  await assertInvariant(id);

  // Retour au mode carburant : nouveau débit.
  await adminUpdateFlight(boss, await correction(id, { pricingMode: "fuel_only" }));
  const g = await getFlight(id);
  assert.equal(g.billedTo, "account");
  assert.equal(g.billedAmount, 18_000);
  assert.equal(g.customAmount, null);
  assert.equal(await balance(pilot.uid), 1_000_000 - 18_000);
  await assertInvariant(id);
});

test("vol clôturé : correction sans effet sur le montant → aucun mouvement", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });

  await adminUpdateFlight(boss, await correction(id, { destination: "Kara" }));

  assert.equal((await getFlight(id)).destination, "Kara");
  assert.equal((await flightTx(id)).length, 1);
  await assertInvariant(id);
});

test("non-admin : permission-denied (correction et suppression)", async () => {
  const pilot = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const id = await seedFlight({ start: at(10), end: at(11), crew: [pilot.uid], aircraftId: a, createdBy: pilot.uid });
  await assert.rejects(adminUpdateFlight(pilot, await correction(id)), (e) => code(e) === "permission-denied");
  await assert.rejects(adminDeleteFlight(pilot, { flightId: id }), (e) => code(e) === "permission-denied");
});

test("vol non clôturé : créneau en conflit refusé ; champs de clôture refusés ; demande conservée", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const p1 = await seedUser({ profile: "lache_toute_mission" });
  const p2 = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  await seedFlight({ start: at(10), end: at(11), crew: [p1.uid], aircraftId: a });
  const id = await seedFlight({ start: at(12), end: at(13), crew: [p2.uid], aircraftId: a, createdBy: p2.uid });

  await assert.rejects(
    adminUpdateFlight(boss, await correction(id, { start: at(10.5), end: at(11.5) })),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "Conflit avec un autre vol validé.",
  );
  await assert.rejects(
    adminUpdateFlight(boss, await correction(id, { actualMinutes: 60 })),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "Réservé aux vols clôturés.",
  );

  const req = await seedFlight({
    start: at(10), end: at(11), crew: [p2.uid], aircraftId: await seedAircraft(), status: "demande",
    createdBy: p2.uid,
  });
  await adminUpdateFlight(boss, await correction(req, { start: at(10.5), end: at(11.5), pricingMode: "fuel_only" }));
  const f = await getFlight(req);
  assert.equal(f.status, "demande");
  assert.equal(f.pricingMode, "fuel_only");
  assert.equal((f.start as admin.firestore.Timestamp).toMillis(), at(10.5));
});

test("vol non clôturé : le crédit reste contrôlé", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const poor = await seedUser({ profile: "lache_toute_mission", category: "GAP", balance: 0 });
  const a = await seedAircraft();
  const id = await seedFlight({ start: at(10), end: at(11), crew: [poor.uid], aircraftId: a, createdBy: poor.uid });
  await assert.rejects(
    adminUpdateFlight(boss, await correction(id, { destination: "Kara" })),
    (e) => code(e) === "failed-precondition" && /Crédit insuffisant/.test((e as Error).message),
  );
});

test("suppression d'un vol clôturé : remboursement et deleted: true ; seconde suppression refusée", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });

  await adminDeleteFlight(boss, { flightId: id });

  const f = await getFlight(id);
  assert.equal(f.deleted, true);
  assert.ok(f.updatedAt);
  assert.equal(await balance(pilot.uid), 1_000_000);
  const adj = (await flightTx(id)).filter((t) => t.type === "flight_adjustment");
  assert.equal(adj.length, 1);
  assert.equal(adj[0].amount, 15_000);
  assert.equal(adj[0].reason, "Annulation du vol");
  assert.equal(adj[0].by, boss.uid);
  await assertInvariant(id);

  await assert.rejects(adminDeleteFlight(boss, { flightId: id }), (e) => code(e) === "not-found");
  assert.equal(await balance(pilot.uid), 1_000_000);
});

test("suppression d'un vol hors app clôturé : aucun mouvement", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss,
    { crew: [pilot.uid], passengers: ["Paul"], aircraftId: a }, { actualMinutes: 90, customAmount: 20_000 });
  await adminDeleteFlight(boss, { flightId: id });
  assert.equal((await flightTx(id)).length, 0);
  await assertInvariant(id);
});

test("suppression d'un vol déjà commencé mais non clôturé : autorisée, sans mouvement", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedFlight({ start: Date.now() - H, end: Date.now() + H, crew: [pilot.uid], aircraftId: a });

  await adminDeleteFlight(boss, { flightId: id });

  assert.equal((await getFlight(id)).deleted, true);
  assert.equal((await flightTx(id)).length, 0);
  assert.equal(await balance(pilot.uid), 1_000_000);
});

test("vol clôturé GAP + passager (carburant) : pilote remplacé par un EXT sans mode → standard, régularisé", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const gap = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const ext = await seedUser({ profile: "lache_toute_mission", category: "EXT" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss,
    { crew: [gap.uid], passengers: ["Paul"], pricingMode: "fuel_only", aircraftId: a },
    { actualMinutes: 90 });
  assert.equal((await getFlight(id)).billedAmount, 18_000);

  // Condition « tous GAP » perdue → standard (spec §4.1), même sans pricingMode.
  await adminUpdateFlight(boss, await correction(id, { crew: [ext.uid] }));

  // EXT, 90 min : 70 000 + 30 000 × 15 / 60 = 77 500.
  const f = await getFlight(id);
  assert.equal(f.pricingMode, "standard");
  assert.equal(f.billedAmount, 77_500);
  assert.equal(f.payerUid, ext.uid);
  assert.equal(await balance(gap.uid), 1_000_000);
  assert.equal(await balance(ext.uid), 1_000_000 - 77_500);
  await assertInvariant(id);
});

test("vol non clôturé GAP + passager (carburant) : pilote remplacé par un EXT sans mode → standard", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const gap = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const ext = await seedUser({ profile: "lache_toute_mission", category: "EXT" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(30), end: at(31), crew: [gap.uid], passengers: ["Paul"], pricingMode: "fuel_only",
    aircraftId: a, createdBy: gap.uid,
  });

  await adminUpdateFlight(boss, await correction(id, { crew: [ext.uid] }));

  const f = await getFlight(id);
  assert.equal(f.pricingMode, "standard");
  assert.equal(f.payerUid, ext.uid);
});

test("vol clôturé court (montant à facturer) corrigé à 90 min : shortFlightAmount effacé", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a },
    { actualMinutes: 30, shortFlightAmount: 10_000 });
  assert.equal((await getFlight(id)).shortFlightAmount, 10_000);

  await adminUpdateFlight(boss, await correction(id, { actualMinutes: 90 }));

  const f = await getFlight(id);
  assert.equal(f.billedAmount, 15_000);
  assert.equal(f.shortFlightAmount, null);
  await assertInvariant(id);

  // Retour à 30 min : le montant à facturer redevient obligatoire, puis conservé.
  await adminUpdateFlight(boss, await correction(id, { actualMinutes: 30, shortFlightAmount: 9_000 }));
  const g = await getFlight(id);
  assert.equal(g.billedAmount, 9_000);
  assert.equal(g.shortFlightAmount, 9_000);
  await assertInvariant(id);
});

test("vol refusé : correction admin refusée", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(40), end: at(41), crew: [pilot.uid], aircraftId: a, status: "refuse", createdBy: pilot.uid,
  });
  await assert.rejects(
    adminUpdateFlight(boss, await correction(id, { destination: "Kara" })),
    (e) => code(e) === "failed-precondition" &&
      (e as Error).message === "Un vol refusé ne peut pas être corrigé.",
  );
});

// --- Plan 4b : atterrissages, amerrissages, heure de fin ---

test("correction d'un vol clôturé : atterrissages modifiés, amerrissages conservés", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft(true, true);
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a },
    { actualMinutes: 90, landings: 1, waterLandings: 2 });
  await adminUpdateFlight(boss, await correction(id, { landings: 3 }));
  const f = await getFlight(id);
  assert.equal(f.landings, 3);
  assert.equal(f.waterLandings, 2);
});

test("nombres envoyés sur un vol non clôturé : refusé", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(10), end: at(11), crew: [pilot.uid], aircraftId: a, createdBy: boss.uid,
  });
  await assert.rejects(adminUpdateFlight(boss, await correction(id, { landings: 2 })),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "Réservé aux vols clôturés.");
});

test("durée réelle corrigée au-delà de fin − début : fin allongée", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id, start } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });
  await adminUpdateFlight(boss, await correction(id, { actualMinutes: 120 }));
  assert.equal((await getFlight(id)).end.toMillis(), start + 120 * 60_000);
});

test("amerrissages sur un appareil non amphibie : refusé, y compris après changement d'appareil",
  async () => {
    const boss = await seedUser({ profile: null, isAdmin: true });
    const pilot = await seedUser({ profile: "lache_toute_mission" });
    const amphib = await seedAircraft(true, true);
    const plain = await seedAircraft();
    const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: amphib },
      { actualMinutes: 90, landings: 1, waterLandings: 1 });
    await assert.rejects(adminUpdateFlight(boss, await correction(id, { aircraftId: plain })),
      (e) => code(e) === "failed-precondition" && (e as Error).message === "Cet appareil n'est pas amphibie.");
    await assert.rejects(adminUpdateFlight(boss, await correction(id, { aircraftId: plain, waterLandings: 2 })),
      (e) => code(e) === "failed-precondition" && (e as Error).message === "Cet appareil n'est pas amphibie.");
    // Retirer les amerrissages en changeant d'appareil : accepté.
    await adminUpdateFlight(boss, await correction(id, { aircraftId: plain, waterLandings: 0 }));
    assert.equal((await getFlight(id)).aircraftId, plain);
  });

test("total nul après correction : refusé", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });
  await assert.rejects(adminUpdateFlight(boss, await correction(id, { landings: 0 })),
    (e) => code(e) === "invalid-argument" && (e as Error).message === "Au moins un atterrissage ou amerrissage.");
});

test("conduite : fin allongée qui chevauche un autre vol du même appareil, acceptée", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const other = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id, start, end } = await closedFlight(boss, { crew: [pilot.uid], aircraftId: a }, { actualMinutes: 90 });
  const next = await seedFlight({ start: end + 10 * 60_000, end: end + 70 * 60_000, crew: [other.uid], aircraftId: a });
  await adminUpdateFlight(boss, await correction(id, { actualMinutes: 120 }));
  assert.equal((await getFlight(id)).end.toMillis(), start + 120 * 60_000);
  // Et le vol suivant (passé, non clôturé) se corrige sans conflit avec le vol clôturé.
  await adminUpdateFlight(boss, await correction(next, { destination: "Kpalimé" }));
  assert.equal((await getFlight(next)).destination, "Kpalimé");
});

test("conduite : correction d'un vol passé non clôturé qui chevauche un autre vol passé, acceptée",
  async () => {
    const boss = await seedUser({ profile: null, isAdmin: true });
    const p1 = await seedUser({ profile: "lache_toute_mission" });
    const p2 = await seedUser({ profile: "lache_toute_mission" });
    const a = await seedAircraft();
    const start = Date.now() - 5 * H;
    const id = await seedFlight({ start, end: start + H, crew: [p1.uid], aircraftId: a, createdBy: boss.uid });
    await seedFlight({ start: start + 2 * H, end: start + 3 * H, crew: [p2.uid], aircraftId: a });
    await adminUpdateFlight(boss, await correction(id, { end: start + 150 * 60_000 }));
    assert.equal((await getFlight(id)).end.toMillis(), start + 150 * 60_000);
  });
