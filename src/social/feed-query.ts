import type { Database } from "../db/client.js";
import type { FeedEntry, FeedQuery } from "./schemas.js";
import { decodeCursor } from "./service.js";
import { cursorPredicateValues } from "./pagination.js";

export async function getFeedFromDatabase(
  db: Database,
  userId: string,
  query: FeedQuery,
  candidateIDs?: string[],
): Promise<{ rows: FeedEntry[]; hasMore: boolean }> {
  const cursor = query.cursor ? decodeCursor(query.cursor) : undefined;
  let feedQuery = db
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
        expression("viewer_follow.follower_id", "=", userId),
      ]),
      expression.and([
        expression("logs.visibility", "=", "friends_only"),
        expression("author_follow.following_id", "=", userId),
      ]),
    ]));

  if (candidateIDs) {
    feedQuery = feedQuery.where("logs.id", "in", candidateIDs.length > 0 ? candidateIDs : ["00000000-0000-0000-0000-000000000000"]);
  }

  if (cursor) {
    const cursorValues = cursorPredicateValues({ createdAt: new Date(cursor.createdAt), id: cursor.id });
    feedQuery = feedQuery.where((expression) => expression.or([
      expression("logs.created_at", "<", cursorValues.createdAt as never),
      expression.and([
        expression("logs.created_at", "=", cursorValues.createdAt as never),
        expression("logs.id", "<", cursorValues.id),
      ]),
    ]));
  }

  const rows = await feedQuery
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
  const logIDs = pageRows.map((row) => row.id);
  const categoryRows = logIDs.length === 0
    ? []
    : await db
        .selectFrom("log_categories")
        .innerJoin("categories", "categories.id", "log_categories.category_id")
        .select([
          "log_categories.log_id",
          "categories.id",
          "categories.name",
          "categories.color_hex",
        ])
        .where("log_categories.log_id", "in", logIDs)
        .execute();

  const categoriesByLog = new Map<string, FeedEntry["categories"]>();
  for (const category of categoryRows) {
    const existing = categoriesByLog.get(category.log_id) ?? [];
    existing.push({ id: category.id, name: category.name, colorHex: category.color_hex });
    categoriesByLog.set(category.log_id, existing);
  }

  return {
    rows: pageRows.map((row) => ({
      id: row.id,
      title: row.title,
      notes: row.notes,
      startedAt: normalizeDate(row.started_at),
      endedAt: normalizeDate(row.ended_at),
      durationSeconds: row.duration_seconds,
      visibility: row.visibility,
      createdAt: normalizeDate(row.created_at),
      author: {
        id: row.user_id,
        username: row.author_username,
        displayName: row.author_display_name,
        avatarUrl: row.author_avatar_url,
      },
      categories: categoriesByLog.get(row.id) ?? [],
    })),
    hasMore,
  };
}

function normalizeDate(value: Date | string | object): Date {
  return value instanceof Date ? value : new Date(String(value));
}
