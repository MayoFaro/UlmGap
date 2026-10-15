// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Cuve (spec §13) : relevés de jauge, pleins d'appareil hors vol.
import { afterEach, beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";
import { code, db, FUEL, H, resetCashbox, resetTank, seedAircraft, seedFlight, seedUser } from "../flights/testkit";
import { closeFlight } from "../flights/close";
import { addAircraftFill, addGaugeReading } from "./tank";

beforeEach(async () => { await resetTank(); await resetCashbox(); });
afterEach(async () => { await resetTank(); await resetCashbox(); });

const level = async () => ((await db.collection("tank").doc("main").get()).get("liters") as number | undefined) ?? 0;
const line = async (id: string) => (await db.collection("tankMovements").doc(id).get()).data()!;

test("relevé initial puis second relevé : écarts +300 puis -20", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const r1 = await addGaugeReading(instr, { measuredLiters: 300, date: "2026-10-12" });
  assert.equal(r1.liters, 300);
  const l1 = await line(r1.id);
  assert.equal(l1.kind, "gauge");
  assert.equal(l1.liters, 300);
  assert.equal(l1.measuredLiters, 300);
  assert.equal(l1.litersAfter, 300);
  assert.equal(l1.date, "2026-10-12");
  assert.equal(l1.by, instr.uid);
  const r2 = await addGaugeReading(instr, { measuredLiters: 280 });
  const l2 = await line(r2.id);
  assert.equal(l2.liters, -20);
  assert.equal(l2.litersAfter, 280);
  assert.equal(await level(), 280);
});

test("relevé sans écart : ligne tracée à 0", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await addGaugeReading(instr, { measuredLiters: 0 });
  const lines = await db.collection("tankMovements").get();
  assert.equal(lines.size, 1);
  assert.equal(lines.docs[0].get("liters"), 0);
});

test("plein d'un appareil : cuve -30, appareil +30, puis plafonné à 100", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await addGaugeReading(instr, { measuredLiters: 300 });
  const a = await seedAircraft();
  await db.collection("aircraft").doc(a).update({ fuelLiters: 20, fuelFlightId: "old" });
  const r = await addAircraftFill(instr, { aircraftId: a, liters: 30, note: "Plein" });
  assert.equal(r.liters, 270);
  const l = await line(r.id);
  assert.equal(l.kind, "aircraft_fill");
  assert.equal(l.liters, -30);
  assert.equal(l.aircraftId, a);
  assert.equal(l.note, "Plein");
  const ac = (await db.collection("aircraft").doc(a).get()).data()!;
  assert.equal(ac.fuelLiters, 50);
  assert.equal(ac.fuelFlightId, null);
  assert.ok(ac.fuelFlightStart);
  await addAircraftFill(instr, { aircraftId: a, liters: 80 });
  assert.equal((await db.collection("aircraft").doc(a).get()).get("fuelLiters"), 100);
  assert.equal(await level(), 190);
});

test("plein : appareil introuvable, lâché refusé", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await assert.rejects(addAircraftFill(instr, { aircraftId: "nope", liters: 10 }), (e) => code(e) === "not-found");
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  await assert.rejects(addAircraftFill(lache, { aircraftId: a, liters: 10 }), (e) => code(e) === "permission-denied");
  await assert.rejects(addGaugeReading(lache, { measuredLiters: 10 }), (e) => code(e) === "permission-denied");
});

test("clôture d'un vol plus ancien que le plein : carburant de l'appareil non écrasé", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: Date.now() - 3 * H, end: Date.now() - 2 * H, crew: [pilot.uid], payerUid: pilot.uid,
    aircraftId: a, status: "valide", pricingMode: "standard",
  });
  await addAircraftFill(instr, { aircraftId: a, liters: 60 });
  await closeFlight(pilot, { ...FUEL, landings: 1, flightId: id, actualMinutes: 60 });
  const ac = (await db.collection("aircraft").doc(a).get()).data()!;
  assert.equal(ac.fuelLiters, 60);
  assert.equal(ac.fuelFlightId, null);
  assert.ok(ac.fuelFlightStart instanceof admin.firestore.Timestamp);
});

test("deux relevés simultanés : niveau final = dernière mesure validée, litersAfter cohérents", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await addGaugeReading(instr, { measuredLiters: 100 });
  const [a, b] = await Promise.all([
    addGaugeReading(instr, { measuredLiters: 150 }),
    addGaugeReading(instr, { measuredLiters: 120 }),
  ]);
  const la = await line(a.id);
  const lb = await line(b.id);
  const [first, second] = la.at.toMillis() <= lb.at.toMillis() ? [la, lb] : [lb, la];
  assert.equal(first.litersAfter, first.measuredLiters);
  assert.equal(second.litersAfter, second.measuredLiters);
  assert.equal(second.liters, second.measuredLiters - first.litersAfter);
  assert.equal(await level(), second.measuredLiters);
});
