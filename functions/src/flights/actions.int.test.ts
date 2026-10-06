// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { at, code, db, draft, H, seedAircraft, seedFlight, seedUser } from "./testkit";
import { createFlight } from "./edit";
import { cancelFlight, refuseFlight, validateFlight } from "./actions";

const get = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;

async function request(o: { category?: string } = {}) {
  const eleve = await seedUser({ profile: "eleve", category: o.category });
  const instr = await seedUser({ profile: "instructeur", category: o.category });
  const a = await seedAircraft();
  const { id } = await createFlight(eleve, draft(a, [eleve.uid, instr.uid]));
  return { eleve, instr, a, id };
}

test("validation par l'instructeur désigné, avec modifications et carburant", async () => {
  const { instr, id } = await request({ category: "GAP" });
  await validateFlight(instr, {
    flightId: id, changes: { destination: "Kara", end: at(12), pricingMode: "fuel_only" },
  });
  const f = await get(id);
  assert.equal(f.status, "valide");
  assert.equal(f.destination, "Kara");
  assert.equal(f.end.toMillis(), at(12));
  assert.equal(f.pricingMode, "fuel_only");
});

test("appel direct : l'élève ne valide pas sa propre demande ; un autre instructeur non plus", async () => {
  const { eleve, id } = await request();
  const other = await seedUser({ profile: "instructeur" });
  await assert.rejects(validateFlight(eleve, { flightId: id }), (e) => code(e) === "permission-denied");
  await assert.rejects(validateFlight(other, { flightId: id }), (e) => code(e) === "permission-denied");
});

test("admin : peut valider une demande dont il n'est pas l'instructeur", async () => {
  const { id } = await request();
  const adm = await seedUser({ profile: null, isAdmin: true });
  await validateFlight(adm, { flightId: id });
  assert.equal((await get(id)).status, "valide");
});

test("demande expirée (départ passé) : validation et refus rejetés", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur" });
  const id = await seedFlight({
    start: Date.now() - H, end: Date.now() + H, aircraftId: await seedAircraft(),
    crew: [eleve.uid, instr.uid], createdBy: eleve.uid, instructorUid: instr.uid, status: "demande",
  });
  await assert.rejects(validateFlight(instr, { flightId: id }),
    (e) => code(e) === "failed-precondition" && /expirée/.test((e as Error).message));
  await assert.rejects(refuseFlight(instr, { flightId: id }), (e) => code(e) === "failed-precondition");
});

test("validation bloquée par un conflit : la demande reste une demande", async () => {
  const { instr, a, id } = await request();
  const other = await seedUser({ profile: "instructeur" });
  await createFlight(other, draft(a, [other.uid]));
  await assert.rejects(validateFlight(instr, { flightId: id }), (e) => code(e) === "failed-precondition");
  assert.equal((await get(id)).status, "demande");
});

test("valider un vol déjà validé : failed-precondition", async () => {
  const { instr, id } = await request();
  await validateFlight(instr, { flightId: id });
  await assert.rejects(validateFlight(instr, { flightId: id }), (e) => code(e) === "failed-precondition");
});

test("refus avec motif", async () => {
  const { instr, id } = await request();
  await refuseFlight(instr, { flightId: id, reason: "Météo" });
  const f = await get(id);
  assert.equal(f.status, "refuse");
  assert.equal(f.refusalReason, "Météo");
});

test("annulation : créateur oui, inconnu non ; le créneau est libéré", async () => {
  const me = await seedUser({ profile: "instructeur" });
  const stranger = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const { id } = await createFlight(me, draft(a, [me.uid]));
  await assert.rejects(cancelFlight(stranger, { flightId: id }), (e) => code(e) === "permission-denied");
  await cancelFlight(me, { flightId: id });
  assert.equal((await get(id)).deleted, true);
  await createFlight(stranger, draft(a, [stranger.uid])); // plus de conflit
});

test("annulation par l'instructeur désigné, malgré un membre devenu inactif", async () => {
  const { eleve, instr, id } = await request();
  await db.collection("users").doc(eleve.uid).update({ active: false });
  await cancelFlight(instr, { flightId: id });
  assert.equal((await get(id)).deleted, true);
});

test("annulation après le départ : refusée", async () => {
  const me = await seedUser({ profile: "instructeur" });
  const id = await seedFlight({
    start: Date.now() - H, end: Date.now() + H, aircraftId: await seedAircraft(),
    crew: [me.uid], createdBy: me.uid,
  });
  await assert.rejects(cancelFlight(me, { flightId: id }), (e) => code(e) === "failed-precondition");
});

