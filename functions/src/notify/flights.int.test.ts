// Lancé par `npm run test:int` : notifications des actions sur les vols
// (spec §6.1), FCM remplacé par une doublure qui enregistre les envois.
import { test, beforeEach, afterEach } from "node:test";
import * as assert from "node:assert/strict";
import { at, db, draft, seedAircraft, seedUser } from "../flights/testkit";
import { createFlight, updateFlight } from "../flights/edit";
import { cancelFlight, refuseFlight, validateFlight } from "../flights/actions";
import { adminDeleteFlight } from "../flights/admin-edit";
import { PushMessage } from "../rules/notifications";
import { setPushSenderForTests } from "./push";

type Sent = { tokens: string[]; message: PushMessage };
let sent: Sent[] = [];

beforeEach(() => {
  sent = [];
  setPushSenderForTests(async (tokens, message) => {
    sent.push({ tokens, message });
    return { failedTokens: [], invalidTokens: [] };
  });
});
afterEach(() => setPushSenderForTests(null));

/** Compte avec un jeton égal à « tok-<uid> ». */
async function user(profile: string | null, isAdmin = false) {
  const u = await seedUser({ profile, isAdmin });
  await db.collection("users").doc(u.uid).update({ fcmToken: `tok-${u.uid}` });
  return u;
}
const titles = () => sent.map((s) => s.message.title);
const tokensOf = (title: string) => sent.filter((s) => s.message.title === title).flatMap((s) => s.tokens);

test("demande : l'instructeur est notifié, puis à la modification", async () => {
  const eleve = await user("eleve");
  const ins = await user("instructeur");
  const a = await seedAircraft();
  const { id } = await createFlight(eleve, draft(a, [eleve.uid, ins.uid]));
  assert.deepEqual(tokensOf("Nouvelle demande de vol"), [`tok-${ins.uid}`]);
  await updateFlight(eleve, { flightId: id, ...draft(a, [eleve.uid, ins.uid], { destination: "Kara" }) });
  assert.deepEqual(tokensOf("Demande de vol modifiée"), [`tok-${ins.uid}`]);
});

test("vol validé directement : aucune notification", async () => {
  const lache = await user("lache_toute_mission");
  await createFlight(lache, draft(await seedAircraft(), [lache.uid]));
  assert.deepEqual(sent, []);
});

test("validation : le créateur est notifié, pas l'instructeur ; avec modifications", async () => {
  const eleve = await user("eleve");
  const ins = await user("instructeur");
  const a = await seedAircraft();
  const { id } = await createFlight(eleve, draft(a, [eleve.uid, ins.uid]));
  sent = [];
  await validateFlight(ins, { flightId: id });
  assert.deepEqual(tokensOf("Vol validé"), [`tok-${eleve.uid}`]);

  const second = await createFlight(eleve, draft(a, [eleve.uid, ins.uid], { start: at(14), end: at(15) }));
  sent = [];
  await validateFlight(ins, { flightId: second.id, changes: { start: at(14.5), end: at(15.5) } });
  assert.deepEqual(titles(), ["Vol validé avec modifications"]);
});

test("refus : le créateur reçoit le motif", async () => {
  const eleve = await user("eleve");
  const ins = await user("instructeur");
  const { id } = await createFlight(eleve, draft(await seedAircraft(), [eleve.uid, ins.uid]));
  sent = [];
  await refuseFlight(ins, { flightId: id, reason: "Météo" });
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0].tokens, [`tok-${eleve.uid}`]);
  assert.equal(sent[0].message.title, "Demande refusée");
  assert.match(sent[0].message.body, /Motif : Météo$/);
});

test("annulation d'un vol validé : équipage et instructeur, pas l'auteur ; demande : rien", async () => {
  const lache = await user("lache_toute_mission");
  const mate = await user("eleve");
  const a = await seedAircraft();
  const { id } = await createFlight(lache, draft(a, [lache.uid, mate.uid]));
  sent = [];
  await cancelFlight(lache, { flightId: id });
  assert.deepEqual(tokensOf("Vol annulé"), [`tok-${mate.uid}`]);

  const eleve = await user("eleve");
  const ins = await user("instructeur");
  const req = await createFlight(eleve, draft(a, [eleve.uid, ins.uid], { start: at(14), end: at(15) }));
  sent = [];
  await cancelFlight(eleve, { flightId: req.id });
  assert.deepEqual(sent, []);
});

test("suppression admin d'un vol validé non clôturé : « Vol annulé »", async () => {
  const boss = await user(null, true);
  const lache = await user("lache_toute_mission");
  const { id } = await createFlight(lache, draft(await seedAircraft(), [lache.uid]));
  sent = [];
  await adminDeleteFlight(boss, { flightId: id });
  assert.deepEqual(tokensOf("Vol annulé"), [`tok-${lache.uid}`]);
});

test("échec d'envoi : l'action réussit quand même", async () => {
  setPushSenderForTests(async () => { throw new Error("FCM indisponible"); });
  const eleve = await user("eleve");
  const ins = await user("instructeur");
  const { id, status } = await createFlight(eleve, draft(await seedAircraft(), [eleve.uid, ins.uid]));
  assert.equal(status, "demande");
  await validateFlight(ins, { flightId: id });
  assert.equal((await db.collection("flights").doc(id).get()).get("status"), "valide");
});
