import type { Database } from "../db/client.js";
import type { FeedCache } from "./feed-cache.js";

export class FeedDistributor {
  constructor(
    private readonly db: Database,
    private readonly cache: FeedCache,
    private readonly retentionSeconds: number,
  ) {}

  async addPublicLog(logId: string): Promise<void> {
    const log = await this.db
      .selectFrom("logs")
      .select(["id", "user_id", "visibility", "created_at"])
      .where("id", "=", logId)
      .executeTakeFirst();

    if (!log || log.visibility !== "public") return;

    const followers = await this.db
      .selectFrom("follows")
      .select("follower_id")
      .where("following_id", "=", log.user_id)
      .execute();

    await this.cache.addForFollowers(
      followers.map((row) => row.follower_id),
      [{ id: log.id, createdAt: normalizeDate(log.created_at) }],
      this.retentionSeconds,
    );
  }
}

function normalizeDate(value: Date | string | object): Date {
  return value instanceof Date ? value : new Date(String(value));
}
