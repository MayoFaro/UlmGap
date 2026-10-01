// Lancé par `npm run test:int` (émulateur Firestore ; FCM remplacé par une doublure).
import { test, afterEach } from "node:test";
import * as assert from "node:assert/strict";
import { db, seedUser } from "../flights/testkit";
import { PushMessage } from "../rules/notifications";
import { sendPush, setPushSenderForTests } from "./push";

const msg: PushMessage = { title: "T", body: "B" };
const setToken = (uid: string, token: string | null) =>
  db.collection("users").doc(uid).update({ fcmToken: token });
const tokenOf = async (uid: string) => (await db.collection("users").doc(uid).get()).get("fcmToken");

afterEach(() => setPushSenderForTests(null));

test("envoie aux seuls comptes actifs destinataires qui ont un jeton", async () => {
  const sent: string[][] = [];
  setPushSenderForTests(async (tokens) => {
    sent.push(tokens);
    return { failedTokens: [], invalidTokens: [] };
  });
  const a = await seedUser({ profile: "eleve" });
  const b = await seedUser({ profile: "eleve" });
  const off = await seedUser({ profile: "eleve", active: false });
  const other = await seedUser({ profile: "eleve" });
  await setToken(a.uid, "tok-a");
  await setToken(off.uid, "tok-off");
  await setToken(other.uid, "tok-other");
  await sendPush(db, { to: [a.uid, b.uid, off.uid], message: msg });
  assert.deepEqual(sent, [["tok-a"]]);
});

test("jeton invalide : effacé", async () => {
  setPushSenderForTests(async () => ({ failedTokens: ["tok-bad"], invalidTokens: ["tok-bad"] }));
  const a = await seedUser({ profile: "eleve" });
  await setToken(a.uid, "tok-bad");
  await sendPush(db, { to: [a.uid], message: msg });
  assert.equal(await tokenOf(a.uid), null);
});

test("échec d'envoi : ne lève jamais", async () => {
  setPushSenderForTests(async () => { throw new Error("FCM indisponible"); });
  const a = await seedUser({ profile: "eleve" });
  await setToken(a.uid, "tok-a");
  await sendPush(db, { to: [a.uid], message: msg });
  assert.equal(await tokenOf(a.uid), "tok-a");
});

test("push null ou sans destinataire : rien n'est envoyé", async () => {
  let calls = 0;
  setPushSenderForTests(async () => {
    calls++;
    return { failedTokens: [], invalidTokens: [] };
  });
  await sendPush(db, null);
  await sendPush(db, { to: [], message: msg });
  const a = await seedUser({ profile: "eleve" }); // sans jeton
  await sendPush(db, { to: [a.uid], message: msg });
  assert.equal(calls, 0);
});
