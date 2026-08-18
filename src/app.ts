import Fastify, { type FastifyInstance } from "fastify";
import type { AppConfig } from "./config.js";
import { createDatabase, type Database } from "./db/client.js";
import { authRoutes } from "./auth/routes.js";

export interface AppDependencies {
  logger?: boolean;
  config?: AppConfig;
  db?: Database;
}

export function buildApp({ logger = true, config, db }: AppDependencies = {}): FastifyInstance {
  const app = Fastify({ logger });

  app.get("/health", async () => ({ status: "ok" }));

  if (config && db) {
    app.register(authRoutes, {
      prefix: "/api/v1/auth",
      config,
      db,
    });
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
