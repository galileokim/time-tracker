import assert from "node:assert/strict";
import test from "node:test";
import { durationSeconds } from "../src/logs/duration.js";
import { createLogSchema } from "../src/logs/schemas.js";

function payload(startedAt: Date, endedAt: Date, overrides: Record<string, unknown> = {}) {
  return {
    idempotencyKey: crypto.randomUUID(),
    title: "Generated activity",
    startedAt: startedAt.toISOString(),
    endedAt: endedAt.toISOString(),
    categoryIds: [],
    visibility: "private",
    ...overrides,
  };
}

test("generated valid log ranges preserve nonnegative whole-second durations", () => {
  for (let seed = 0; seed < 150; seed += 1) {
    const startMilliseconds = 1_700_000_000_000 + seed * 86_400_000;
    const expectedSeconds = (seed * 7919) % 86_401;
    const fractionalMilliseconds = seed % 1000;
    const startedAt = new Date(startMilliseconds);
    const endedAt = new Date(startMilliseconds + expectedSeconds * 1000 + fractionalMilliseconds);
    const parsed = createLogSchema.safeParse(payload(startedAt, endedAt));

    assert.equal(parsed.success, true, `seed ${seed}`);
    if (parsed.success) {
      const derivedDuration = durationSeconds(parsed.data.startedAt, parsed.data.endedAt);
      assert.equal(derivedDuration, expectedSeconds);
      assert.ok(derivedDuration >= 0);
    }
  }
});

test("generated invalid fields and reversed time ranges fail schema validation", () => {
  for (let seed = 0; seed < 150; seed += 1) {
    const startMilliseconds = 1_700_000_000_000 + seed * 1000;
    const startedAt = new Date(startMilliseconds);
    const earlierEnd = new Date(startMilliseconds - ((seed % 60) + 1) * 1000);
    const reversed = createLogSchema.safeParse(payload(startedAt, earlierEnd));
    assert.equal(reversed.success, false, `reversed range seed ${seed}`);

    const invalidVisibility = createLogSchema.safeParse(payload(startedAt, startedAt, { visibility: `invalid-${seed}` }));
    assert.equal(invalidVisibility.success, false, `visibility seed ${seed}`);

    const oversizedTitle = createLogSchema.safeParse(payload(startedAt, startedAt, { title: "x".repeat(101) }));
    assert.equal(oversizedTitle.success, false, `title seed ${seed}`);
  }
});
