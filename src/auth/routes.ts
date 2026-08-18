import jwtPlugin from "@fastify/jwt";
import type { FastifyPluginAsync, FastifyRequest } from "fastify";
import type { Database } from "../db/client.js";
import type { AppConfig } from "../config.js";
import { loginSchema, registerSchema } from "./schemas.js";
import { AccountConflictError, AuthService, AuthenticationError } from "./service.js";

export interface AuthRouteOptions {
  db: Database;
  config: Pick<AppConfig, "JWT_SECRET" | "JWT_EXPIRES_IN">;
}

export const authRoutes: FastifyPluginAsync<AuthRouteOptions> = async (app, options) => {
  await app.register(jwtPlugin, {
    secret: options.config.JWT_SECRET,
    sign: { expiresIn: options.config.JWT_EXPIRES_IN },
  });

  const auth = new AuthService(
    options.db,
    {
      sign: (payload, signOptions) => app.jwt.sign(payload, signOptions),
    },
    options.config.JWT_EXPIRES_IN,
  );

  app.post("/register", async (request, reply) => {
    const input = registerSchema.safeParse(request.body);
    if (!input.success) {
      return reply.code(400).send({
        error: {
          code: "INVALID_REQUEST",
          issues: input.error.issues.map(({ path, code }) => ({ path, code })),
        },
      });
    }

    try {
      const user = await auth.register(input.data);
      return reply.code(201).send({ user });
    } catch (error) {
      if (error instanceof AccountConflictError) {
        return reply.code(error.statusCode).send({ error: { code: error.code, message: error.message } });
      }
      throw error;
    }
  });

  app.post("/login", async (request, reply) => {
    const input = loginSchema.safeParse(request.body);
    if (!input.success) {
      return reply.code(400).send({
        error: {
          code: "INVALID_REQUEST",
          issues: input.error.issues.map(({ path, code }) => ({ path, code })),
        },
      });
    }

    try {
      return await auth.login(input.data);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return reply.code(error.statusCode).send({ error: { code: error.code, message: error.message } });
      }
      throw error;
    }
  });

  app.get("/me", { preHandler: authenticate }, async (request) => {
    const user = request.user as { sub: string; username: string };
    return { user: { id: user.sub, username: user.username } };
  });
};

async function authenticate(request: FastifyRequest): Promise<void> {
  await request.jwtVerify();
}
