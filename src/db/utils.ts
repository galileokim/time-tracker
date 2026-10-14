export function isUniqueViolation(error: unknown): error is { code: string } {
  return typeof error === "object" && error !== null && "code" in error && error.code === "23505";
}

/** Normalizes timestamp columns, which the driver may return as `Date` or string. */
export function toDate(value: Date | string | object): Date {
  return value instanceof Date ? value : new Date(String(value));
}
