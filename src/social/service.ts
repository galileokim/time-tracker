import { sql } from "kysely";
import type { Database } from "../db/client.js";
import type { FeedCursor, FeedEntry, FeedPage, FeedQuery } from "./schemas.js";

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
  constructor(private readonly db: Database) {}

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
  }

  async unfollow(followerId: string, followingId: string): Promise<void> {
    await this.db
      .deleteFrom("follows")
      .where("follower_id", "=", followerId)
      .where("following_id", "=", followingId)
      .execute();
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
    const baseQuery = this.db
      .selectFrom("logs")
      .innerJoin("users as author", "author.id", "logs.user_id")
      .leftJoin("follows as viewer_follow", (join) =>
        join.onRef("viewer_follow.following_id", "=", "logs.user_id")
          .on("viewer_follow.follower_id", "=", userId),
      )
      .leftJoin("follows as author_follow", (join) =>
        join.onRef("author_follow.follower_id", "=", "logs.user_id")
          .on("author_follow.following_id", "=", userId),
      )
      .where((expression) => expression.or([
        expression("logs.user_id", "=", userId),
        expression.and([
          expression("logs.visibility", "=", "public"),
          expression.or([
            expression("logs.user_id", "=", userId),
            expression("viewer_follow.follower_id", "is not", null),
          ]),
        ]),
        expression.and([
          expression("logs.visibility", "=", "friends_only"),
          expression("author_follow.following_id", "is not", null),
        ]),
      ]));

    const pagedQuery = cursor
      ? baseQuery.where((expression) => expression.or([
          expression("logs.created_at", "<", cursor.createdAt as never),
          expression.and([
            expression("logs.created_at", "=", cursor.createdAt as never),
            expression("logs.id", "<", cursor.id),
          ]),
        ]))
      : baseQuery;

    const rows = await pagedQuery
      .select([
        "logs.id",
        "logs.user_id",
        "logs.title",
        "logs.notes",
        "logs.started_at",
        "logs.ended_at",
        "logs.duration_seconds",
        "logs.visibility",
        "logs.created_at",
        "author.username as author_username",
        "author.display_name as author_display_name",
        "author.avatar_url as author_avatar_url",
      ])
      .orderBy("logs.created_at", "desc")
      .orderBy("logs.id", "desc")
      .limit(query.limit + 1)
      .execute();

    const hasMore = rows.length > query.limit;
    const pageRows = rows.slice(0, query.limit);
    const logIds = pageRows.map((row) => row.id);
    const categories = logIds.length === 0
      ? []
      : await this.db
          .selectFrom("log_categories")
          .innerJoin("categories", "categories.id", "log_categories.category_id")
          .select([
            "log_categories.log_id",
            "categories.id",
            "categories.name",
            "categories.color_hex",
          ])
          .where("log_categories.log_id", "in", logIds)
          .execute();

    const categoriesByLog = new Map<string, FeedEntry["categories"]>();
    for (const category of categories) {
      const existing = categoriesByLog.get(category.log_id) ?? [];
      existing.push({ id: category.id, name: category.name, colorHex: category.color_hex });
      categoriesByLog.set(category.log_id, existing);
    }

    const items = pageRows.map((row): FeedEntry => ({
      id: row.id,
      title: row.title,
      notes: row.notes,
      startedAt: toDate(row.started_at),
      endedAt: toDate(row.ended_at),
      durationSeconds: row.duration_seconds,
      visibility: row.visibility,
      createdAt: toDate(row.created_at),
      author: {
        id: row.user_id,
        username: row.author_username,
        displayName: row.author_display_name,
        avatarUrl: row.author_avatar_url,
      },
      categories: categoriesByLog.get(row.id) ?? [],
    }));

    const lastItem = pageRows.at(-1);
    return {
      items,
      nextCursor: hasMore && lastItem
        ? encodeCursor({ createdAt: toDate(lastItem.created_at).toISOString(), id: lastItem.id })
        : null,
    };
  }
}

export function isVisibleToViewer(
  visibility: "public" | "private" | "friends_only",
  ownerId: string,
  viewerId: string,
  viewerFollowsOwner: boolean,
  ownerFollowsViewer: boolean,
): boolean {
  if (ownerId === viewerId) return true;
  if (visibility === "public") return viewerFollowsOwner;
  if (visibility === "friends_only") return ownerFollowsViewer;
  return false;
}

export function encodeCursor(cursor: FeedCursor): string {
  return Buffer.from(JSON.stringify(cursor)).toString("base64url");
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

function toDate(value: Date | string | object): Date {
  return value instanceof Date ? value : new Date(String(value));
}
