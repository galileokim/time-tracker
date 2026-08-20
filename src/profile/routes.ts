import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import type { Database } from "../db/client.js";
import { createCategorySchema, updateProfileSchema } from "./schemas.js";
import {
  CategoryConflictError,
  ProfileNotFoundError,
  ProfileService,
} from "./service.js";

export interface ProfileRouteOptions {
  db: Database;
}

export const profileRoutes: FastifyPluginAsync<ProfileRouteOptions> = async (app, { db }) => {
  const profiles = new ProfileService(db);

  app.addHook("preHandler", authenticate);

  app.get("/me", async (request, reply) => {
    const userId = authenticatedUserId(request);
    try {
      return { user: await profiles.getProfile(userId) };
    } catch (error) {
      return handleProfileError(error, reply);
    }
  });

  app.patch("/me", async (request, reply) => {
    const input = updateProfileSchema.safeParse(request.body);
    if (!input.success) return invalidRequest(reply, input.error.issues);

    const userId = authenticatedUserId(request);
    try {
      return { user: await profiles.updateProfile(userId, input.data) };
    } catch (error) {
      return handleProfileError(error, reply);
    }
  });

  app.get("/categories", async (request) => {
    return { categories: await profiles.listCategories(authenticatedUserId(request)) };
  });

  app.post("/categories", async (request, reply) => {
    const input = createCategorySchema.safeParse(request.body);
    if (!input.success) return invalidRequest(reply, input.error.issues);

    try {
      const category = await profiles.createCategory(authenticatedUserId(request), input.data);
      return reply.code(201).send({ category });
    } catch (error) {
      if (error instanceof CategoryConflictError) {
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

function handleProfileError(error: unknown, reply: FastifyReply) {
  if (error instanceof ProfileNotFoundError) {
    return reply.code(error.statusCode).send({ error: { code: error.code, message: error.message } });
  }
  throw error;
}
