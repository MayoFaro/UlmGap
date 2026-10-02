import { test } from "node:test";
import * as assert from "node:assert/strict";
import { becomesFuelSource } from "./fuel";

test("becomesFuelSource : appareil sans valeur, vol plus récent ou simultané", () => {
  assert.equal(becomesFuelSource(1_000, null), true);
  assert.equal(becomesFuelSource(2_000, 1_000), true);
  assert.equal(becomesFuelSource(1_000, 1_000), true);
});

test("becomesFuelSource : vol plus ancien que la source (clôture tardive)", () => {
  assert.equal(becomesFuelSource(1_000, 2_000), false);
});
