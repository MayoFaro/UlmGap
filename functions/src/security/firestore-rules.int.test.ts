// Lancé par `npm run test:int` (émulateur Firestore).
import { after, before, beforeEach, test } from "node:test";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  RulesTestEnvironment, assertFails, assertSucceeds, initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";

let env: RulesTestEnvironment;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-ulmgap-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/eleve"), { active: true, isAdmin: false, profile: "eleve", balance: 0 });
    await setDoc(doc(db, "users/instr"), { active: true, isAdmin: false, profile: "instructeur" });
    await setDoc(doc(db, "users/off"), { active: false, isAdmin: false, profile: "eleve" });
    await setDoc(doc(db, "profiles/eleve"), { displayName: "E", shortName: "ELE" });
    await setDoc(doc(db, "aircraft/a1"), { registration: "F-JABC" });
    await setDoc(doc(db, "flights/f1"), { status: "valide" });
    await setDoc(doc(db, "transactions/t1"), { userUid: "eleve", amount: 100 });
    await setDoc(doc(db, "transactions/t2"), { userUid: "instr", amount: 100 });
  });
});

const as = (uid: string, verified = true) =>
  env.authenticatedContext(uid, { email_verified: verified }).firestore();

test("e-mail non vérifié : aucune lecture", async () => {
  await assertFails(getDoc(doc(as("eleve", false), "flights/f1")));
  await assertFails(getDoc(doc(as("eleve", false), "users/eleve")));
});

test("compte inactif : aucune lecture", async () => {
  await assertFails(getDoc(doc(as("off"), "flights/f1")));
  await assertFails(getDoc(doc(as("off"), "profiles/eleve")));
});

test("anonyme : aucune lecture", async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "flights/f1")));
});

test("connecté : lit flights, aircraft, profiles, settings", async () => {
  const db = as("eleve");
  await assertSucceeds(getDoc(doc(db, "flights/f1")));
  await assertSucceeds(getDoc(doc(db, "aircraft/a1")));
  await assertSucceeds(getDoc(doc(db, "profiles/eleve")));
  await assertSucceeds(getDoc(doc(db, "settings/pricing")));
});

test("users : soi-même oui, les autres non ; instructeur : tous", async () => {
  await assertSucceeds(getDoc(doc(as("eleve"), "users/eleve")));
  await assertFails(getDoc(doc(as("eleve"), "users/instr")));
  await assertSucceeds(getDoc(doc(as("instr"), "users/eleve")));
});

test("users : seul fcmToken est modifiable, et seulement le sien", async () => {
  await assertSucceeds(updateDoc(doc(as("eleve"), "users/eleve"), { fcmToken: "t" }));
  await assertFails(updateDoc(doc(as("eleve"), "users/eleve"), { balance: 999999 }));
  await assertFails(updateDoc(doc(as("eleve"), "users/eleve"), { isAdmin: true }));
  await assertFails(updateDoc(doc(as("instr"), "users/eleve"), { fcmToken: "t" }));
});

test("transactions : les siennes ; instructeur : toutes", async () => {
  await assertSucceeds(getDoc(doc(as("eleve"), "transactions/t1")));
  await assertFails(getDoc(doc(as("eleve"), "transactions/t2")));
  await assertSucceeds(getDoc(doc(as("instr"), "transactions/t2")));
});

test("M5 : fcmToken doit être une chaîne raisonnable ou null", async () => {
  const db = as("eleve");
  await assertSucceeds(updateDoc(doc(db, "users/eleve"), { fcmToken: null }));
  await assertFails(updateDoc(doc(db, "users/eleve"), { fcmToken: 123 }));
  await assertFails(updateDoc(doc(db, "users/eleve"), { fcmToken: "x".repeat(5000) }));
});

test("aucune écriture client sur les collections métier", async () => {
  const db = as("instr");
  await assertFails(setDoc(doc(db, "flights/new"), { status: "valide" }));
  await assertFails(setDoc(doc(db, "aircraft/new"), { registration: "X" }));
  await assertFails(setDoc(doc(db, "profiles/instr"), { shortName: "X" }));
  await assertFails(setDoc(doc(db, "transactions/new"), { amount: 1 }));
  await assertFails(setDoc(doc(db, "settings/pricing"), { hourlyRate: 1 }));
  await assertFails(setDoc(doc(db, "autre/x"), { a: 1 }));
});
