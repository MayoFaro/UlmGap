// Lancé par `npm run test:int` (émulateur Firestore).
import { after, before, beforeEach, test } from "node:test";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  RulesTestEnvironment, assertFails, assertSucceeds, initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { and, collection, doc, getDoc, getDocs, or, orderBy, query, setDoc, Timestamp, updateDoc, where } from "firebase/firestore";

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
    await setDoc(doc(db, "users/adm"), { active: true, isAdmin: true, profile: null });
    await setDoc(doc(db, "cashbox/main"), { balance: 0 });
    await setDoc(doc(db, "cashMovements/c1"), { kind: "fuel_purchase", amount: -1 });
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

// Une demande, même refusée/expirée/annulée, reste entre ses deux interlocuteurs.
async function seedPrivateRequests() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/other"), { active: true, isAdmin: false, profile: "instructeur" });
    await setDoc(doc(db, "users/admin"), { active: true, isAdmin: true, profile: null });
    for (const [id, status, deleted] of [
      ["pending", "demande", false], ["refused", "refuse", false],
      ["cancelled", "demande", true],
    ] as const) {
      await setDoc(doc(db, `flights/${id}`), {
        status, deleted, createdBy: "eleve", instructorUid: "instr",
        crew: ["eleve", "instr"], start: Timestamp.fromMillis(1000),
      });
    }
    await updateDoc(doc(db, "flights/f1"), {
      start: Timestamp.fromMillis(2000), aircraftId: "a1", payerUid: "eleve", isClosed: false,
    });
  });
}

test("demandes privées : lecture réservée au demandeur et à l'instructeur désigné, sans exception admin", async () => {
  await seedPrivateRequests();
  for (const id of ["pending", "refused", "cancelled"]) {
    for (const uid of ["eleve", "instr"]) {
      await assertSucceeds(getDoc(doc(as(uid), `flights/${id}`)));
    }
    for (const uid of ["other", "admin"]) {
      await assertFails(getDoc(doc(as(uid), `flights/${id}`)));
    }
  }
});

test("planning : requête globale interdite, requête limitée aux vols visibles autorisée", async () => {
  await seedPrivateRequests();
  for (const uid of ["eleve", "instr", "other", "admin"]) {
    const flights = collection(as(uid), "flights");
    await assertFails(getDocs(query(flights, where("start", ">=", Timestamp.fromMillis(0)))));
    const result = await assertSucceeds(getDocs(query(flights,
      and(or(where("status", "==", "valide"), where("createdBy", "==", uid), where("instructorUid", "==", uid)),
        where("start", ">=", Timestamp.fromMillis(0))), orderBy("start"),
    )));
    const expected = uid === "eleve" || uid === "instr" ? 4 : 1;
    if (result.size !== expected) throw new Error(`Visibilité incorrecte pour ${uid}: ${result.size}`);
    await assertSucceeds(getDocs(query(flights, where("status", "==", "valide"))));
  }
});

test("validation : le vol devient public ; retour en demande : il redevient privé", async () => {
  await seedPrivateRequests();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), "flights/pending"), { status: "valide" });
  });
  await assertSucceeds(getDoc(doc(as("other"), "flights/pending")));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), "flights/pending"), { status: "demande" });
  });
  await assertFails(getDoc(doc(as("other"), "flights/pending")));
});

test("lectures auxiliaires : carnet, carburant, crédit et destinations ne lisent que les vols validés", async () => {
  await seedPrivateRequests();
  const flights = collection(as("other"), "flights");
  const publicFilter = where("status", "==", "valide");
  for (const q of [
    query(flights, publicFilter, where("start", ">=", Timestamp.fromMillis(0)),
      where("start", "<", Timestamp.fromMillis(3000)), orderBy("start")),
    query(flights, publicFilter, where("aircraftId", "==", "a1")),
    query(flights, publicFilter, where("payerUid", "==", "eleve"), where("isClosed", "==", false)),
    query(flights, publicFilter, where("isClosed", "==", false)),
    query(flights, publicFilter, orderBy("start", "desc")),
  ]) {
    const result = await assertSucceeds(getDocs(q));
    if (result.size !== 1 || result.docs[0].id !== "f1") throw new Error("Vols privés dans une lecture auxiliaire");
  }
});

test("changement d'instructeur : l'ancien destinataire perd l'accès", async () => {
  await seedPrivateRequests();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), "flights/pending"), { instructorUid: "other", crew: ["eleve", "other"] });
  });
  await assertFails(getDoc(doc(as("instr"), "flights/pending")));
  await assertSucceeds(getDoc(doc(as("other"), "flights/pending")));
  await assertSucceeds(getDoc(doc(as("eleve"), "flights/pending")));
});

test("caisse : lecture réservée aux instructeurs et aux admins, aucune écriture client", async () => {
  for (const path of ["cashbox/main", "cashMovements/c1"]) {
    await assertFails(getDoc(doc(as("eleve"), path)));
    await assertSucceeds(getDoc(doc(as("instr"), path)));
    await assertSucceeds(getDoc(doc(as("adm"), path)));
  }
  await assertSucceeds(getDocs(collection(as("instr"), "cashMovements")));
  await assertFails(getDocs(collection(as("eleve"), "cashMovements")));
  await assertFails(setDoc(doc(as("adm"), "cashbox/main"), { balance: 1 }));
  await assertFails(setDoc(doc(as("adm"), "cashMovements/new"), { amount: 1 }));
});
