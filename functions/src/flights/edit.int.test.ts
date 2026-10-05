// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { at, code, db, details, draft, H, seedAircraft, seedFlight, seedUser } from "./testkit";
import { createFlight, updateFlight } from "./edit";

const get = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;

test("élève + instructeur : demande, champs du contrat et payeur", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const { id, status } = await createFlight(eleve, draft(a, [eleve.uid, instr.uid]));
  assert.equal(status, "demande");
  const f = await get(id);
  assert.equal(f.status, "demande");
  assert.equal(f.instructorUid, instr.uid);
  assert.equal(f.payerUid, eleve.uid);
  assert.equal(f.createdBy, eleve.uid);
  assert.equal(f.pricingMode, "standard");
  assert.match(f.aircraft, /^F-/);
  assert.deepEqual(f.crew, [eleve.uid, instr.uid]);
  assert.deepEqual(f.passengers, []);
  assert.equal(f.deleted, false);
  assert.equal(f.isClosed, false);
  assert.equal(f.reminderGen, 0);
  assert.equal(f.pricingSnapshot, null);
  assert.ok(f.updatedAt);
  assert.equal(f.start.toMillis(), at(10));
});

test("matrice : élève seul refusé (permission-denied)", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  await assert.rejects(createFlight(eleve, draft(await seedAircraft(), [eleve.uid])),
    (e) => code(e) === "permission-denied");
});

test("appel direct : un lâché ne crée pas un vol dont il ne fait pas partie", async () => {
  const me = await seedUser({ profile: "lache_toute_mission" });
  const other = await seedUser({ profile: "lache_toute_mission" });
  await assert.rejects(createFlight(me, draft(await seedAircraft(), [other.uid])),
    (e) => code(e) === "permission-denied" &&
      (e as Error).message === "Vous devez faire partie de l'équipage.");
});

test("admin hors équipage : élève + instructeur → valide", async () => {
  const adm = await seedUser({ profile: null, isAdmin: true });
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur" });
  const { status } = await createFlight(adm, draft(await seedAircraft(), [eleve.uid, instr.uid]));
  assert.equal(status, "valide");
});

test("instructeur hors équipage : élève seul → valide", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const eleve = await seedUser({ profile: "eleve" });
  const { status } = await createFlight(instr, draft(await seedAircraft(), [eleve.uid]));
  assert.equal(status, "valide");
});

test("non connecté : unauthenticated", async () => {
  await assert.rejects(createFlight(undefined, {}), (e) => code(e) === "unauthenticated");
});

test("départ passé : failed-precondition (non admin)", async () => {
  const me = await seedUser({ profile: "instructeur" });
  await assert.rejects(
    createFlight(me, draft(await seedAircraft(), [me.uid], { start: Date.now() - H, end: Date.now() })),
    (e) => code(e) === "failed-precondition");
});

test("admin : saisie après coup d'un vol passé → valide, sans contrôle de conflit (conduite)", async () => {
  const adm = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const past = { start: Date.now() - 3 * H, end: Date.now() - 2 * H };
  const { id, status } = await createFlight(adm, draft(a, [pilot.uid], past));
  assert.equal(status, "valide");
  assert.equal((await get(id)).start.toMillis(), past.start);
  // Révision du 2026-10-01 : un vol passé relève de la conduite, jamais bloqué.
  const other = await seedUser({ profile: "instructeur" });
  const second = await createFlight(adm, draft(a, [other.uid], past));
  assert.equal(second.status, "valide");
});

test("membre inactif ou appareil inactif : failed-precondition, message explicite", async () => {
  const me = await seedUser({ profile: "lache_toute_mission" });
  const off = await seedUser({ profile: "eleve", active: false, shortName: "OFF" });
  await assert.rejects(createFlight(me, draft(await seedAircraft(), [me.uid, off.uid])),
    (e) => code(e) === "failed-precondition" && /OFF/.test((e as Error).message));
  await assert.rejects(createFlight(me, draft(await seedAircraft(false), [me.uid])),
    (e) => code(e) === "failed-precondition");
});

