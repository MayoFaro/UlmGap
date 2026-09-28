import { test } from "node:test";
import * as assert from "node:assert/strict";
import { assertSeedAllowed } from "./seed";

test("assertSeedAllowed : rejette un projet qui n'est ni ulmgap-dev ni demo-*", () => {
  assert.throws(() => assertSeedAllowed("ulmgap-prod"));
});

test("assertSeedAllowed : accepte ulmgap-dev", () => {
  assert.doesNotThrow(() => assertSeedAllowed("ulmgap-dev"));
});

test("assertSeedAllowed : accepte un projet demo-*", () => {
  assert.doesNotThrow(() => assertSeedAllowed("demo-ulmgap"));
});
