import Fastify, { type FastifyInstance } from "fastify";
import type { AppConfig } from "./config.js";
import { createDatabase, type Database } from "./db/client.js";
import { authRoutes } from "./auth/routes.js";
import { profileRoutes } from "./profile/routes.js";
import jwtPlugin from "@fastify/jwt";
import { logRoutes } from "./logs/routes.js";
import { socialRoutes } from "./social/routes.js";
import { createRedisClient, type RedisClient } from "./cache/redis.js";

export interface AppDependencies {
  logger?: boolean;
  config?: AppConfig;
  db?: Database;
  redis?: RedisClient;
}

export function buildApp({ logger = true, config, db, redis }: AppDependencies = {}): FastifyInstance {
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
        redis,
        feedCacheMaxAgeSeconds: config.FEED_CACHE_MAX_AGE_SECONDS,
      });
      await authenticatedApi.register(socialRoutes, {
        db,
        redis,
      });
    }, { prefix: "/api/v1" });
  }

  return app;
}

export async function buildConfiguredApp(config: AppConfig): Promise<FastifyInstance> {
  const database = createDatabase(config);
  const redis = await createRedisClient(config);
  const app = buildApp({ config, db: database.db, redis });

  app.addHook("onClose", async () => {
    await Promise.all([database.close(), redis.quit()]);
  });

  return app;
}
