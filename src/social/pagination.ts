export interface FeedOrderKey {
  createdAt: Date;
  id: string;
}

export interface FeedCursorKey {
  createdAt: Date;
  id: string;
}

export function isOlderThanCursor(entry: FeedOrderKey, cursor: FeedCursorKey): boolean {
  const entryTime = entry.createdAt.getTime();
  const cursorTime = cursor.createdAt.getTime();
  return entryTime < cursorTime || (entryTime === cursorTime && entry.id < cursor.id);
}

export function cursorPredicateValues(cursor: FeedCursorKey): { createdAt: Date; id: string } {
  return { createdAt: cursor.createdAt, id: cursor.id };
}

export function sortFeedDescending<T extends FeedOrderKey>(entries: readonly T[]): T[] {
  return [...entries].sort((left, right) => {
    const timeDifference = right.createdAt.getTime() - left.createdAt.getTime();
    if (timeDifference !== 0) return timeDifference;
    return right.id.localeCompare(left.id);
  });
}

export function paginateFeed<T extends FeedOrderKey>(entries: readonly T[], limit: number, cursor?: FeedCursorKey): { items: T[]; hasMore: boolean } {
  const ordered = sortFeedDescending(entries).filter((entry) => !cursor || isOlderThanCursor(entry, cursor));
  return {
    items: ordered.slice(0, limit),
    hasMore: ordered.length > limit,
  };
}
