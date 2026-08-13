import Fastify, { type FastifyInstance } from "fastify";

export interface AppDependencies {
  logger?: boolean;
}

export function buildApp({ logger = true }: AppDependencies = {}): FastifyInstance {
  const app = Fastify({ logger });

  app.get("/health", async () => ({ status: "ok" }));

  return app;
}
