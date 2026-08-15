exports.up = (pgm) => {
  pgm.createExtension("pgcrypto", { ifNotExists: true });

  pgm.createTable("users", {
    id: { type: "uuid", primaryKey: true },
    username: { type: "varchar(50)", notNull: true },
    display_name: { type: "varchar(100)", notNull: true },
    email: { type: "varchar(255)", notNull: true },
    password_hash: { type: "text", notNull: true },
    avatar_url: { type: "text" },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("current_timestamp") },
  });
  pgm.createIndex("users", pgm.func("lower(username)"), { name: "users_username_unique", unique: true });
  pgm.createIndex("users", pgm.func("lower(email)"), { name: "users_email_unique", unique: true });

  pgm.createTable("categories", {
    id: { type: "uuid", primaryKey: true, default: pgm.func("gen_random_uuid()") },
    user_id: { type: "uuid", notNull: true, references: '"users"', onDelete: "CASCADE" },
    name: { type: "varchar(50)", notNull: true },
    color_hex: { type: "varchar(7)", notNull: true, default: "#3B82F6" },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("current_timestamp") },
  });
  pgm.addConstraint("categories", "categories_user_name_unique", { unique: ["user_id", "name"] });
  pgm.addConstraint("categories", "categories_color_hex_check", {
    check: "color_hex ~ '^#[0-9A-Fa-f]{6}$'",
  });

  pgm.createTable("logs", {
    id: { type: "uuid", primaryKey: true, default: pgm.func("gen_random_uuid()") },
    user_id: { type: "uuid", notNull: true, references: '"users"', onDelete: "CASCADE" },
    title: { type: "varchar(100)", notNull: true },
    notes: { type: "text" },
    started_at: { type: "timestamptz", notNull: true },
    ended_at: { type: "timestamptz", notNull: true },
    duration_seconds: {
      type: "integer",
      notNull: true,
      expressionGenerated: "extract(epoch from (ended_at - started_at))::integer",
    },
    visibility: { type: "varchar(20)", notNull: true, default: "public" },
    idempotency_key: { type: "uuid", notNull: true, unique: true },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("current_timestamp") },
  });
  pgm.addConstraint("logs", "logs_visibility_check", {
    check: "visibility IN ('public', 'private', 'friends_only')",
  });
  pgm.addConstraint("logs", "logs_time_order_check", { check: "ended_at >= started_at" });
  pgm.createIndex("logs", ["user_id", "started_at", "id"]);

  pgm.createTable("log_categories", {
    log_id: { type: "uuid", notNull: true, references: '"logs"', onDelete: "CASCADE" },
    category_id: { type: "uuid", notNull: true, references: '"categories"', onDelete: "CASCADE" },
  });
  pgm.addConstraint("log_categories", "log_categories_pkey", { primaryKey: ["log_id", "category_id"] });

  pgm.createTable("follows", {
    follower_id: { type: "uuid", notNull: true, references: '"users"', onDelete: "CASCADE" },
    following_id: { type: "uuid", notNull: true, references: '"users"', onDelete: "CASCADE" },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("current_timestamp") },
  });
  pgm.addConstraint("follows", "follows_pkey", { primaryKey: ["follower_id", "following_id"] });
  pgm.addConstraint("follows", "follows_distinct_users_check", {
    check: "follower_id <> following_id",
  });
  pgm.createIndex("follows", ["following_id", "follower_id"]);
};

exports.down = (pgm) => {
  pgm.dropTable("follows");
  pgm.dropTable("log_categories");
  pgm.dropTable("logs");
  pgm.dropTable("categories");
  pgm.dropTable("users");
};
