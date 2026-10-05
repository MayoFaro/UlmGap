// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Clôture (`closeFlight`) : bilan facturé, débit du compte débité et
// historique. Les tests qui modifient settings/pricing la restaurent dans un
// `finally` (fichiers d'intégration exécutés l'un après l'autre, cf.
// run-tests.js).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { at, code, db, FUEL, H, seedAircraft, seedFlight, seedUser } from "./testkit";
import { closeFlight } from "./close";
import { createFlight } from "./edit";
import { DEFAULT_PRICING } from "../rules/pricing";
import { updatePricing } from "../finance/pricing-store";
import { CLUB_UTC_OFFSET_MS, clubDay } from "../rules/club-day";

const getFlight = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;
const getUser = async (uid: string) => (await db.collection("users").doc(uid).get()).data()!;
const flightTx = async (flightId: string) => {
  const snap = await db.collection("transactions").where("flightId", "==", flightId).get();
  return snap.docs.map((d) => d.data());
};

/** Vol valide déjà passé, prêt à être clôturé. */
async function seedPastFlight(fields: Record<string, unknown>): Promise<string> {
  const crew = (fields.crew as string[] | undefined) ?? [];
  return seedFlight({
    start: Date.now() - 2 * H, end: Date.now() - H, crew, status: "valide", pricingMode: "standard",
    ...fields,
  });
}

test("clôture 90 min GAP par un membre de l'équipage : solde −15 000, transaction et vol à jour", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const mate = await seedUser({ profile: "eleve" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid, mate.uid], payerUid: pilot.uid, aircraftId: a });

  const r = await closeFlight(mate, { ...FUEL, landings: 1, flightId: id, actualMinutes: 90 });
  assert.deepEqual(r, { billedAmount: 15_000, billedTo: "account" });

  assert.equal((await getUser(pilot.uid)).balance, 1_000_000 - 15_000);
  const txs = await flightTx(id);
  assert.equal(txs.length, 1);
  assert.equal(txs[0].type, "flight");
  assert.equal(txs[0].amount, -15_000);
  assert.equal(txs[0].balanceAfter, 1_000_000 - 15_000);
  assert.equal(txs[0].userUid, pilot.uid);
  assert.equal(txs[0].flightId, id);
  assert.equal(txs[0].by, mate.uid);

  const f = await getFlight(id);
  assert.equal(f.isClosed, true);
  assert.equal(f.actualFlightMinutes, 90);
  assert.equal(f.billedAmount, 15_000);
  assert.equal(f.billedTo, "account");
  assert.equal(f.closedBy, mate.uid);
  assert.ok(f.closedAt);
  assert.equal(f.pricingMode, "standard");
});

test("non-membre non admin : permission-denied ; admin hors équipage : accepté", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const outsider = await seedUser({ profile: "eleve" });
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const a = await seedAircraft();
  const id1 = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });
  await assert.rejects(
    closeFlight(outsider, { ...FUEL, landings: 1, flightId: id1, actualMinutes: 90 }),
    (e) => code(e) === "permission-denied",
  );

  const id2 = await seedPastFlight({ crew: [pilot.uid], aircraftId: await seedAircraft() });
  const r = await closeFlight(admin1, { ...FUEL, landings: 1, flightId: id2, actualMinutes: 90 });
  assert.equal(r.billedTo, "account");
});

test("avant le départ : failed-precondition", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(10), end: at(11), crew: [pilot.uid], aircraftId: a,
    status: "valide", pricingMode: "standard",
  });
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 90 }),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "Le vol n'a pas encore eu lieu.",
  );
});

test("vol du jour pas encore parti : clôture acceptée (décision 6)", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  // Dernière seconde du jour au club : toujours aujourd'hui, et dans le
  // futur sauf pendant cette seconde-là.
  const endOfClubDay = (clubDay(Date.now()) + 1) * 86_400_000 - CLUB_UTC_OFFSET_MS - 1000;
  const id = await seedFlight({
    start: endOfClubDay - 60 * 60_000, end: endOfClubDay, crew: [pilot.uid], aircraftId: a,
    status: "valide", pricingMode: "standard",
  });
  const r = await closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 60 });
  assert.equal(r.billedTo, "account");
});

test("deux clôtures simultanées : une seule réussit, un seul débit", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });

  const r = await Promise.allSettled([
    closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 90 }),
    closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 90 }),
  ]);
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  const rejected = r.find((x) => x.status === "rejected") as PromiseRejectedResult;
  assert.equal(code(rejected.reason), "failed-precondition");
  assert.equal((rejected.reason as Error).message, "Ce vol est déjà clôturé.");

  const txs = await flightTx(id);
  assert.equal(txs.length, 1);
});

