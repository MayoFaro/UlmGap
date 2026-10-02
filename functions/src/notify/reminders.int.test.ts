// Lancé par `npm run test:int` : rappels de clôture (plan 5, décision 2),
// FCM remplacé par une doublure. Seuls les envois aux jetons de ce fichier
// sont examinés (base partagée avec les autres fichiers de test).
import { test, beforeEach, afterEach } from "node:test";
import * as assert from "node:assert/strict";
import { db, H, seedAircraft, seedFlight, seedUser } from "../flights/testkit";
import { PushMessage } from "../rules/notifications";
import { setPushSenderForTests } from "./push";
import { sendClosingReminders } from "./reminders";

let sent: { tokens: string[]; message: PushMessage }[] = [];
beforeEach(() => {
  sent = [];
  setPushSenderForTests(async (tokens, message) => {
    sent.push({ tokens, message });
    return { failedTokens: [], invalidTokens: [] };
  });
});
afterEach(() => setPushSenderForTests(null));

async function pilot() {
  const u = await seedUser({ profile: "lache_toute_mission" });
  await db.collection("users").doc(u.uid).update({ fcmToken: `tok-${u.uid}` });
  return u;
}
const remindersTo = (uid: string) =>
  sent.filter((s) => s.message.title === "Vol à clôturer" && s.tokens.includes(`tok-${uid}`)).length;
const flight = async (crew: string, endAgoH: number, now: number, o: Record<string, unknown> = {}) =>
  seedFlight({
    start: now - (endAgoH + 1) * H, end: now - endAgoH * H, crew: [crew],
    aircraftId: await seedAircraft(), ...o,
  });

test("25 h après la fin : rappel et lastReminderAt ; pas de doublon 1 h après ; nouveau rappel à 48 h",
  async () => {
    const now = Date.now();
    const p = await pilot();
    const id = await flight(p.uid, 25, now);
    await sendClosingReminders(db, now);
    assert.equal(remindersTo(p.uid), 1);
    assert.equal((await db.collection("flights").doc(id).get()).get("lastReminderAt").toMillis(), now);

    await sendClosingReminders(db, now + H);
    assert.equal(remindersTo(p.uid), 1);

    await sendClosingReminders(db, now + 48 * H);
    assert.equal(remindersTo(p.uid), 2);
  });

test("23 h après la fin : pas encore", async () => {
  const now = Date.now();
  const p = await pilot();
  await flight(p.uid, 23, now);
  await sendClosingReminders(db, now);
  assert.equal(remindersTo(p.uid), 0);
});

test("vol clôturé, supprimé, demande ou refusé : jamais", async () => {
  const now = Date.now();
  const p = await pilot();
  await flight(p.uid, 30, now, { isClosed: true });
  await flight(p.uid, 30, now, { deleted: true });
  await flight(p.uid, 30, now, { status: "demande" });
  await flight(p.uid, 30, now, { status: "refuse" });
  await sendClosingReminders(db, now);
  assert.equal(remindersTo(p.uid), 0);
});

test("échec d'envoi : la tâche continue et note quand même le rappel", async () => {
  setPushSenderForTests(async () => { throw new Error("FCM indisponible"); });
  const now = Date.now();
  const p = await pilot();
  const id = await flight(p.uid, 25, now);
  await sendClosingReminders(db, now);
  assert.equal((await db.collection("flights").doc(id).get()).get("lastReminderAt").toMillis(), now);
});

test("un vol mal formé n'empêche pas les rappels des autres vols", async () => {
  const now = Date.now();
  const p = await pilot();
  // Vol corrompu (fin illisible), lu avant ou après le bon vol selon l'ordre de la requête.
  await db.collection("flights").doc().set({
    status: "valide", isClosed: false, deleted: false, crew: [p.uid], end: "illisible",
  });
  await flight(p.uid, 25, now);
  await sendClosingReminders(db, now);
  assert.equal(remindersTo(p.uid), 1);
});