test("conflits : même appareil bloquant avec détails ; bornes ouvertes ; demandes non bloquantes", async () => {
  const p1 = await seedUser({ profile: "instructeur" });
  const p2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  await createFlight(p1, draft(a, [p1.uid]));
  await assert.rejects(createFlight(p2, draft(a, [p2.uid], { start: at(10.5), end: at(11.5) })),
    (e) => code(e) === "failed-precondition" && details(e)?.conflict?.start === at(10));
  // Écart de 30 min exactement : pas de conflit (plan 9).
  await createFlight(p2, draft(a, [p2.uid], { start: at(11.5), end: at(12.5) }));
  // Une demande peut chevaucher un vol validé.
  const eleve = await seedUser({ profile: "eleve" });
  const { status } = await createFlight(eleve, draft(a, [eleve.uid, p1.uid]));
  assert.equal(status, "demande");
});

test("battement de 30 min : refus à 20 min d'écart avec le message exact, accepté à 30 min", async () => {
  const p1 = await seedUser({ profile: "instructeur" });
  const p2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  await createFlight(p1, draft(a, [p1.uid]));
  await assert.rejects(createFlight(p2, draft(a, [p2.uid], { start: at(11 + 1 / 3), end: at(12 + 1 / 3) })),
    (e) => code(e) === "failed-precondition" &&
      (e as Error).message === "Conflit avec un autre vol validé (30 min d'écart minimum).");
  await createFlight(p2, draft(a, [p2.uid], { start: at(11.5), end: at(12.5) }));
});

test("battement de 30 min : la requête trouve un vol terminé 10 min avant le début", async () => {
  const p1 = await seedUser({ profile: "instructeur" });
  const p2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  await seedFlight({ start: at(9.5), end: at(10 + 5 / 6), crew: [p1.uid], aircraftId: a }); // fin 10 h 50
  await assert.rejects(createFlight(p2, draft(a, [p2.uid], { start: at(11), end: at(12) })),
    (e) => code(e) === "failed-precondition" && details(e)?.conflict?.end === at(10 + 5 / 6));
});

test("conflits : même personne sur un autre appareil", async () => {
  const p = await seedUser({ profile: "instructeur" });
  await createFlight(p, draft(await seedAircraft(), [p.uid]));
  await assert.rejects(createFlight(p, draft(await seedAircraft(), [p.uid])),
    (e) => code(e) === "failed-precondition");
});

test("création concurrente du même créneau : une seule passe", async () => {
  const p1 = await seedUser({ profile: "instructeur" });
  const p2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const r = await Promise.allSettled([
    createFlight(p1, draft(a, [p1.uid])),
    createFlight(p2, draft(a, [p2.uid])),
  ]);
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  const rejected = r.find((x) => x.status === "rejected");
  assert.equal(code((rejected as PromiseRejectedResult).reason), "failed-precondition");
});

test("mode : GAP + passager → fuel_only ; instructeur GAP choisit carburant ; lâché non", async () => {
  const gap = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const r1 = await createFlight(gap, draft(await seedAircraft(), [gap.uid], { passengers: ["Paul"] }));
  assert.equal((await get(r1.id)).pricingMode, "fuel_only");

  const instr = await seedUser({ profile: "instructeur", category: "GAP" });
  const gap2 = await seedUser({ profile: "eleve", category: "GAP" });
  const r2 = await createFlight(instr,
    draft(await seedAircraft(), [instr.uid, gap2.uid], { pricingMode: "fuel_only" }));
  assert.equal((await get(r2.id)).pricingMode, "fuel_only");

  const gap3 = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const r3 = await createFlight(gap,
    draft(await seedAircraft(), [gap.uid, gap3.uid], { start: at(20), end: at(21), pricingMode: "fuel_only" }));
  assert.equal((await get(r3.id)).pricingMode, "standard");
});

