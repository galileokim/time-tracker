import Fastify, { type FastifyInstance } from "fastify";
import type { AppConfig } from "./config.js";
import { createDatabase, type Database } from "./db/client.js";
import { authRoutes } from "./auth/routes.js";
import { profileRoutes } from "./profile/routes.js";
import jwtPlugin from "@fastify/jwt";
import { logRoutes } from "./logs/routes.js";
import { socialRoutes } from "./social/routes.js";

export interface AppDependencies {
  logger?: boolean;
  config?: AppConfig;
  db?: Database;
}

export function buildApp({ logger = true, config, db }: AppDependencies = {}): FastifyInstance {
  const app = Fastify({ logger });

  app.get("/health", async () => ({ status: "ok" }));

  if (config && db) {
    app.register(jwtPlugin, {
      secret: config.JWT_SECRET,
      sign: { expiresIn: config.JWT_EXPIRES_IN },
    });
    app.register(async (authenticatedApi) => {
      await authenticatedApi.register(authRoutes, {
        prefix: "/auth",
        config,
        db,
      });
      await authenticatedApi.register(profileRoutes, {
        db,
      });
      await authenticatedApi.register(logRoutes, {
        db,
      });
      await authenticatedApi.register(socialRoutes, {
        db,
      });
    }, { prefix: "/api/v1" });
  }

  return app;
}

export function buildConfiguredApp(config: AppConfig): FastifyInstance {
  const database = createDatabase(config);
  const app = buildApp({ config, db: database.db });

  app.addHook("onClose", async () => {
    await database.close();
  });

  return app;
}
