import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const migration = require("../migrations/001_create_tracker_schema.cjs") as {
  up: (builder: unknown) => void;
  down: (builder: unknown) => void;
};

test("schema migration creates all tracker tables and integrity constraints", () => {
  const statements: string[] = [];
  const builder = new Proxy({}, {
    get: (_target, operation: string) => (...args: unknown[]) => {
      statements.push(`${operation} ${JSON.stringify(args)}`);
    },
  });

  migration.up(builder);
  const sql = statements.join("\n");

  for (const table of ["users", "categories", "logs", "log_categories", "follows"]) {
    assert.ok(sql.includes(`createTable [\"${table}\"`), `creates ${table}`);
  }

  assert.match(sql, /lower\(username\)/);
  assert.match(sql, /lower\(email\)/);
  assert.match(sql, /duration_seconds/);
  assert.match(sql, /ended_at >= started_at/);
  assert.match(sql, /"onDelete":"CASCADE"/);
  assert.match(sql, /follower_id <> following_id/);
});

test("schema rollback drops tables in foreign-key-safe order", () => {
  const dropped: string[] = [];
  const builder = new Proxy({}, {
    get: (_target, operation: string) => (table: string) => {
      if (operation === "dropTable") dropped.push(table);
    },
  });

  migration.down(builder);

  assert.deepEqual(dropped, ["follows", "log_categories", "logs", "categories", "users"]);
});
