# Skills

Agent skills that teach a coding agent how to work through a commitreview
review — reading your comments, replying inline, committing changes, and
picking up the next patchset.

Without one, an agent has to be told the workflow every time, and will
typically forget the part that matters most: **commitreview reviews commits,
so uncommitted edits are invisible to you.**

## Installing

You need neither this directory nor a clone.

**From the binary** — the skill is bundled inside it:

```sh
commitreview install-skill             # every project on this machine
commitreview install-skill --project   # just this repository
```

**With [skills.sh](https://skills.sh)** — the layout here follows the
ecosystem convention (`skills/<name>/SKILL.md`), so this repository works with
it as-is, and covers Codex, Cursor, Zed, Amp and others rather than just
Claude Code:

```sh
npx skills add Klutch-Software-Incorporated/commitreview -g   # global
npx skills add Klutch-Software-Incorporated/commitreview      # this project
```

**By hand**, if you would rather:

```sh
mkdir -p ~/.claude/skills && cp -r skills/commitreview ~/.claude/skills/
```

On Windows, `%USERPROFILE%\.claude\skills\`.

Claude loads the skill on its own when you say something like "open a review"
or "I've left some comments". You can also invoke it directly with
`/commitreview`.

## Editing it

`commitreview/SKILL.md` is the source of truth — it is what you read here and
what every installer hands out. After changing it, regenerate the copy
embedded in the binary:

```sh
dart run tool/embed_skill.dart
```

CI fails if the embedded copy falls behind, and a test asserts the two match.

It is plain markdown with YAML frontmatter. The frontmatter's `description` is
what tells an agent when the skill applies; the body is the instructions. Any
framework supporting skills can use it as-is, or you can paste the body into
whatever system-prompt mechanism yours provides.

## What it covers

- Opening a review: finding an existing server via `/whoami` before starting
  one, and reporting the URL back
- Reaching the server over MCP, and the HTTP fallback for when the server was
  started after the agent's session began
- The loop: read pending comments, reply, commit, refresh, resolve
- That answering a question is often the right response, rather than editing
- That uncommitted work is not part of the review
- Not starting or stopping servers you did not ask it to
