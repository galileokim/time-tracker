import { Kysely, PostgresDialect } from "kysely";
import { Pool } from "pg";
import type { AppConfig } from "../config.js";
import type { DatabaseSchema } from "./types.js";

export function createDatabase(config: Pick<AppConfig, "DATABASE_URL">) {
  const pool = new Pool({ connectionString: config.DATABASE_URL });
  const db = new Kysely<DatabaseSchema>({
    dialect: new PostgresDialect({ pool }),
  });

  return {
    db,
    pool,
    close: () => db.destroy(),
  };
}

export type Database = Kysely<DatabaseSchema>;