test("vol supprimé : not-found", async () => {
  const me = await seedUser({ profile: "instructeur" });
  const { id } = await createFlight(me, draft(await seedAircraft(), [me.uid]));
  await cancelFlight(me, { flightId: id });
  await assert.rejects(cancelFlight(me, { flightId: id }), (e) => code(e) === "not-found");
});

test("validation : l'instructeur coche le vol d'instruction", async () => {
  const { instr, id } = await request();
  await validateFlight(instr, { flightId: id, changes: { instruction: true } });
  assert.equal((await get(id)).instruction, true);
});

test("validation : baptême refusé sur un vol sans passager", async () => {
  const { instr, id } = await request();
  await assert.rejects(validateFlight(instr, { flightId: id, changes: { baptism: true } }),
    (e) => code(e) === "invalid-argument" &&
      (e as Error).message === "Baptême de l'air réservé à un vol avec un passager sans compte.");
  assert.equal((await get(id)).status, "demande");
});

test("validation : le baptême du vol est conservé", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(10), end: at(11), aircraftId: a, crew: [eleve.uid, instr.uid], createdBy: eleve.uid,
    instructorUid: instr.uid, status: "demande", passengers: ["Paul"], pricingMode: "baptism",
    baptismTier: "local",
  });
  await validateFlight(instr, { flightId: id });
  assert.equal((await get(id)).pricingMode, "baptism");
  assert.equal((await get(id)).baptismTier, "local"); // conservé tel que stocké
});

test("validation : l'instructeur choisit le forfait du baptême", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(10), end: at(11), aircraftId: a, crew: [eleve.uid, instr.uid], createdBy: eleve.uid,
    instructorUid: instr.uid, status: "demande", passengers: ["Paul"], pricingMode: "baptism",
    baptismTier: "local",
  });
  await validateFlight(instr, { flightId: id, changes: { baptismTier: "nyonye" } });
  assert.equal((await get(id)).baptismTier, "nyonye");
});

test("validation : charge utile exacte de l'app (baptismTier null), demande ordinaire", async () => {
  const { instr, id } = await request();
  await validateFlight(instr, {
    flightId: id,
    changes: {
      start: at(10), end: at(11), destination: "Kara", aircraftId: (await get(id)).aircraftId,
      instruction: false, baptism: false, baptismTier: null,
    },
  });
  assert.equal((await get(id)).status, "valide");
});

test("validation : baptême avec baptismTier null garde le forfait enregistré", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(10), end: at(11), aircraftId: a, crew: [eleve.uid, instr.uid], createdBy: eleve.uid,
    instructorUid: instr.uid, status: "demande", passengers: ["Paul"], pricingMode: "baptism",
    baptismTier: "awagne",
  });
  await validateFlight(instr, { flightId: id, changes: { baptism: true, baptismTier: null } });
  const f = await get(id);
  assert.equal(f.status, "valide");
  assert.equal(f.baptismTier, "awagne");
});

// --- Plan 10 : lâché amphibie (spec §3.6) ---

test("amphibie : un instructeur non lâché ne valide pas une demande passée sur amphibie", async () => {
  const { instr, id } = await request();
  const amphib = await seedAircraft(true, true);
  await assert.rejects(validateFlight(instr, { flightId: id, changes: { aircraftId: amphib } }),
    (e) => code(e) === "permission-denied" &&
      (e as Error).message === "Appareil amphibie : l'instructeur doit être lâché amphibie.");
  assert.equal((await get(id)).status, "demande");
});

test("amphibie : un instructeur lâché valide ; un admin non lâché valide aussi", async () => {
  const amphib = await seedAircraft(true, true);
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur", amphibiousCleared: true });
  const plain = await seedAircraft();
  const { id } = await createFlight(eleve, draft(plain, [eleve.uid, instr.uid]));
  await validateFlight(instr, { flightId: id, changes: { aircraftId: amphib } });
  assert.equal((await get(id)).status, "valide");

  const r = await request();
  const adm = await seedUser({ profile: null, isAdmin: true });
  await validateFlight(adm, { flightId: r.id, changes: { aircraftId: amphib, start: at(14), end: at(15) } });
  assert.equal((await get(r.id)).status, "valide");
});
