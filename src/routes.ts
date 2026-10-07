import type { FastifyPluginAsync } from "fastify";

const routes: FastifyPluginAsync = async (fastify) => {
  fastify.get("/", async () => ({ hello: "world" }));
};

export default routes;
