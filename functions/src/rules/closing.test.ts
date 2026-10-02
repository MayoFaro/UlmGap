import { test } from "node:test";
import * as assert from "node:assert/strict";
import { closingEnd } from "./closing";

const M = 60_000;
test("temps de vol plus long que prévu : fin = début + temps de vol", () => {
  assert.equal(closingEnd(0, 60 * M, 90), 90 * M);
});
test("temps de vol plus court : fin inchangée (appareil posé ailleurs)", () => {
  assert.equal(closingEnd(0, 180 * M, 90), 180 * M);
});
test("égalité : fin inchangée", () => {
  assert.equal(closingEnd(0, 90 * M, 90), 90 * M);
});
