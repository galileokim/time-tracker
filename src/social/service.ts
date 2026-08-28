import type { Database } from "../db/client.js";
import type { RedisClient } from "../cache/redis.js";
import { RedisFeedCache } from "../cache/feed-cache.js";
import type { FeedCursor, FeedPage, FeedQuery } from "./schemas.js";
import { getFeedFromDatabase } from "./feed-query.js";

export class FollowTargetNotFoundError extends Error {
  readonly statusCode = 404;
  readonly code = "USER_NOT_FOUND";

  constructor() {
    super("User not found");
    this.name = "FollowTargetNotFoundError";
  }
}

export class SelfFollowError extends Error {
  readonly statusCode = 400;
  readonly code = "SELF_FOLLOW_NOT_ALLOWED";

  constructor() {
    super("An account cannot follow itself");
    this.name = "SelfFollowError";
  }
}

export class SocialService {
  private readonly cache: RedisFeedCache | undefined;

  constructor(private readonly db: Database, redis?: RedisClient) {
    this.cache = redis ? new RedisFeedCache(redis) : undefined;
  }

  async follow(followerId: string, followingId: string): Promise<void> {
    if (followerId === followingId) throw new SelfFollowError();

    const target = await this.db
      .selectFrom("users")
      .select("id")
      .where("id", "=", followingId)
      .executeTakeFirst();
    if (!target) throw new FollowTargetNotFoundError();

    await this.db
      .insertInto("follows")
      .values({ follower_id: followerId, following_id: followingId })
      .onConflict((conflict) => conflict.columns(["follower_id", "following_id"]).doNothing())
      .execute();

    try {
      await this.backfillFollower(followerId, followingId);
    } catch {
      return;
    }
  }

  async unfollow(followerId: string, followingId: string): Promise<void> {
    await this.db
      .deleteFrom("follows")
      .where("follower_id", "=", followerId)
      .where("following_id", "=", followingId)
      .execute();

    try {
      const logs = await this.db
        .selectFrom("logs")
        .select("id")
        .where("user_id", "=", followingId)
        .execute();
      await this.cache?.removeLogs(logs.map((log) => log.id), [followerId]);
    } catch {
      return;
    }
  }

  async listFollowing(userId: string) {
    return this.db
      .selectFrom("follows")
      .innerJoin("users", "users.id", "follows.following_id")
      .select([
        "users.id",
        "users.username",
        "users.display_name",
        "users.avatar_url",
        "follows.created_at as followed_at",
      ])
      .where("follows.follower_id", "=", userId)
      .orderBy("users.username", "asc")
      .execute();
  }

  async getFeedPage(userId: string, query: FeedQuery): Promise<FeedPage> {
    const cursor = query.cursor ? decodeCursor(query.cursor) : undefined;
    const candidates = await this.readCandidates(userId, cursor, query.limit);
    if (candidates) {
      const cachedPage = await getFeedFromDatabase(this.db, userId, query, candidates);
      if (cachedPage.rows.length >= Math.min(query.limit, candidates.length)) {
        return pageFromRows(cachedPage.rows, cachedPage.hasMore || candidates.length > query.limit);
      }
    }

    const authoritativePage = await getFeedFromDatabase(this.db, userId, query);
    if (this.cache) await this.cachePage(userId, authoritativePage.rows);
    return pageFromRows(authoritativePage.rows, authoritativePage.hasMore);
  }

  private async readCandidates(userId: string, cursor: FeedCursor | undefined, limit: number): Promise<string[] | undefined> {
    if (!this.cache) return undefined;

    try {
      const entries = await this.cache.getCandidates(
        userId,
        cursor ? { id: cursor.id, createdAt: new Date(cursor.createdAt) } : undefined,
        limit + 1,
      );
      return entries?.map((entry) => entry.id);
    } catch {
      return undefined;
    }
  }

  private async cachePage(userId: string, rows: Array<{ id: string; createdAt: Date }>): Promise<void> {
    try {
      await this.cache?.addForFollowers(
        [userId],
        rows.map((row) => ({ id: row.id, createdAt: row.createdAt })),
        604800,
      );
    } catch {
      return;
    }
  }

  private async backfillFollower(followerId: string, authorId: string): Promise<void> {
    const logs = await this.db
      .selectFrom("logs")
      .select(["id", "created_at"])
      .where("user_id", "=", authorId)
      .where("visibility", "=", "public")
      .execute();
    await this.cache?.addForFollowers(
      [followerId],
      logs.map((log) => ({ id: log.id, createdAt: toDate(log.created_at) })),
      604800,
    );
  }
}

export function decodeCursor(value: string): FeedCursor {
  try {
    const parsed: unknown = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
    if (
      typeof parsed !== "object" || parsed === null ||
      !("createdAt" in parsed) || typeof parsed.createdAt !== "string" ||
      Number.isNaN(Date.parse(parsed.createdAt)) ||
      !("id" in parsed) || typeof parsed.id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(parsed.id)
    ) {
      throw new Error("invalid cursor");
    }
    return { createdAt: parsed.createdAt, id: parsed.id };
  } catch {
    throw new Error("Invalid feed cursor");
  }
}

function encodeCursor(cursor: FeedCursor): string {
  return Buffer.from(JSON.stringify(cursor)).toString("base64url");
}

function pageFromRows(rows: Awaited<ReturnType<typeof getFeedFromDatabase>>["rows"], hasMore: boolean): FeedPage {
  const last = rows.at(-1);
  return {
    items: rows,
    nextCursor: hasMore && last
      ? encodeCursor({ createdAt: last.createdAt.toISOString(), id: last.id })
      : null,
  };
}

function toDate(value: Date | string | object): Date {
  return value instanceof Date ? value : new Date(String(value));
}
