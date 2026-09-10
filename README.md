# commitreview

Review a commit locally, in your browser, and hand the comments to your AI
coding agent — which can answer them inline, make the changes, and push the
next commit back into the same review.

It renders a commit's diff, lets you comment on any line, and exposes those
threads over MCP. The agent reads them, replies where you asked a question,
edits and commits, then refreshes; your tab updates itself.

**Commits are the unit of review, as in Gerrit.** Each head commit is a
patchset. Comments anchor to `(file, line)` on the patchset they were raised
on, and git carries them onto later patchsets — so an edited line keeps its
comment and a deleted one is reported as deleted rather than guessed at.
Uncommitted work is not reviewed; commit it, then refresh.

Written in Dart with no runtime dependencies — just `dart:io` and
`dart:convert` — so `dart compile exe` gives you a single binary.

## Running

```sh
dart run commitreview          # the latest commit (HEAD~1..HEAD)
dart run commitreview main     # everything since main
```

Or build a standalone binary:

```sh
dart compile exe bin/commitreview.dart -o commitreview.exe
```

Options: `--repo <path>`, `--port <n>` (default 4970), `--out <file>`,
`--no-open`, `--split`, `--unified`.

## Wiring it to an agent

The server must be listening **before** the agent connects, because MCP
clients connect at session start. Start it in your own terminal, then start
Claude Code. Copy `.mcp.json.example` to `.mcp.json` in the repo you are
reviewing:

```json
{
  "mcpServers": {
    "commitreview": { "type": "http", "url": "http://127.0.0.1:4970/mcp" }
  }
}
```

Tools: `review_pending`, `review_reply`, `review_resolve`, `review_refresh`,
`review_status`.

The loop is: leave comments in the browser, tell the agent to check the
review, it answers inline and edits files, then calls `review_refresh`. Your
tab reloads itself within about two seconds.

## How comments survive new commits

The base is resolved once and **pinned**, including across restarts. That is
what makes both workflows behave: amending rewrites HEAD but leaves the base
alone, and committing on top simply makes the next patchset cumulative. If
the base tracked `HEAD~1` it would slide forward and you would end up
reviewing only the most recent fix.

When HEAD moves, the new commit becomes the next patchset and every open
thread is carried across using `git diff -U0 -M <old> <new>`:

| Situation | Result |
|---|---|
| Line outside every hunk | shifted by the running offset — clean |
| Line in a replaced run | aligned onto the line it became — **Line edited** |
| Nothing in the run corresponds to it | **Not in this patchset** |

Git decides what moved, so there are no thresholds to tune and no global
searching. Comments on **removed** lines point into the pinned base, so they
never move at all.

The one place git is not enough: it reports a rewritten block as "these N
lines became these M" without saying which became which. A doc comment
inserted at the top of a two-line block would push every comment one line
early. So within a replaced run — and only there, among lines git has already
identified as the replacement — the two halves are aligned with an
order-preserving dynamic program. A one-for-one replacement is taken as
certain regardless of how different the text is; there is nothing to
disambiguate.

Nothing is ever discarded. A thread that leaves the diff moves to a
collapsible panel showing the code as it was on the patchset it was raised
on, still repliable and resolvable — and since that patchset is an immutable
commit, it stays reproducible forever. Reviewed commits are pinned under
`refs/review/*` so a rebase or squash cannot let `git gc` prune them.

Threads persist in `<repo>/.review/threads.json`, keyed by the pinned base.
The directory ignores itself, so review state never shows up as a change to
review.

## Layout

| Path | What's in it |
|---|---|
| `bin/commitreview.dart` | CLI parsing and entry point |
| `tool/check_page_js.dart` | Parses the page's JavaScript with `node --check` |
| `lib/src/diff.dart` | Diff walking and HTML rendering of rows, files, tree |
| `lib/src/target.dart` | Base, patchsets, and ref pinning |
| `lib/src/mapping.dart` | Carrying a line from one commit to the next |
| `lib/src/git.dart` | Thin git CLI wrapper |
| `lib/src/anchor.dart` | Diff context windows and snapshots |
| `lib/src/model.dart` | `Msg`, `Thread`, `Session` and persistence |
| `lib/src/doc.dart` | The diff and everything derived from it |
| `lib/src/html.dart` | Template substitution |
| `lib/src/template.dart` | The single-page UI |
| `lib/src/markdown.dart` | What the agent actually reads |
| `lib/src/mcp.dart` | JSON-RPC and the tool definitions |
| `lib/src/server.dart` | HTTP routing and the server loop |

## Tests

```sh
dart test
dart run tool/check_page_js.dart   # the page script is inside a Dart string
```

The anchoring tests build diffs by hand rather than shelling out to git, so
they're fast and deterministic. They cover the cases that actually broke
during development: a shifted line, an edited line, a deleted line, a renamed
file, an insertion inside a replaced run (the off-by-one), a resumed review
keeping its pinned base across restarts, and a diff containing the template's
own placeholder tokens.
