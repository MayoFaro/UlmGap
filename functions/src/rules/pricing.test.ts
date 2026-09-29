import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  adjustments, closingBill, computedCost, DEFAULT_PRICING, toCategory,
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
  });
});

test("toCategory : inconnu → EXT", () => {
  assert.equal(toCategory("XX"), "EXT");
  assert.equal(toCategory("GAP"), "GAP");
  assert.equal(toCategory(undefined), "EXT");
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
