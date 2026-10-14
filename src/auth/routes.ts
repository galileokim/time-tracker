import type { FastifyPluginAsync } from "fastify";
import type { Database } from "../db/client.js";
import type { AppConfig } from "../config.js";
import { invalidRequest } from "../http.js";
import { loginSchema, registerSchema } from "./schemas.js";
import { AuthService } from "./service.js";

export interface AuthRouteOptions {
  db: Database;
  config: Pick<AppConfig, "JWT_SECRET" | "JWT_EXPIRES_IN">;
}

export const authRoutes: FastifyPluginAsync<AuthRouteOptions> = async (app, options) => {
  const auth = new AuthService(
    options.db,
    { sign: (payload, signOptions) => app.jwt.sign(payload, signOptions) },
    options.config.JWT_EXPIRES_IN,
  );

  app.post("/register", async (request, reply) => {
    const input = registerSchema.safeParse(request.body);
    if (!input.success) return invalidRequest(reply, input.error.issues);

    const user = await auth.register(input.data);
    return reply.code(201).send({ user });
  });

  app.post("/login", async (request, reply) => {
    const input = loginSchema.safeParse(request.body);
    if (!input.success) return invalidRequest(reply, input.error.issues);

    return auth.login(input.data);
  });
};
