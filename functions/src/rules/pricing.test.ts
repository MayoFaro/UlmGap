import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  adjustments, closingBill, computedCost, DEFAULT_PRICING, formatFcfa, instructionAdjustments,
  instructionCreditDue, Pricing, pricingWithDefaults, toCategory,
} from "./pricing";

const fx = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, "../../../test/fixtures/pricing_cases.json"), "utf8"));

test("DEFAULT_PRICING reproduit la spec §2.4", () => {
  assert.deepEqual(DEFAULT_PRICING, {
    flatFee: { GAP: 12_000, GR: 30_000, MIL: 50_000, EXT: 70_000 },
    includedMinutes: 75,
    minPlannedMinutes: 45,
    overtimeHourly: { GAP: 12_000, GR: 30_000, MIL: 30_000, EXT: 30_000 },
    fuelHourlyRate: 12_000,
    instructionCredit: 20_000,
    baptismFee: 70_000,
  });
});

test("toCategory : inconnu → EXT", () => {
  assert.equal(toCategory("XX"), "EXT");
  assert.equal(toCategory("GAP"), "GAP");
  assert.equal(toCategory(undefined), "EXT");
});

test("formatFcfa : groupes de 3 chiffres, espace insécable, signe négatif", () => {
  assert.equal(formatFcfa(0), "0 FCFA");
  assert.equal(formatFcfa(70_000), "70 000 FCFA");
  assert.equal(formatFcfa(12_000), "12 000 FCFA");
  assert.equal(formatFcfa(1_234_567), "1 234 567 FCFA");
  assert.equal(formatFcfa(-500), "−500 FCFA");
});

for (const c of fx.cost) {
  test(`coût : ${c.name}`, () => {
    assert.equal(computedCost(c.mode, c.minutes, c.category, DEFAULT_PRICING), c.expected);
  });
}

for (const c of fx.closing) {
  test(`clôture : ${c.name}`, () => {
    const args = {
      mode: c.mode, actualMinutes: c.actualMinutes, category: c.category, pricing: DEFAULT_PRICING,
      shortFlightAmount: c.shortFlightAmount ?? null, customAmount: c.customAmount ?? null,
      hasPassenger: c.hasPassenger,
    };
    if (c.expectedError) {
      assert.throws(() => closingBill(args), new Error(c.expectedError));
    } else {
      assert.deepEqual(closingBill(args), c.expected);
    }
  });
}

for (const c of fx.adjustments) {
  test(`régularisation : ${c.name}`, () => {
    assert.deepEqual(adjustments(c.before, c.after), c.expected);
  });
}

test("closingBill baptism : baptismFee hors app, quelle que soit la durée", () => {
  const p = { ...DEFAULT_PRICING, baptismFee: 70_000 };
  for (const actualMinutes of [20, 60, 200]) {
    assert.deepEqual(
      closingBill({ mode: "baptism", actualMinutes, category: "EXT", pricing: p, hasPassenger: true,
        shortFlightAmount: 5_000, customAmount: 9_000 }),
      { billedAmount: 70_000, billedTo: "off_app", pricingMode: "baptism" });
  }
});

test("pricingWithDefaults : snapshot ancien sans les nouveaux champs", () => {
  const old = { ...DEFAULT_PRICING } as Partial<Pricing>;
  delete old.instructionCredit;
  delete old.baptismFee;
  const p = pricingWithDefaults(old);
  assert.equal(p.instructionCredit, 20_000);
  assert.equal(p.baptismFee, 70_000);
  assert.deepEqual(pricingWithDefaults(null), DEFAULT_PRICING);
  assert.equal(pricingWithDefaults({ ...DEFAULT_PRICING, instructionCredit: 15_000 }).instructionCredit, 15_000);
});

const ins = { uid: "i", profile: "instructeur" as const };
const stu = { uid: "s", profile: "eleve" as const };

test("instructionCreditDue : seuil 45 min, instructeur crédité", () => {
  const p = DEFAULT_PRICING;
  assert.deepEqual(instructionCreditDue({ instruction: true, actualMinutes: 45, crew: [stu, ins], pricing: p }),
    { uid: "i", amount: 20_000 });
  assert.equal(instructionCreditDue({ instruction: true, actualMinutes: 44, crew: [stu, ins], pricing: p }), null);
  assert.equal(instructionCreditDue({ instruction: false, actualMinutes: 90, crew: [stu, ins], pricing: p }), null);
  assert.equal(instructionCreditDue({ instruction: true, actualMinutes: 90, crew: [ins], pricing: p }), null);
  assert.equal(instructionCreditDue({ instruction: true, actualMinutes: 90,
    crew: [ins, { uid: "j", profile: "instructeur" }], pricing: p }), null);
});

test("instructionAdjustments : retrait, ajout, changement d'instructeur, inchangé", () => {
  assert.deepEqual(instructionAdjustments({ uid: null, amount: 0 }, { uid: "i", amount: 20_000 }),
    [{ uid: "i", amount: 20_000 }]);
  assert.deepEqual(instructionAdjustments({ uid: "i", amount: 20_000 }, { uid: null, amount: 0 }),
    [{ uid: "i", amount: -20_000 }]);
  assert.deepEqual(instructionAdjustments({ uid: "i", amount: 20_000 }, { uid: "j", amount: 20_000 }),
    [{ uid: "i", amount: -20_000 }, { uid: "j", amount: 20_000 }]);
  assert.deepEqual(instructionAdjustments({ uid: "i", amount: 20_000 }, { uid: "i", amount: 20_000 }), []);
});