test("modification : seul le créateur", async () => {
  const me = await seedUser({ profile: "instructeur" });
  const other = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const { id } = await createFlight(me, draft(a, [me.uid]));
  await assert.rejects(updateFlight(other, { flightId: id, ...draft(a, [me.uid]) }),
    (e) => code(e) === "permission-denied");
});

test("modification d'un vol validé sans changer de créneau : pas de conflit avec lui-même", async () => {
  const me = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const { id } = await createFlight(me, draft(a, [me.uid]));
  const { status } = await updateFlight(me, { flightId: id, ...draft(a, [me.uid], { destination: "Kara" }) });
  assert.equal(status, "valide");
  assert.equal((await get(id)).destination, "Kara");
});

test("modification par un lâché qui ajoute un instructeur : redevient demande", async () => {
  const me = await seedUser({ profile: "lache_toute_mission" });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const { id } = await createFlight(me, draft(a, [me.uid]));
  const { status } = await updateFlight(me, { flightId: id, ...draft(a, [me.uid, instr.uid]) });
  assert.equal(status, "demande");
  assert.equal((await get(id)).instructorUid, instr.uid);
});

test("un vol refusé modifié repart en demande, motif effacé", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(30), end: at(31), aircraftId: a, crew: [eleve.uid, instr.uid], createdBy: eleve.uid,
    instructorUid: instr.uid, status: "refuse", refusalReason: "Météo",
  });
  const { status } = await updateFlight(eleve,
    { flightId: id, ...draft(a, [eleve.uid, instr.uid], { start: at(32), end: at(33) }) });
  assert.equal(status, "demande");
  assert.equal((await get(id)).refusalReason, null);
});

test("modification après le départ ou d'un vol avec un membre devenu inactif : refusée", async () => {
  const me = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const past = await seedFlight({
    start: Date.now() - H, end: Date.now() + H, aircraftId: a, crew: [me.uid], createdBy: me.uid,
  });
  await assert.rejects(updateFlight(me, { flightId: past, ...draft(a, [me.uid]) }),
    (e) => code(e) === "failed-precondition");

  const mate = await seedUser({ profile: "eleve", shortName: "MAT" });
  const { id } = await createFlight(me, draft(a, [me.uid, mate.uid], { start: at(40), end: at(41) }));
  await db.collection("users").doc(mate.uid).update({ active: false });
  await assert.rejects(
    updateFlight(me, { flightId: id, ...draft(a, [me.uid, mate.uid], { start: at(40), end: at(41), destination: "Kara" }) }),
    (e) => code(e) === "failed-precondition" && /MAT/.test((e as Error).message));
});

test("compte débité : un lâché ne place pas un autre en premier (appel direct)", async () => {
  const me = await seedUser({ profile: "lache_toute_mission" });
  const other = await seedUser({ profile: "lache_toute_mission" });
  await assert.rejects(createFlight(me, draft(await seedAircraft(), [other.uid, me.uid])),
    (e) => code(e) === "permission-denied");
  const a = await seedAircraft();
  const { id } = await createFlight(me, draft(a, [me.uid, other.uid]));
  await assert.rejects(updateFlight(me, { flightId: id, ...draft(a, [other.uid, me.uid]) }),
    (e) => code(e) === "permission-denied");
});

test("carburant choisi par l'instructeur : conservé quand le créateur non instructeur modifie", async () => {
  const eleve = await seedUser({ profile: "eleve", category: "GAP" });
  const instr = await seedUser({ profile: "instructeur", category: "GAP" });
  const a = await seedAircraft();
  const id = await seedFlight({
    start: at(50), end: at(51), aircraftId: a, crew: [eleve.uid, instr.uid], createdBy: eleve.uid,
    instructorUid: instr.uid, status: "valide", pricingMode: "fuel_only",
  });
  await updateFlight(eleve, { flightId: id, ...draft(a, [eleve.uid, instr.uid], { start: at(50), end: at(51), destination: "Kara" }) });
  assert.equal((await get(id)).pricingMode, "fuel_only");
});

