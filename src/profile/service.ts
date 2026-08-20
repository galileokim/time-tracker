import type { Database } from "../db/client.js";
import type { CreateCategoryInput, CategoryResponse, UpdateProfileInput } from "./schemas.js";
import type { PublicUser } from "../auth/schemas.js";

export class ProfileNotFoundError extends Error {
  readonly statusCode = 404;
  readonly code = "PROFILE_NOT_FOUND";

  constructor() {
    super("Profile not found");
    this.name = "ProfileNotFoundError";
  }
}

export class CategoryConflictError extends Error {
  readonly statusCode = 409;
  readonly code = "CATEGORY_CONFLICT";

  constructor() {
    super("Category name already exists");
    this.name = "CategoryConflictError";
  }
}

export class ProfileService {
  constructor(private readonly db: Database) {}

  async getProfile(userId: string): Promise<PublicUser> {
    const row = await this.db
      .selectFrom("users")
      .select(["id", "username", "display_name", "email", "avatar_url", "created_at"])
      .where("id", "=", userId)
      .executeTakeFirst();

    if (!row) throw new ProfileNotFoundError();
    return toPublicUser(row);
  }

  async updateProfile(userId: string, input: UpdateProfileInput): Promise<PublicUser> {
    const changes: { display_name?: string; avatar_url?: string | null } = {};
    if (input.displayName !== undefined) changes.display_name = input.displayName;
    if (input.avatarUrl !== undefined) changes.avatar_url = input.avatarUrl;

    const row = await this.db
      .updateTable("users")
      .set(changes)
      .where("id", "=", userId)
      .returning(["id", "username", "display_name", "email", "avatar_url", "created_at"])
      .executeTakeFirst();

    if (!row) throw new ProfileNotFoundError();
    return toPublicUser(row);
  }

  async createCategory(userId: string, input: CreateCategoryInput): Promise<CategoryResponse> {
    try {
      const row = await this.db
        .insertInto("categories")
        .values({
          user_id: userId,
          name: input.name,
          ...(input.colorHex === undefined ? {} : { color_hex: input.colorHex }),
        })
        .returning(["id", "name", "color_hex", "created_at"])
        .executeTakeFirstOrThrow();

      return toCategory(row);
    } catch (error) {
      if (isUniqueViolation(error)) throw new CategoryConflictError();
      throw error;
    }
  }

  async listCategories(userId: string): Promise<CategoryResponse[]> {
    const rows = await this.db
      .selectFrom("categories")
      .select(["id", "name", "color_hex", "created_at"])
      .where("user_id", "=", userId)
      .orderBy("created_at", "asc")
      .orderBy("id", "asc")
      .execute();

    return rows.map(toCategory);
  }
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
    createdAt: toDate(row.created_at),
  };
}

function toCategory(row: {
  id: string;
  name: string;
  color_hex: string;
  created_at: Date | string | object;
}): CategoryResponse {
  return {
    id: row.id,
    name: row.name,
    colorHex: row.color_hex,
    createdAt: toDate(row.created_at),
  };
}

function toDate(value: Date | string | object): Date {
  return value instanceof Date ? value : new Date(String(value));
}

function isUniqueViolation(error: unknown): error is { code: string } {
  return typeof error === "object" && error !== null && "code" in error && error.code === "23505";
}
