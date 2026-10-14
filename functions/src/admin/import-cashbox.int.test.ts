// Lancé par `npm run test:int` (émulateur Firestore).
import { afterEach, beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import { db, resetCashbox } from "../flights/testkit";
import { importCashbox } from "./import-cashbox";

beforeEach(resetCashbox);
afterEach(resetCashbox);

test("import : lignes triées par date, solde recalculé, reprise en cours", async () => {
  const r = await importCashbox(db, [
    { date: "2026-10-12", kind: "fuel_purchase", amount: -220_000, note: "ESSENCE" },
    { date: "2025-03-05", kind: "opening", amount: 10_000_000, note: "Fond initial" },
    { date: "2025-03-05", kind: "maintenance", amount: -500_000, note: "RESERVOIR" },
  ]);
  assert.deepEqual(r, { count: 3, balance: 9_280_000 });
  const box = (await db.collection("cashbox").doc("main").get()).data()!;
  assert.equal(box.balance, 9_280_000);
  assert.equal(box.migrationClosedAt, null);
  const lines = (await db.collection("cashMovements").orderBy("at").get()).docs.map((d) => d.data());
  assert.deepEqual(lines.map((l) => l.note), ["Fond initial", "RESERVOIR", "ESSENCE"]);
  assert.deepEqual(lines.map((l) => l.balanceAfter), [10_000_000, 9_500_000, 9_280_000]);
  for (const l of lines) {
    assert.equal(l.imported, true);
    assert.equal(l.by, "import");
    assert.equal(l.userUid, null);
    assert.equal(l.correctsId, null);
  }
});

test("import refusé si la caisse contient déjà une opération", async () => {
  await db.collection("cashMovements").doc().set({ kind: "fuel_purchase", amount: -1 });
  await assert.rejects(importCashbox(db, [{ date: "2025-03-05", kind: "opening", amount: 1, note: "x" }]),
    { message: "La caisse contient déjà des opérations : import refusé." });
});
