export type LogVisibility = "public" | "private" | "friends_only";

export interface VisibilityContext {
  authorId: string;
  viewerId: string;
  visibility: LogVisibility;
  viewerFollowsAuthor: boolean;
  authorFollowsViewer: boolean;
}

export function canViewLog({
  authorId,
  viewerId,
  visibility,
  viewerFollowsAuthor,
  authorFollowsViewer,
}: VisibilityContext): boolean {
  if (authorId === viewerId) return true;
  if (visibility === "public") return viewerFollowsAuthor;
  if (visibility === "friends_only") return authorFollowsViewer;
  return false;
}
