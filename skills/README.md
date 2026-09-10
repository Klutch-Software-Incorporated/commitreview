# Skills

Agent skills that teach a coding agent how to work through a commitreview
review — reading your comments, replying inline, committing changes, and
picking up the next patchset.

Without one, an agent has to be told the workflow every time, and will
typically forget the part that matters most: **commitreview reviews commits,
so uncommitted edits are invisible to you.**

## Claude Code

The skill is bundled inside the `commitreview` binary, so you do not need this
directory — or a clone — to install it:

```sh
commitreview install-skill             # every project on this machine
commitreview install-skill --project   # just this repository
```

`SKILL.md` here is the source those are generated from
(`dart run tool/embed_skill.dart`), and is what you read and edit. CI fails if
the embedded copy falls behind it.

Copying it by hand works too, if you would rather:

```sh
mkdir -p ~/.claude/skills && cp -r skills/commitreview ~/.claude/skills/
```

On Windows, `%USERPROFILE%\.claude\skills\`.

Claude loads it on its own when you say something like "I've left some
comments" or "check the review". You can also invoke it directly with
`/commitreview`.

## Other agents

`commitreview/SKILL.md` is plain markdown with YAML frontmatter. The
frontmatter's `description` is what tells an agent when the skill applies;
the body is the instructions. Most agent frameworks that support skills or
custom instructions can use it as-is, or you can paste the body into whatever
system-prompt mechanism yours provides.

## What it covers

- Opening a review: finding an existing server via `/whoami` before starting
  one, and reporting the URL back
- Reaching the server over MCP, and the HTTP fallback for when the server was
  started after the agent's session began
- The loop: read pending comments, reply, commit, refresh, resolve
- That answering a question is often the right response, rather than editing
- That uncommitted work is not part of the review
- Not starting or stopping servers you did not ask it to
