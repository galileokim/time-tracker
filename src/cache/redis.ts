import { createClient, type RedisClientType } from "redis";
import type { AppConfig } from "../config.js";

export type RedisClient = RedisClientType;

export async function createRedisClient(config: Pick<AppConfig, "REDIS_URL">): Promise<RedisClient> {
  const client = createClient({ url: config.REDIS_URL });
  client.on("error", () => {});
  await client.connect();
  return client;
}
