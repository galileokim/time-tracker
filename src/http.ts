import type { FastifyReply, FastifyRequest } from "fastify";

export async function authenticate(request: FastifyRequest): Promise<void> {
  await request.jwtVerify();
}

export function authenticatedUserId(request: FastifyRequest): string {
  return (request.user as { sub: string }).sub;
}

export function invalidRequest(reply: FastifyReply, issues: Array<{ path: PropertyKey[]; code: string; message?: string }>) {
  return reply.code(400).send({
    error: {
      code: "INVALID_REQUEST",
      issues: issues.map(({ path, code, message }) => ({ path, code, message })),
    },
  });
}
