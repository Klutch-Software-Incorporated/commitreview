<h1 align="center">
  <img src="assets/commitreview-logo.svg" alt="commitreview" width="380">
</h1>

<!-- Screenshot of the review UI goes here. -->

Serve a commit's diff to your browser, comment on the lines you care about, and
let your AI coding agent read those comments over MCP so it can answer them and
commit the changes back.

## Quickstart

With the [Dart SDK](https://dart.dev/get-dart):

```bash
dart pub global activate commitreview
```

Or download a binary for your platform from
[Releases](https://github.com/Klutch-Software-Incorporated/commitreview/releases)
and put it on your `PATH`. It is self-contained, so this needs no Dart at all.

Then install the skill that teaches your agent to use it:

```bash
commitreview install-skill
```

Restart your agent so it picks up the skill. Then from any git repository:

```bash
commitreview  # review the latest commit in the browser
```

Click any line to comment, then tell your agent you've left comments. It
replies to what you asked and commits what you wanted changed. That commit
becomes the next round, with your comments still on the right lines.

If `commitreview` isn't found after activating it, add Dart's pub cache to your
`PATH` (`$HOME/.pub-cache/bin`, or `%LOCALAPPDATA%\Pub\Cache\bin` on Windows),
or run it as `dart pub global run commitreview`.

## Usage

### Reviewing

```bash
commitreview           # the latest commit (HEAD~1..HEAD)
commitreview main      # everything since main
commitreview abc123    # everything since a specific commit
```

The server runs until you stop it, and comments save as you write them. A
single line can carry several separate threads.

| Flag | Default | Description |
| --- | --- | --- |
| `<base>` | `HEAD~1` | Review everything since this commit, branch or tag |
| `--repo <path>` | cwd | Repository to review |
| `--port <n>` | 4970 | Listen port; takes the next free one if busy |
| `--no-open` | false | Don't launch a browser |
| `--split` | — | Start in side-by-side view |
| `--unified` | — | Start in unified view |
| `--out <file>` | — | Also write the review to a file when the server stops |
| `-h`, `--help` | — | Show usage |

**Uncommitted work is not reviewed.** Commits are the unit of review, the way
they are in Gerrit, so commit and then refresh. Git carries your comments onto
the new commit: one whose line moved goes with it, one whose line was edited is
marked, and one whose line is gone is kept and shown against the commit it was
written on.

Comments live in `.review/threads.json` in your repository, in a directory that
ignores itself so review state never shows up as something to review.

### install-skill

Writes the bundled agent skill, so your agent knows how to open a review, read
your comments, reply, commit and refresh without being told each session.

```bash
commitreview install-skill             # every project on this machine
commitreview install-skill --project   # just this repository
```

| Flag | Default | Description |
| --- | --- | --- |
| `--project` | false | Install into `./.claude/skills` so it travels with the repo |
| `--repo <path>` | cwd | With `--project`, which repository to install into |
| `--force` | false | Overwrite even if the file was edited locally |
| `-h`, `--help` | — | Show usage |

Re-running is a no-op when nothing changed, and updates the file when the
bundled skill has moved on, so it is safe to run after an upgrade.

## Working with an agent

The skill covers the workflow, but two things are worth knowing yourself.

**Start commitreview before your agent.** MCP clients connect once, at session
start, so a server that isn't listening yet won't show up as tools. An agent
that starts the server itself falls back to plain HTTP against the same
endpoint. That works, but it is second best.

**Point your agent at it.** Copy `.mcp.json.example` into the repository you're
reviewing as `.mcp.json`:

```json
{
  "mcpServers": {
    "commitreview": { "type": "http", "url": "http://127.0.0.1:4970/mcp" }
  }
}
```

The tools are `review_pending`, `review_reply`, `review_resolve`,
`review_refresh` and `review_status`. Servers also answer `/whoami`, so an
agent can tell several apart when you have more than one review open.

See [skills/](skills/) for the skill itself, and for use with agents other than
Claude Code.

## Development

```bash
dart test
dart run tool/check_page_js.dart    # the page script lives in a Dart string
dart run tool/embed_skill.dart      # after editing skills/commitreview/SKILL.md
```

`check_page_js` matters more than it looks: the page's JavaScript lives inside
a Dart string, so a broken literal compiles perfectly and then takes out the
entire UI in the browser. It runs `node --check` over the real script.

`embed_skill` regenerates `lib/src/skill.g.dart` from the skill markdown, which
is what lets `install-skill` work without a clone. The markdown is the source of
truth; CI regenerates and fails if the committed copy is behind.

To build a standalone binary:

```bash
git clone https://github.com/Klutch-Software-Incorporated/commitreview.git
cd commitreview
dart pub get
dart compile exe bin/commitreview.dart -o commitreview
```

There are no runtime dependencies, so the result can be dropped anywhere on
your `PATH`.

### Releasing

Bump `version:` in `pubspec.yaml`, add a `CHANGELOG.md` entry, then tag:

```bash
git tag v0.4.0 && git push origin v0.4.0
```

That runs the release workflow: it checks the tag matches the pubspec version,
runs the tests, creates the GitHub release, and attaches a binary built on
Linux, macOS (Intel and Apple silicon) and Windows.

Publishing to pub.dev is a separate opt-in job in the same workflow. The
package has to exist there first, so run `dart pub publish` once by hand, then
enable automated publishing for this repository on pub.dev and set the
repository variable `PUBLISH_TO_PUB_DEV` to `true`. After that a tag publishes
both. It uses a short-lived OIDC token rather than a stored credential.

## Requirements

- [Dart SDK](https://dart.dev/get-dart) 3.5 or newer
- A git repository with commits to review
- A browser
- Node.js, for `tool/check_page_js.dart` only (not needed to run the tool)

## License

MIT. See [LICENSE](LICENSE).