test("moins de 45 min standard sans montant : invalid-argument ; avec 8 000 : débit de 8 000", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id1 = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, landings: 1, flightId: id1, actualMinutes: 30 }),
    (e) => code(e) === "invalid-argument",
  );
  // Le vol n'a pas été clôturé par l'essai précédent : on peut réessayer.
  const r = await closeFlight(pilot, { ...FUEL, landings: 1, flightId: id1, actualMinutes: 30, shortFlightAmount: 8_000 });
  assert.deepEqual(r, { billedAmount: 8_000, billedTo: "account" });
});

test("montant différent avec passager : off_app, aucun mouvement de solde ; sans passager : invalid-argument", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const idWithPax = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, passengers: ["Paul"] });
  const r = await closeFlight(pilot, { ...FUEL, landings: 1, flightId: idWithPax, actualMinutes: 90, customAmount: 5_000 });
  assert.deepEqual(r, { billedAmount: 5_000, billedTo: "off_app" });
  assert.equal((await getUser(pilot.uid)).balance, 1_000_000);
  assert.equal((await flightTx(idWithPax)).length, 0);
  const f = await getFlight(idWithPax);
  assert.equal(f.pricingMode, "custom");
  assert.equal(f.billedTo, "off_app");
  assert.equal(f.billedAmount, 5_000);

  const idNoPax = await seedPastFlight({ crew: [pilot.uid], aircraftId: await seedAircraft() });
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, landings: 1, flightId: idNoPax, actualMinutes: 90, customAmount: 5_000 }),
    (e) => code(e) === "invalid-argument",
  );
});

test("montant de 250 000 : invalid-argument", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, passengers: ["Paul"] });
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 90, customAmount: 250_000 }),
    (e) => code(e) === "invalid-argument",
  );
});

test("tarifs figés : le pricingSnapshot (EXT 70 000) facture, pas le tarif courant modifié depuis", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "instructeur", category: "EXT" });
  const a = await seedAircraft();
  // Vol créé et validé dans le passé (admin), snapshot figé aux tarifs courants (EXT 70 000).
  const start = Date.now() - 2 * H;
  const { id, status } = await createFlight(admin1, {
    start, end: start + 60 * 60_000, destination: "Lomé", aircraftId: a,
    crew: [pilot.uid], passengers: [],
  });
  assert.equal(status, "valide");
  assert.equal((await getFlight(id)).pricingSnapshot.flatFee.EXT, 70_000);

  try {
    await updatePricing(admin1, {
      ...DEFAULT_PRICING, flatFee: { ...DEFAULT_PRICING.flatFee, EXT: 80_000 },
    });
    const r = await closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 60 });
    assert.equal(r.billedAmount, 70_000);
  } finally {
    await updatePricing(admin1, DEFAULT_PRICING);
  }
});

test("vol validé sans pricingSnapshot (ancien vol) : tarifs courants", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "EXT" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, pricingSnapshot: null });
  assert.equal((await getFlight(id)).pricingSnapshot, null);
  const r = await closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 60 });
  assert.equal(r.billedAmount, DEFAULT_PRICING.flatFee.EXT);
});

test("le solde peut devenir négatif", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 1_000 });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });
  const r = await closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 60 });
  assert.equal(r.billedAmount, DEFAULT_PRICING.flatFee.EXT); // EXT par défaut, 60 min < 75 incluses
  assert.equal((await getUser(pilot.uid)).balance, 1_000 - DEFAULT_PRICING.flatFee.EXT);
});

test("temps de vol plus long que prévu : fin allongée, nombres enregistrés", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const start = Date.now() - 5 * H;
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start, end: start + H });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 90, landings: 2 });
  const f = await getFlight(id);
  assert.equal(f.end.toMillis(), start + 90 * 60_000);
  assert.equal(f.landings, 2);
  assert.equal(f.waterLandings, 0);
});

test("temps de vol plus court que fin − début : fin inchangée", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const start = Date.now() - 5 * H;
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start, end: start + 3 * H });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 90, landings: 1 });
  assert.equal((await getFlight(id)).end.toMillis(), start + 3 * H);
});

test("appareil amphibie : amerrissages enregistrés", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft(true, true);
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, waterLandings: 3 });
  const f = await getFlight(id);
  assert.equal(f.landings, 1);
  assert.equal(f.waterLandings, 3);
});

test("amerrissages sur un appareil non amphibie : refusé, vol non clôturé", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, waterLandings: 1 }),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "Cet appareil n'est pas amphibie.",
  );
  assert.equal((await getFlight(id)).isClosed, false);
});

const getAircraft = async (id: string) => (await db.collection("aircraft").doc(id).get()).data()!;

