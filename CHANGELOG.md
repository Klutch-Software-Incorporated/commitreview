# Changelog

## 0.4.0

First public release.

- Review a commit's diff in the browser and comment on any line. Several
  threads can share a line.
- Commits are the unit of review, as in Gerrit. The base is resolved once and
  pinned, including across restarts, and each new head commit becomes the next
  patchset.
- Comments are carried onto later patchsets using git's own line mapping, so a
  line that moved keeps its comment, an edited line is marked, and a deleted
  one is kept and shown against the commit it was raised on.
- MCP endpoint at `/mcp` exposing `review_pending`, `review_reply`,
  `review_resolve`, `review_refresh` and `review_status`, so an agent can read
  comments, answer inline, and pick up the commits made in response.
- `commitreview install-skill` writes a bundled agent skill that teaches an
  agent the workflow, with no clone required.
- Servers self-identify at `/whoami`, and a busy port is skipped rather than
  being fatal, so several reviews can run at once.
- Split and unified views, a file tree, per-file viewed state, and light/dark
  themes.
