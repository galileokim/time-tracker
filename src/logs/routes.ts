import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import type { RedisClient } from "../cache/redis.js";
import { RedisFeedCache } from "../cache/feed-cache.js";
import { FeedDistributor } from "../cache/feed-distributor.js";
import type { Database } from "../db/client.js";
import { createLogSchema } from "./schemas.js";
import { CategoryOwnershipError, LogConflictError, LogService } from "./service.js";

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

    try {
      const receipt = await logs.create(authenticatedUserId(request), input.data);
      return reply.code(receipt.created ? 201 : 200).send(receipt);
    } catch (error) {
      if (error instanceof CategoryOwnershipError || error instanceof LogConflictError) {
        return reply.code(error.statusCode).send({
          error: { code: error.code, message: error.message },
        });
      }
      throw error;
    }
  });
};

async function authenticate(request: FastifyRequest): Promise<void> {
  await request.jwtVerify();
}

function authenticatedUserId(request: FastifyRequest): string {
  return (request.user as { sub: string }).sub;
}

function invalidRequest(reply: FastifyReply, issues: Array<{ path: PropertyKey[]; code: string }>) {
  return reply.code(400).send({
    error: {
      code: "INVALID_REQUEST",
      issues: issues.map(({ path, code }) => ({ path, code })),
    },
  });
}
