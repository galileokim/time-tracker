import type { RedisClient } from "./redis.js";

export interface FeedCandidate {
  id: string;
  createdAt: Date;
}

export interface FeedCache {
  addForFollowers(followerIDs: string[], logs: FeedCandidate[], retentionSeconds: number): Promise<void>;
  getCandidates(userId: string, before?: FeedCandidate, limit?: number): Promise<FeedCandidate[] | null>;
  removeLogs(logIDs: string[], followerIDs: string[]): Promise<void>;
}

export class RedisFeedCache implements FeedCache {
  constructor(private readonly client: RedisClient) {}

  async addForFollowers(
    followerIDs: string[],
    logs: FeedCandidate[],
    retentionSeconds: number,
  ): Promise<void> {
    if (followerIDs.length === 0 || logs.length === 0) return;

    await Promise.all(followerIDs.map(async (followerId) => {
      const key = feedKey(followerId);
      const commands = this.client.multi();
      for (const log of logs) {
        commands.zAdd(key, { score: log.createdAt.getTime(), value: log.id });
      }
      const newest = Math.max(...logs.map((log) => log.createdAt.getTime()));
      commands.zRemRangeByScore(key, "-inf", newest - retentionSeconds * 1000);
      await commands.exec();
    }));
  }

  async getCandidates(
    userId: string,
    before?: FeedCandidate,
    limit = 100,
  ): Promise<FeedCandidate[] | null> {
    const key = feedKey(userId);
    const exists = await this.client.exists(key);
    if (!exists) return null;

    const entries = await this.client.zRangeWithScores(key, 0, -1, {
      REV: true,
    });
    const candidates = entries
      .map(({ value, score }) => ({ id: value, createdAt: new Date(score) }))
      .filter((candidate) => !before || isBefore(candidate, before));

    return candidates.slice(0, limit);
  }

  async removeLogs(logIDs: string[], followerIDs: string[]): Promise<void> {
    if (logIDs.length === 0 || followerIDs.length === 0) return;
    await Promise.all(followerIDs.map((followerId) =>
      this.client.zRem(feedKey(followerId), logIDs),
    ));
  }
}

function isBefore(candidate: FeedCandidate, cursor: FeedCandidate): boolean {
  return candidate.createdAt.getTime() < cursor.createdAt.getTime() ||
    (candidate.createdAt.getTime() === cursor.createdAt.getTime() && candidate.id < cursor.id);
}

export function feedKey(userId: string): string {
  return `feed:${userId}`;
}
