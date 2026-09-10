# Changelog

## 0.5.0

Setting up a repository took four manual steps, and the CLI's errors sent you
down the wrong path when you got one wrong. Both fixed after watching a
first-time setup go sideways.

- `commitreview init` does the setup in one command: adds this tool to
  `.mcp.json` while keeping any servers already configured there, installs the
  agent skill, and makes `.review/` ignore itself. Safe to re-run, and it
  refuses to touch a `.mcp.json` it cannot parse.
- `--version`, which did not exist. `dart pub global activate --source git`
  pins whichever commit was current at the time, so two installs could both
  call themselves 0.4.0 and behave differently, with no way to tell.
- Unknown options are now rejected by name. A typo like `--prot` used to be
  treated as a git ref and reported as "expected at most one base ref".
- A mistyped or unavailable subcommand says so, rather than reporting that
  `install-skill` could not be resolved to a commit, and points out that an
  install can be older than the docs.
- Git output is decoded as UTF-8 rather than the system encoding. On Windows
  every accented character, CJK glyph and emoji in a diff was mojibake.

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
