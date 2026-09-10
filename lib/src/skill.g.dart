// GENERATED. Do not edit. Run: dart run tool/embed_skill.dart
// Source: skills/commitreview/SKILL.md

/// The agent skill, embedded so it can be installed from the binary alone.
const skillMarkdown = r'''
---
name: commitreview
description: Open a code review for the user in commitreview, a local commit-based review tool, and work through the comments they leave. Use when the user asks for a review of your work, says they want to review something, says they have left comments, asks you to check or read the review, or names commitreview. Do not use it for ordinary requests to review code, diffs, commits, branches, or pull requests; answer those normally.
---

# commitreview

A local review tool. The user reads a commit's diff in their browser and
comments on the lines they care about; you answer inline, make changes, and
commit. Each commit is a patchset, and git carries their comments onto the new
one, so the conversation survives your edits.

## When to use this skill

Use it when the user:

- asks you to open, start, or set up a review, or asks to review your work
- says they have left comments, or asks you to check or read the review
- refers to a review thread or something they marked
- names commitreview

Do not use it for ordinary requests like "review these changes" or "find
problems in this diff". Those are answered normally, in conversation.

## Opening a review

This is the default action when the user asks for a review.

First, check whether one is already running for this repository. A running
server records itself in `.review/server.json` at the repository root:

```bash
cat .review/server.json
```

If the file is there, confirm the server is actually alive before trusting it,
since the file outlives a crash:

```bash
curl -s -m 2 "$(python -c "import json;print(json.load(open('.review/server.json'))['url'])")/whoami"
```

Use that server and give the user its URL. Never start a second server for a
repository that already has one, and never stop a server the user started.

Do **not** sweep a port range looking for servers. It reads as port scanning,
permission classifiers refuse it, and the question is narrower than that
anyway: you want this repository's review, which is what the file answers.

### Picking the command

How it is installed varies, and getting this wrong wastes a round trip:

- `commitreview`, if it resolves.
- **`commitreview.bat` on Windows whenever you are going through bash**, which
  includes the Bash tool and the user's `!` prefix. `dart pub global activate`
  installs a `.bat` shim; it is on `PATH`, but bash will not find it without
  the extension. Check with `command -v commitreview commitreview.bat`.
- `dart pub global run commitreview` otherwise. Always works if the package is
  activated, just slower to start.
- `./commitreview.exe` or `dart run bin/commitreview.dart` from a clone.

Whatever you settle on, use that exact form again when you hand a command to
the user. Telling someone to run `commitreview` when only `commitreview.bat`
resolves for them just fails twice.

### Starting it

Run it with the Bash tool's **`run_in_background` option**, with no shell
redirection and no trailing `&`. Redirecting output to a file to background it
looks like hiding output from the conversation, and gets refused.

- With no argument it reviews the latest commit (`HEAD~1..HEAD`).
- With a ref it reviews everything since that ref, e.g. `main` for a whole
  branch. If you have made several commits the user has not seen, a base ref
  covering all of them beats reviewing only the last.

The server prints its URL on startup. Give the user that URL.

### If starting it is refused

Launching a long-running local server is exactly the shape of thing a
permission classifier declines, and that is not a fault to work around. Stop
and hand it over, rather than trying variations:

> Run `commitreview.bat` yourself with `! commitreview.bat` and I'll pick it
> up from the output — or allow it once and I'll start it.

Use the command form you established above. Then wait.

Then tell the user:

- the URL (it opens a browser itself, but say it in case that fails)
- what is under review: the patchset and commit subject from the log
- that you are waiting, and they should reply here when they have finished
  commenting

Then stop and wait. Do not poll for comments.

If the log shows uncommitted changes are present, mention it. They are not part
of the review.

## Reaching the server

If tools named `review_pending`, `review_reply`, `review_resolve`,
`review_refresh` and `review_status` are available, use them.

Otherwise fall back to HTTP. MCP clients connect once, at session start, so a
server you just started will not appear as tools; expect to use HTTP for any
review you opened yourself. The endpoint is plain JSON-RPC:

```bash
call() {  # call <tool> '<json-args>'
  curl -s -X POST http://127.0.0.1:4970/mcp -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}"
}

call review_pending '{}'
call review_reply '{"thread":3,"text":"Fixed in the new commit."}'
call review_resolve '{"thread":3}'
call review_refresh '{}'
```

Use the port the server actually reported. Pass `{}` explicitly for tools that
take no arguments. The reply is JSON-RPC; the part you want is at
`.result.content[0].text`:

```bash
call review_pending '{}' | python -c \
  "import json,sys; print(json.load(sys.stdin)['result']['content'][0]['text'])"
```

## Working through the comments

Once the user says they are done commenting:

1. `review_pending` returns every thread with a new comment, each with its diff
   context, real `file:line`, and full message history. Threads you have
   already seen are not repeated.
2. Address each one. Some ask for a change. Some ask a question and want an
   answer rather than an edit, so read carefully before editing anything.
3. `review_reply(thread, text)` posts your answer into the thread, where it
   appears under their comment. Reply to every thread you acted on.
4. Commit. See below; this step is not optional.
5. `review_refresh` picks up the new commit as the next patchset and carries
   the comments onto it. Their tab reloads itself.
6. `review_resolve(thread)` marks a thread fully handled. Leave one open if you
   are waiting on them, or if you answered something they may respond to.

Then tell the user you have replied and pushed a new patchset, and wait again.

`review_status` summarises the review at any point: what is being compared,
which patchset is current, how many threads are waiting on you.

## Committing is required

**commitreview reviews commits, not the working tree.** Edits you leave
uncommitted are invisible to the user. The diff looks unchanged and it appears
you did nothing.

```bash
git add -A && git commit -m "..."
```

then call `review_refresh`. If it reports "No new commit", you have not
committed yet.

A new commit and an amend both work. Prefer a new commit per review round so
the rounds stay legible as separate patchsets, unless the user wants history
kept tidy.

## Writing replies

- Answer the question that was asked. If they asked why, explain rather than
  silently changing the code.
- Be specific about what you changed.
- If you disagree, say so with your reasoning rather than complying silently.
  The thread is a conversation.
- If you could not do something, say that plainly rather than resolving the
  thread.
- Never copy secrets, tokens, passwords, API keys, or other credential-like
  material out of the diff into a reply.

## Constraints

- Only works inside a git repository, and only reviews commits.
- Comments on lines you delete are not lost. They are marked *not in this
  patchset* and stay readable against the commit they were raised on. That is
  normal, and usually confirms a requested removal landed.
''';
