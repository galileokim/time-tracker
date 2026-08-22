import type { Database } from "../db/client.js";
import type { CreateLogInput, LogReceipt } from "./schemas.js";

export class CategoryOwnershipError extends Error {
  readonly statusCode = 400;
  readonly code = "INVALID_CATEGORIES";

  constructor() {
    super("One or more categories are unavailable to this account");
    this.name = "CategoryOwnershipError";
  }
}

export class LogConflictError extends Error {
  readonly statusCode = 409;
  readonly code = "IDEMPOTENCY_CONFLICT";

  constructor() {
    super("Idempotency key is already associated with another log request");
    this.name = "LogConflictError";
  }
}

export class LogService {
  constructor(private readonly db: Database) {}

  async create(userId: string, input: CreateLogInput): Promise<LogReceipt> {
    try {
      return await this.db.transaction().execute(async (transaction) => {
      const existing = await transaction
        .selectFrom("logs")
        .select(["id", "user_id", "idempotency_key", "title", "notes", "started_at", "ended_at", "visibility"])
        .where("idempotency_key", "=", input.idempotencyKey)
        .executeTakeFirst();

      if (existing) {
        const links = await transaction
          .selectFrom("log_categories")
          .select("category_id")
          .where("log_id", "=", existing.id)
          .orderBy("category_id", "asc")
          .execute();
        const existingCategoryIds = links.map((link) => link.category_id).sort();
        const requestedCategoryIds = [...input.categoryIds].sort();

        if (
          existing.user_id !== userId ||
          existing.title !== input.title ||
          existing.notes !== (input.notes ?? null) ||
          new Date(existing.started_at).getTime() !== Date.parse(input.startedAt) ||
          new Date(existing.ended_at).getTime() !== Date.parse(input.endedAt) ||
          existing.visibility !== input.visibility ||
          !sameStrings(existingCategoryIds, requestedCategoryIds)
        ) {
          throw new LogConflictError();
        }

        return { id: existing.id, idempotencyKey: input.idempotencyKey, created: false };
      }

      if (input.categoryIds.length > 0) {
        const ownedCategories = await transaction
          .selectFrom("categories")
          .select("id")
          .where("user_id", "=", userId)
          .where("id", "in", input.categoryIds)
          .execute();

        if (ownedCategories.length !== new Set(input.categoryIds).size) {
          throw new CategoryOwnershipError();
        }
      }

      const log = await transaction
        .insertInto("logs")
        .values({
          user_id: userId,
          title: input.title,
          notes: input.notes ?? null,
          started_at: new Date(input.startedAt),
          ended_at: new Date(input.endedAt),
          visibility: input.visibility,
          idempotency_key: input.idempotencyKey,
        })
        .returning(["id"])
        .executeTakeFirstOrThrow();

      if (input.categoryIds.length > 0) {
        await transaction
          .insertInto("log_categories")
          .values(input.categoryIds.map((categoryId) => ({
            log_id: log.id,
            category_id: categoryId,
          })))
          .execute();
      }

      return { id: log.id, idempotencyKey: input.idempotencyKey, created: true };
      });
    } catch (error) {
      if (isUniqueViolation(error)) {
        const existing = await this.db
          .selectFrom("logs")
          .select(["id", "user_id", "title", "notes", "started_at", "ended_at", "visibility"])
          .where("idempotency_key", "=", input.idempotencyKey)
          .executeTakeFirst();

        if (existing && existing.user_id === userId && await this.matchesExistingLog(existing, input)) {
          return { id: existing.id, idempotencyKey: input.idempotencyKey, created: false };
        }
        if (existing) throw new LogConflictError();
      }
      throw error;
    }
  }

  private async matchesExistingLog(
    existing: {
      id: string;
      title: string;
      notes: string | null;
      started_at: Date | string | object;
      ended_at: Date | string | object;
      visibility: string;
    },
    input: CreateLogInput,
  ): Promise<boolean> {
    const links = await this.db
      .selectFrom("log_categories")
      .select("category_id")
      .where("log_id", "=", existing.id)
      .orderBy("category_id", "asc")
      .execute();
    const existingCategoryIds = links.map((link) => link.category_id).sort();
    const requestedCategoryIds = [...input.categoryIds].sort();

    return existing.title === input.title &&
      existing.notes === (input.notes ?? null) &&
      new Date(String(existing.started_at)).getTime() === Date.parse(input.startedAt) &&
      new Date(String(existing.ended_at)).getTime() === Date.parse(input.endedAt) &&
      existing.visibility === input.visibility &&
      sameStrings(existingCategoryIds, requestedCategoryIds);
  }
}

function isUniqueViolation(error: unknown): error is { code: string } {
  return typeof error === "object" && error !== null && "code" in error && error.code === "23505";
}

function sameStrings(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}
