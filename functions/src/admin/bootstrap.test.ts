import { test } from "node:test";
import * as assert from "node:assert/strict";
import { bootstrapAdmin } from "./bootstrap";

test("M8 : une erreur Auth autre que « compte inexistant » est remontée", async () => {
  const created: string[] = [];
  const auth = {
    getUserByEmail: async () => {
      throw Object.assign(new Error("no config"), { code: "auth/configuration-not-found" });
    },
    createUser: async (p: { email?: string }) => {
      created.push(p.email ?? "");
      return { uid: "x" };
    },
  };
  await assert.rejects(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    bootstrapAdmin(auth as any, {} as any, { email: "a@b.fr", name: "A", short: "AAA" }),
    (e) => (e as { code?: string }).code === "auth/configuration-not-found");
  assert.deepEqual(created, []);
});
