<img src="assets/commitreview-icon.svg" alt="" width="88" align="right">

# commitreview

Review a commit in your browser, leave comments on the lines you care about,
and hand them to your AI coding agent — which answers your questions inline,
makes the changes, and commits them back into the same review.

Then you review the next commit, with your comments still attached to the
right lines.

Your editor can already show you a diff, but it gives you nowhere to *respond*
to one — feedback gets retyped into a chat window, detached from the code it
was about. And half of review isn't "change this", it's "why did you do it
this way?". commitreview gives each line a conversation instead.

## Requirements

- [Dart SDK](https://dart.dev/get-dart) 3.5 or newer
- git
- A browser

## Install

```sh
dart pub global activate --source git \
  https://github.com/Klutch-Software-Incorporated/commitreview.git
```

That puts a `commitreview` executable in Dart's pub cache. Add the cache's
`bin` to your `PATH` to call it directly:

| Platform | Add to `PATH` |
|---|---|
| macOS / Linux | `$HOME/.pub-cache/bin` |
| Windows | `%LOCALAPPDATA%\Pub\Cache\bin` |

Without that, `dart pub global run commitreview` works from anywhere.

To update later, run the same `activate` command again. To remove it,
`dart pub global deactivate commitreview`.

### From a clone

```sh
git clone https://github.com/Klutch-Software-Incorporated/commitreview.git
cd commitreview
dart pub get
dart run bin/commitreview.dart          # run it directly
dart compile exe bin/commitreview.dart -o commitreview   # or build a binary
```

The compiled binary is self-contained — there are no runtime dependencies, so
you can drop it anywhere on your `PATH` and forget about it.

## Use

From inside a git repository:

```sh
commitreview              # review the latest commit (HEAD~1..HEAD)
commitreview main         # review everything since main
```

It prints a URL and opens your browser. Click any line to comment; click
**Reply** on a thread to add to it. A line can carry several separate threads.

| Option | |
|---|---|
| `--repo <path>` | review a different repository |
| `--port <n>` | listen port, default 4970 |
| `--no-open` | don't launch a browser |
| `--split` / `--unified` | pick the starting diff view |
| `--out <file>` | also write the review to a file on exit |

The server keeps running until you stop it. Comments save as you write them,
into `.review/threads.json` in your repository — a directory that ignores
itself, so review state never shows up as something to review.

**Uncommitted work is not reviewed.** Commits are the unit of review, the way
they are in Gerrit — so commit, then refresh. When you do, your comments are
carried onto the new commit by git: one that moved goes with it, one whose
line was edited is marked, and one whose line is gone is kept and shown
against the commit it was written on.

## Connecting your agent

Copy `.mcp.json.example` into the repository you're reviewing as `.mcp.json`:

```json
{
  "mcpServers": {
    "commitreview": { "type": "http", "url": "http://127.0.0.1:4970/mcp" }
  }
}
```

**Start commitreview before you start your agent** — MCP clients connect once,
at session start, so a server that isn't listening yet won't be found.

Then the loop is:

1. Leave your comments.
2. Tell the agent to check the review.
3. It replies inline where you asked something, and edits where you asked for
   a change.
4. It commits and refreshes. Your tab updates itself within a couple of
   seconds, showing the new commit as the next patchset.

Your comments come with you, attached to the same code.

## The agent skill

A skill ships with commitreview that teaches an agent this whole workflow, so
you don't have to explain it every session. Without it, agents reliably get
one thing wrong: **they leave changes uncommitted**, which makes it look like
they did nothing, because only commits are reviewed.

### Install it

The skill is bundled inside the binary, so this needs nothing else — no
clone, no download, no other tooling:

```sh
commitreview install-skill             # every project on this machine
commitreview install-skill --project   # just this repository
```

Re-running is a no-op if nothing changed, and updates the file if the bundled
skill has moved on — so it's safe after an upgrade. It writes to
`~/.claude/skills/`, or `%USERPROFILE%\.claude\skills\` on Windows.

Restart your agent afterwards, or start a new session, so it picks the skill
up.

### Use it

Just ask. The skill triggers on what you'd say anyway:

> open a review of your work

> I've left some comments

> check the review

Or invoke it directly with `/commitreview`.

Asking for a review starts a server for the current repository — reusing one
that's already running rather than starting a second — hands you the URL, and
waits. Say when you're done commenting and the agent picks it up from there.

### What it handles

- Finding an existing server before starting one, by asking each candidate
  port `/whoami`, since a busy port means the port isn't fixed
- Talking to the server over MCP where available, and over plain HTTP where
  not — which is the normal case for a server started mid-session
- Committing before refreshing, so its work is actually visible to you
- Answering a question rather than silently rewriting the code, when what you
  left was a question

See [skills/](skills/) for use with agents other than Claude Code.

## Development

```sh
dart test
dart run tool/check_page_js.dart    # the page script lives in a Dart string
dart run tool/embed_skill.dart      # after editing skills/commitreview/SKILL.md
```

`check_page_js` matters more than it looks: the page's JavaScript lives inside
a Dart string, so a broken literal compiles perfectly and then takes out the
entire UI in the browser. It runs `node --check` over the real script.

`embed_skill` regenerates `lib/src/skill.g.dart` from the skill markdown, which
is what lets `commitreview install-skill` work without a clone. The markdown is
the source of truth; CI regenerates and fails if the committed copy is behind.

The tests build diffs by hand instead of shelling out to git, so they're fast
and deterministic. They cover the cases that actually broke while this was
being written — a shifted line, an edited line, a deleted line, a renamed
file, an insertion inside a rewritten block, and a review resuming after a
restart with its base intact.

## License

MIT — see [LICENSE](LICENSE).
