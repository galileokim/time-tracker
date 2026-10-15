import type { FastifyPluginAsync } from "fastify";
import type { RedisClient } from "../cache/redis.js";
import { RedisFeedCache } from "../cache/feed-cache.js";
import { FeedDistributor } from "../cache/feed-distributor.js";
import type { Database } from "../db/client.js";
import { authenticate, authenticatedUserId, invalidRequest } from "../http.js";
import { createLogSchema } from "./schemas.js";
import { LogService } from "./service.js";

export interface LogRouteOptions {
  db: Database;
  redis?: RedisClient;
  feedCacheMaxAgeSeconds?: number;
}

export const logRoutes: FastifyPluginAsync<LogRouteOptions> = async (app, { db, redis, feedCacheMaxAgeSeconds = 604800 }) => {
  const publisher = redis
    ? new FeedDistributor(db, new RedisFeedCache(redis), feedCacheMaxAgeSeconds)
    : undefined;
  const logs = new LogService(db, publisher);

  app.addHook("preHandler", authenticate);

  app.post("/logs", async (request, reply) => {
    const input = createLogSchema.safeParse(request.body);
    if (!input.success) return invalidRequest(reply, input.error.issues);

    const receipt = await logs.create(authenticatedUserId(request), input.data);
    return reply.code(receipt.created ? 201 : 200).send(receipt);
  });
};
