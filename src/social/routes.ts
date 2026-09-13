import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import type { Database } from "../db/client.js";
import type { RedisClient } from "../cache/redis.js";
import { feedQuerySchema, followUserSchema } from "./schemas.js";
import { decodeCursor, FollowTargetNotFoundError, SelfFollowError, SocialService } from "./service.js";

export interface SocialRouteOptions {
  db: Database;
  redis?: RedisClient;
}

export const socialRoutes: FastifyPluginAsync<SocialRouteOptions> = async (app, { db, redis }) => {
  const social = new SocialService(db, redis);
  app.addHook("preHandler", authenticate);

  app.post("/follows", async (request, reply) => {
    const input = followUserSchema.safeParse(request.body);
    if (!input.success) return invalidRequest(reply, input.error.issues);

    try {
      await social.follow(authenticatedUserId(request), input.data.userId);
      return reply.code(204).send();
    } catch (error) {
      if (error instanceof SelfFollowError || error instanceof FollowTargetNotFoundError) {
        return reply.code(error.statusCode).send({
          error: { code: error.code, message: error.message },
        });
      }
      throw error;
    }
  });

  app.delete<{ Params: { userId: string } }>("/follows/:userId", async (request, reply) => {
    const target = zUserId(request.params.userId);
    if (!target.success) return invalidRequest(reply, [{ path: ["userId"], code: "invalid_format" }]);
    await social.unfollow(authenticatedUserId(request), target.data);
    return reply.code(204).send();
  });

  app.get("/follows", async (request) => ({
    following: await social.listFollowing(authenticatedUserId(request)),
  }));

  app.get<{ Querystring: { username?: string } }>("/users/search", async (request, reply) => {
    const username = typeof request.query.username === "string" ? request.query.username.trim() : "";
    if (username.length < 3 || username.length > 50) {
      return reply.code(400).send({ error: { code: "INVALID_SEARCH", message: "Enter at least three username characters" } });
    }
    return { users: await social.searchUsers(authenticatedUserId(request), username) };
  });

  app.get("/feed", async (request, reply) => {
    const query = feedQuerySchema.safeParse(request.query);
    if (!query.success) return invalidRequest(reply, query.error.issues);
    if (query.data.cursor) {
      try {
        decodeCursor(query.data.cursor);
      } catch {
        return reply.code(400).send({ error: { code: "INVALID_CURSOR", message: "Invalid feed cursor" } });
      }
    }

    return social.getFeedPage(authenticatedUserId(request), query.data);
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

function zUserId(value: string) {
  const result = z.uuid().safeParse(value);
  return result.success ? result : { success: false as const };
}
