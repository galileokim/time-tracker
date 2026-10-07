import assert from "node:assert/strict";
import test from "node:test";
import { canViewLog, type LogVisibility } from "../src/social/visibility.js";

const visibilities: LogVisibility[] = ["public", "private", "friends_only"];

 test("visibility policy keeps own logs visible and isolates directed follow rules", () => {
  for (const visibility of visibilities) {
    for (const viewerFollowsAuthor of [false, true]) {
      for (const authorFollowsViewer of [false, true]) {
        assert.equal(canViewLog({
          authorId: "viewer",
          viewerId: "viewer",
          visibility,
          viewerFollowsAuthor,
          authorFollowsViewer,
        }), true);

        const actual = canViewLog({
          authorId: "author",
          viewerId: "viewer",
          visibility,
          viewerFollowsAuthor,
          authorFollowsViewer,
        });
        const expected = visibility === "public"
          ? viewerFollowsAuthor
          : visibility === "friends_only"
            ? authorFollowsViewer
            : false;
        assert.equal(actual, expected, `${visibility} viewerFollowsAuthor=${viewerFollowsAuthor} authorFollowsViewer=${authorFollowsViewer}`);
      }
    }
  }
});

test("visibility policy is invariant to unrelated follow edges", () => {
  const contexts = [
    { visibility: "public" as const, viewerFollowsAuthor: true, authorFollowsViewer: false, expected: true },
    { visibility: "public" as const, viewerFollowsAuthor: false, authorFollowsViewer: true, expected: false },
    { visibility: "friends_only" as const, viewerFollowsAuthor: true, authorFollowsViewer: false, expected: false },
    { visibility: "friends_only" as const, viewerFollowsAuthor: false, authorFollowsViewer: true, expected: true },
    { visibility: "private" as const, viewerFollowsAuthor: true, authorFollowsViewer: true, expected: false },
  ];

  for (const context of contexts) {
    for (let index = 0; index < 100; index += 1) {
      assert.equal(canViewLog({ authorId: "author", viewerId: "viewer", ...context }), context.expected);
    }
  }
});
