import assert from "node:assert/strict";
import test from "node:test";
import { createClient } from "redis";
import { createDatabase } from "../src/db/client.js";
import { loadConfig } from "../src/config.js";
import { RedisFeedCache } from "../src/cache/feed-cache.js";
import { FeedDistributor } from "../src/cache/feed-distributor.js";
import { buildApp } from "../src/app.js";
import { SocialService } from "../src/social/service.js";

const config = loadConfig({
  NODE_ENV: "test",
  DATABASE_URL: "postgres://tracker:tracker@localhost:55432/tracker",
  REDIS_URL: "redis://localhost:6380",
  JWT_SECRET: "a-secret-key-that-is-at-least-32-characters-long",
});

test("Redis feed cache fans out public logs and PostgreSQL repairs misses", async (t) => {
  const database = createDatabase(config);
  const redis = createClient({ url: config.REDIS_URL });
  redis.on("error", () => {});
  await redis.connect();
  const cache = new RedisFeedCache(redis);
  const testUserIDs: string[] = [];
  const testPrefix = `cache_${crypto.randomUUID().slice(0, 8)}`;
  const viewerId = crypto.randomUUID();
  const authorId = crypto.randomUUID();
  testUserIDs.push(viewerId, authorId);

  t.after(async () => {
    if (redis.isOpen) {
      await redis.del(`feed:${viewerId}`);
      await redis.quit();
    }
    if (testUserIDs.length) await database.db.deleteFrom("users").where("id", "in", testUserIDs).execute();
    await database.close();
  });

  await database.db.insertInto("users").values([
    { id: viewerId, username: `${testPrefix}-viewer`, display_name: "Viewer", email: `${testPrefix}-viewer@example.test`, password_hash: "hash" },
    { id: authorId, username: `${testPrefix}-author`, display_name: "Author", email: `${testPrefix}-author@example.test`, password_hash: "hash" },
  ]).execute();
  await database.db.insertInto("follows").values({ follower_id: viewerId, following_id: authorId }).execute();

  const logs = await database.db.insertInto("logs").values([
    {
      user_id: authorId,
      title: "Public cached",
      started_at: new Date("2026-03-01T10:00:00Z"),
      ended_at: new Date("2026-03-01T10:30:00Z"),
      visibility: "public",
      idempotency_key: crypto.randomUUID(),
    },
    {
      user_id: authorId,
      title: "Private not cached",
      started_at: new Date("2026-03-01T11:00:00Z"),
      ended_at: new Date("2026-03-01T11:30:00Z"),
      visibility: "private",
      idempotency_key: crypto.randomUUID(),
    },
  ]).returning(["id", "visibility", "created_at"]).execute();

  const distributor = new FeedDistributor(database.db, cache, 86400);
  await Promise.all(logs.map((log) => distributor.addPublicLog(log.id)));
  const indexed = await cache.getCandidates(viewerId);
  assert.equal(indexed?.length, 1);
  assert.equal(indexed?.[0]?.id, logs.find((log) => log.visibility === "public")?.id);

  const social = new SocialService(database.db, redis);
  const cachedPage = await social.getFeedPage(viewerId, { limit: 10 });
  assert.equal(cachedPage.items.length, 1);
  assert.equal(cachedPage.items[0]?.title, "Public cached");

  await redis.del(`feed:${viewerId}`);
  const recoveredPage = await social.getFeedPage(viewerId, { limit: 10 });
  assert.equal(recoveredPage.items.length, 1, JSON.stringify(recoveredPage));
  assert.equal(recoveredPage.items[0]?.title, "Public cached");
  assert.equal((await cache.getCandidates(viewerId))?.length, 1);

  const noCache = new SocialService(database.db);
  const authoritativePage = await noCache.getFeedPage(viewerId, { limit: 10 });
  assert.deepEqual(authoritativePage.items.map((item) => item.id), recoveredPage.items.map((item) => item.id));

  const cacheError = new Error("Redis unavailable");
  const disconnectedCache = {
    addForFollowers: async () => { throw cacheError; },
    getCandidates: async () => { throw cacheError; },
    removeLogs: async () => { throw cacheError; },
  };
  const disconnectedSocial = new SocialService(database.db, disconnectedCache as never);
  const disconnectedPage = await disconnectedSocial.getFeedPage(viewerId, { limit: 10 });
  assert.deepEqual(disconnectedPage.items.map((item) => item.id), authoritativePage.items.map((item) => item.id));

  const publisher = new FeedDistributor(database.db, disconnectedCache, 86400);
  await assert.rejects(() => publisher.addPublicLog(logs[0]!.id), cacheError);

  const app = buildApp({ config, db: database.db, redis: redis as never, logger: false });
  await app.ready();
  t.after(() => app.close());
  const account = await app.inject({
    method: "POST",
    url: "/api/v1/auth/register",
    payload: {
      username: `${testPrefix}-publisher`,
      displayName: "Publisher",
      email: `${testPrefix}-publisher@example.test`,
      password: "correct horse battery staple",
    },
  });
  assert.equal(account.statusCode, 201);
  const login = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: {
      username: `${testPrefix}-publisher`,
      password: "correct horse battery staple",
    },
  });
  const publicLog = await app.inject({
    method: "POST",
    url: "/api/v1/logs",
    headers: { authorization: `Bearer ${login.json().accessToken}` },
    payload: {
      idempotencyKey: crypto.randomUUID(),
      title: "Cache failure stays non-fatal",
      startedAt: "2026-03-02T10:00:00.000Z",
      endedAt: "2026-03-02T10:10:00.000Z",
      categoryIds: [],
      visibility: "public",
    },
  });
  assert.equal(publicLog.statusCode, 201);
  testUserIDs.push(account.json().user.id);
  await app.close();
});