test("carburant : valeurs enregistrées sur le vol, recopiées sur l'appareil", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start, end: start + H });
  await closeFlight(pilot, { flightId: id, actualMinutes: 60, landings: 1,
    fuelStartExpected: null, fuelStart: 35, fuelAdded: 20, fuelEnd: 41 });
  const f = await getFlight(id);
  assert.equal(f.fuelStartExpectedLiters, null);
  assert.equal(f.fuelStartLiters, 35);
  assert.equal(f.fuelAddedLiters, 20);
  assert.equal(f.fuelEndLiters, 41);
  const ac = await getAircraft(a);
  assert.equal(ac.fuelLiters, 41);
  assert.equal(ac.fuelFlightId, id);
  assert.equal(ac.fuelFlightStart.toMillis(), start);
});

test("carburant : clôture tardive d'un vol plus ancien, appareil inchangé", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const older = Date.now() - 30 * H;
  const newer = Date.now() - 5 * H;
  const idNew = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start: newer, end: newer + H });
  const idOld = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, start: older, end: older + H });
  await closeFlight(pilot, { ...FUEL, flightId: idNew, actualMinutes: 60, landings: 1, fuelEnd: 25 });
  await closeFlight(pilot, { ...FUEL, flightId: idOld, actualMinutes: 60, landings: 1, fuelEnd: 70 });
  assert.equal((await getFlight(idOld)).fuelEndLiters, 70);
  const ac = await getAircraft(a);
  assert.equal(ac.fuelLiters, 25);
  assert.equal(ac.fuelFlightId, idNew);
});

test("carburant manquant : invalid-argument, vol non clôturé", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a });
  await assert.rejects(
    closeFlight(pilot, { flightId: id, actualMinutes: 60, landings: 1, fuelStart: 40, fuelAdded: 0 }),
    (e) => code(e) === "invalid-argument" && (e as Error).message === "Carburant rangé invalide (0 à 100 L).",
  );
  assert.equal((await getFlight(id)).isClosed, false);
});

test("vol d'instruction de 45 min : instructeur crédité de 20 000, ligne « Crédit instruction »", async () => {
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: a, instruction: true });
  await closeFlight(stu, { ...FUEL, flightId: id, actualMinutes: 45, landings: 1, fuelEnd: 30 });
  assert.equal((await getUser(ins.uid)).balance, 20_000);
  const t = (await flightTx(id)).find((x) => x.type === "instruction")!;
  assert.equal(t.userUid, ins.uid);
  assert.equal(t.amount, 20_000);
  assert.equal(t.reason, "Crédit instruction");
  const f = await getFlight(id);
  assert.equal(f.instructionCreditUid, ins.uid);
  assert.equal(f.instructionCreditAmount, 20_000);
});

test("vol d'instruction de 44 min ou case décochée : pas de crédit", async () => {
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const short = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: a, instruction: true });
  await closeFlight(stu, { ...FUEL, flightId: short, actualMinutes: 44, landings: 1, shortFlightAmount: 8_000, fuelEnd: 32 });
  const plain = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: await seedAircraft(), instruction: false });
  await closeFlight(stu, { ...FUEL, flightId: plain, actualMinutes: 90, landings: 1, fuelEnd: 20 });
  assert.equal((await getUser(ins.uid)).balance, 0);
  assert.equal((await getFlight(short)).instructionCreditUid, null);
});

test("vol d'instruction figé avant le plan 8 : crédit par défaut (20 000)", async () => {
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const ins = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  const { instructionCredit: _i, baptismFee: _b, ...oldSnapshot } = DEFAULT_PRICING;
  const id = await seedPastFlight({ crew: [stu.uid, ins.uid], aircraftId: a, instruction: true,
    pricingSnapshot: oldSnapshot });
  await closeFlight(stu, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, fuelEnd: 25 });
  assert.equal((await getUser(ins.uid)).balance, 20_000);
});

test("baptême : 70 000 hors app quelle que soit la durée, aucun débit", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [pilot.uid], aircraftId: a, passengers: ["Paul"], pricingMode: "baptism" });
  const r = await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 20, landings: 1, fuelEnd: 35 });
  assert.deepEqual(r, { billedAmount: 70_000, billedTo: "off_app" });
  assert.equal((await getUser(pilot.uid)).balance, 0);
  assert.equal((await flightTx(id)).length, 0);
  assert.equal((await getFlight(id)).pricingMode, "baptism");
});

test("instructeur payeur de son propre vol d'instruction : débit puis crédit enchaînés", async () => {
  const ins = await seedUser({ profile: "instructeur", category: "GAP", balance: 100_000 });
  const stu = await seedUser({ profile: "eleve", category: "GAP" });
  const a = await seedAircraft();
  const id = await seedPastFlight({ crew: [ins.uid, stu.uid], payerUid: ins.uid, aircraftId: a, instruction: true });
  await closeFlight(ins, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, fuelEnd: 25 });
  const txs = await flightTx(id);
  assert.equal(txs.length, 2);
  const debit = txs.find((x) => x.type === "flight")!;
  assert.equal((await getUser(ins.uid)).balance, 100_000 + debit.amount + 20_000);
});
