import { test } from "node:test";
import * as assert from "node:assert/strict";
import { supplyAdjustments, supplyCredit } from "./tank";

test("supplyCredit : litres × prix, arrondi", () => {
  assert.equal(supplyCredit(20, 600), 12_000);
  assert.equal(supplyCredit(3, 333.5), 1001);
  assert.equal(supplyCredit(0, 600), 0);
});

test("supplyAdjustments : changement de pilote, même pilote, nul", () => {
  assert.deepEqual(supplyAdjustments({ uid: "a", amount: 12_000 }, { uid: "b", amount: 12_000 }),
    [{ uid: "a", amount: -12_000 }, { uid: "b", amount: 12_000 }]);
  assert.deepEqual(supplyAdjustments({ uid: "a", amount: 12_000 }, { uid: "a", amount: 15_000 }),
    [{ uid: "a", amount: 3_000 }]);
  assert.deepEqual(supplyAdjustments({ uid: "a", amount: 12_000 }, { uid: "a", amount: 12_000 }), []);
  assert.deepEqual(supplyAdjustments({ uid: null, amount: 0 }, { uid: "a", amount: 12_000 }),
    [{ uid: "a", amount: 12_000 }]);
  assert.deepEqual(supplyAdjustments({ uid: "a", amount: 12_000 }, { uid: null, amount: 0 }),
    [{ uid: "a", amount: -12_000 }]);
});
