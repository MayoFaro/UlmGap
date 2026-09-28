import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  checkPayer, conflictCause, decideStatus, designatedInstructor, findConflict, payerOf,
  resolvePricingMode,
} from "./flights";

const fx = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, "../../../test/fixtures/flight_rules.json"), "utf8"));

for (const c of fx.matrix) {
  test(`matrice : ${c.name}`, () => {
    const d = decideStatus(c.creator, c.crew, c.passengers);
    if (c.expected === "refus") {
      assert.equal(d.ok, false);
      assert.ok(!d.ok && d.reason.length > 0);
    } else {
      assert.deepEqual(d, { ok: true, status: c.expected, instructorUid: c.instructorUid });
    }
  });
}

for (const c of fx.pricing) {
  test(`mode : ${c.name}`, () => {
    assert.equal(resolvePricingMode(c), c.expected);
  });
}

for (const c of fx.conflicts) {
  test(`conflit : ${c.name}`, () => {
    assert.equal(findConflict(c.candidate, c.others)?.id ?? null, c.expected);
  });
}

test("payeur : premier inscrit (DPS/LDX → DPS, LDX/DPS → LDX)", () => {
  assert.equal(payerOf(["DPS", "LDX"]), "DPS");
  assert.equal(payerOf(["LDX", "DPS"]), "LDX");
});

test("instructeur désigné : jamais le créateur lui-même", () => {
  assert.equal(designatedInstructor("i", [{ uid: "i", profile: "instructeur" }]), null);
  assert.equal(designatedInstructor("c", [
    { uid: "c", profile: "eleve" }, { uid: "i", profile: "instructeur" },
  ]), "i");
});

for (const c of fx.payer) {
  test(`compte débité : ${c.name}`, () => {
    const r = checkPayer(c.creator, c.crew);
    if (c.ok) assert.equal(r, null);
    else assert.equal(r, "Le compte débité doit être le vôtre : placez-vous en premier.");
  });
}

for (const c of fx.conflicts.filter((x: { expectedCause?: unknown }) => x.expectedCause)) {
  test(`cause du conflit : ${c.name}`, () => {
    const other = findConflict(c.candidate, c.others)!;
    assert.deepEqual(conflictCause(c.candidate, other), c.expectedCause);
  });
}

test("message élève au vouvoiement", () => {
  const d = decideStatus({ uid: "c", profile: "eleve", isAdmin: false },
    [{ uid: "c", profile: "eleve" }], 0);
  assert.deepEqual(d, { ok: false,
    reason: "Impossible de créer un vol à votre profit sans la présence d'un instructeur." });
});