test("carburant imposé par un passager : perdu quand le passager est retiré", async () => {
  const gap = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const a = await seedAircraft();
  const { id } = await createFlight(gap, draft(a, [gap.uid], { start: at(60), end: at(61), passengers: ["Paul"] }));
  assert.equal((await get(id)).pricingMode, "fuel_only");
  await updateFlight(gap, { flightId: id, ...draft(a, [gap.uid], { start: at(60), end: at(61) }) });
  assert.equal((await get(id)).pricingMode, "standard");
});

test("conflit : la cause (appareil ou personne) est dans les détails", async () => {
  const p1 = await seedUser({ profile: "instructeur" });
  const p2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  await createFlight(p1, draft(a, [p1.uid], { start: at(70), end: at(71) }));
  await assert.rejects(createFlight(p2, draft(a, [p2.uid], { start: at(70), end: at(71) })),
    (e) => details(e)?.conflict?.kind === "aircraft");
  await assert.rejects(createFlight(p1, draft(await seedAircraft(), [p1.uid], { start: at(70), end: at(71) })),
    (e) => details(e)?.conflict?.kind === "crew" &&
      JSON.stringify(details(e)?.conflict?.members) === JSON.stringify([p1.uid]));
});

test("planification : un vol clôturé (même à venir) ne bloque jamais un nouveau vol", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  await seedFlight({ start: at(10), end: at(11), crew: [pilot.uid], aircraftId: a, isClosed: true });
  const r = await createFlight(pilot, draft(a, [pilot.uid], { start: at(10), end: at(11) }));
  assert.equal((await db.collection("flights").doc(r.id).get()).get("status"), "valide");
});

test("planification : un vol validé à venir non clôturé bloque toujours", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  await seedFlight({ start: at(10), end: at(11), crew: [pilot.uid], aircraftId: a });
  await assert.rejects(createFlight(pilot, draft(a, [pilot.uid], { start: at(10), end: at(11) })),
    (e) => code(e) === "failed-precondition" && details(e)?.conflict !== undefined);
});

test("vol d'instruction : enregistré avec un instructeur et un élève", async () => {
  const ins = await seedUser({ profile: "instructeur" });
  const stu = await seedUser({ profile: "eleve" });
  const a = await seedAircraft();
  const { id } = await createFlight(ins, { ...draft(a, [stu.uid, ins.uid]), instruction: true });
  assert.equal((await get(id)).instruction, true);
});

test("vol d'instruction hors condition : refusé", async () => {
  const ins = await seedUser({ profile: "instructeur" });
  const ins2 = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  for (const crew of [[ins.uid], [ins.uid, ins2.uid]]) {
    await assert.rejects(createFlight(ins, { ...draft(a, crew), instruction: true }),
      (e) => code(e) === "invalid-argument" &&
        (e as Error).message === "Vol d'instruction : il faut un instructeur et un autre membre avec compte.");
  }
});

test("baptême : mode baptism, pas de contrôle de crédit (solde nul)", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await createFlight(pilot, { ...draft(a, [pilot.uid], { passengers: ["Paul"] }), baptism: true, baptismTier: "awagne" });
  const f = await get(id);
  assert.equal(f.pricingMode, "baptism");
  assert.equal(f.baptismTier, "awagne");
  assert.equal(f.instruction, false);
});

test("baptême retiré avec le passager : mode recalculé", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const d = draft(a, [pilot.uid], { passengers: ["Paul"] });
  const { id } = await createFlight(pilot, { ...d, baptism: true, baptismTier: "local" });
  await updateFlight(pilot, { flightId: id, ...d, passengers: [] });
  assert.equal((await get(id)).pricingMode, "standard");
  assert.equal((await get(id)).baptismTier, null);
});
