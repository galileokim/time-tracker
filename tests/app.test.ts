import assert from "node:assert/strict";
import test from "node:test";
import { buildApp } from "../src/app.js";
test("builds a Fastify app without binding a network port", async () => {
  const app = buildApp({ logger: false });

  try {
    const response = await app.inject({ method: "GET", url: "/health" });

    assert.equal(response.statusCode, 200);
    assert.deepEqual(response.json(), { status: "ok" });
  } finally {
    await app.close();
  }
});
