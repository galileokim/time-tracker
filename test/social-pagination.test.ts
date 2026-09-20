import assert from "node:assert/strict";
import test from "node:test";
import { isOlderThanCursor, paginateFeed, sortFeedDescending } from "../src/social/pagination.js";

const timestamp = new Date("2026-02-08T12:00:00.000Z");

test("compound cursor orders equal timestamps by descending ID without overlap", () => {
  const entries = ["c", "a", "b"].map((id) => ({ id, createdAt: timestamp }));
  const ordered = sortFeedDescending(entries);
  assert.deepEqual(ordered.map(({ id }) => id), ["c", "b", "a"]);

  const first = paginateFeed(entries, 2);
  assert.deepEqual(first.items.map(({ id }) => id), ["c", "b"]);
  assert.equal(first.hasMore, true);

  const second = paginateFeed(entries, 2, first.items[1]);
  assert.deepEqual(second.items.map(({ id }) => id), ["a"]);
  assert.equal(second.hasMore, false);
  assert.equal(isOlderThanCursor(second.items[0], first.items[1]), true);
});

test("generated compound cursors only return older entries across pages", () => {
  for (let seed = 0; seed < 100; seed += 1) {
    const entries = Array.from({ length: 35 }, (_, index) => ({
      id: `id-${String(index).padStart(3, "0")}-${seed}`,
      createdAt: new Date(timestamp.getTime() + ((index * 7 + seed) % 4) * 1000),
    }));
    const ordered = sortFeedDescending(entries);
    const seen = new Set<string>();
    let cursor: (typeof entries)[number] | undefined;
    let pageCount = 0;

    while (true) {
      const page = paginateFeed(entries, 6, cursor);
      for (const item of page.items) {
        assert.ok(!seen.has(item.id));
        seen.add(item.id);
      }
      pageCount += 1;
      if (!page.hasMore || page.items.length === 0) break;
      cursor = page.items.at(-1);
    }

    assert.equal(seen.size, ordered.length);
    assert.ok(pageCount >= 1);
  }
});
