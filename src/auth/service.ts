import argon2 from "argon2";
import type { Database } from "../db/client.js";
import type { AuthTokens, LoginInput, PublicUser, RegisterInput } from "./schemas.js";

export class AuthenticationError extends Error {
  readonly statusCode = 401;
  readonly code = "INVALID_CREDENTIALS";

  constructor() {
    super("Invalid username or password");
    this.name = "AuthenticationError";
  }
}

export class AccountConflictError extends Error {
  readonly statusCode = 409;
  readonly code = "ACCOUNT_CONFLICT";

  constructor() {
    super("Username or email is already in use");
    this.name = "AccountConflictError";
  }
}

export interface TokenSigner {
  sign(payload: { sub: string; username: string }, options: { expiresIn: string }): string;
}

export interface AuthServiceOptions {
  passwordHasher?: Pick<typeof argon2, "hash" | "verify">;
}

export class AuthService {
  private readonly passwordHasher: Pick<typeof argon2, "hash" | "verify">;

  constructor(
    private readonly db: Database,
    private readonly jwt: TokenSigner,
    private readonly tokenLifetime: string,
    options: AuthServiceOptions = {},
  ) {
    this.passwordHasher = options.passwordHasher ?? argon2;
  }

  async register(input: RegisterInput): Promise<PublicUser> {
    const passwordHash = await this.passwordHasher.hash(input.password, {
      type: argon2.argon2id,
    });

    try {
      const row = await this.db
        .insertInto("users")
        .values({
          id: crypto.randomUUID(),
          username: input.username,
          display_name: input.displayName,
          email: input.email,
          password_hash: passwordHash,
          avatar_url: null,
        })
        .returning([
          "id",
          "username",
          "display_name",
          "email",
          "avatar_url",
          "created_at",
        ])
        .executeTakeFirstOrThrow();

      return toPublicUser(row);
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new AccountConflictError();
      }
      throw error;
    }
  }

  async login(input: LoginInput): Promise<AuthTokens> {
    const row = await this.db
      .selectFrom("users")
      .select(["id", "username", "password_hash"])
      .where((expression) => expression.fn("lower", ["username"]), "=", input.username.toLowerCase())
      .executeTakeFirst();

    if (!row || !(await this.passwordHasher.verify(row.password_hash, input.password))) {
      throw new AuthenticationError();
    }

    const accessToken = this.jwt.sign(
      { sub: row.id, username: row.username },
      { expiresIn: this.tokenLifetime },
    );

    return {
      accessToken,
      tokenType: "Bearer",
      expiresInSeconds: parseTokenLifetime(this.tokenLifetime),
    };
  }
}

function parseTokenLifetime(value: string): number {
  const match = /^(\d+)(s|m|h|d)$/.exec(value);
  if (!match) {
    throw new Error("JWT_EXPIRES_IN must use seconds, minutes, hours, or days");
  }

  const amount = Number(match[1]);
  const multiplier = { s: 1, m: 60, h: 3600, d: 86400 }[match[2] as "s" | "m" | "h" | "d"];
  return amount * multiplier;
}

function toPublicUser(row: {
  id: string;
  username: string;
  display_name: string;
  email: string;
  avatar_url: string | null;
  created_at: Date | string | object;
}): PublicUser {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    email: row.email,
    avatarUrl: row.avatar_url,
    createdAt: new Date(String(row.created_at)),
  };
}

function isUniqueViolation(error: unknown): error is { code: string } {
  return typeof error === "object" && error !== null && "code" in error && error.code === "23505";
}
