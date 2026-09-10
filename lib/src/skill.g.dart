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

First, check whether one is already running for this repository. Servers
self-identify at `/whoami`, and the port is not fixed: the default is 4970, but
a busy port is skipped.

```bash
for p in $(seq 4970 4990); do curl -s -m 1 "http://127.0.0.1:$p/whoami"; echo; done
```

Each answer includes `url`, `pid`, `repo`, `target` and `patchset`. If one
already covers this repository, use it and give the user its URL. Never start a
second server for a repository that already has one, and never stop a server
the user started.

If none is running, start one in the background from the repository root. First
pick the command, `<cr>` below, since how it is installed varies:

- `commitreview`, if it resolves.
- `commitreview.bat` on Windows when you are running through a POSIX shell.
  `dart pub global activate` installs a `.bat` shim, which is on `PATH` but
  which bash will not find without the extension.
- `dart pub global run commitreview` otherwise. Always works if the package is
  activated, just slower to start.
- `./commitreview.exe` or `dart run bin/commitreview.dart` when working from a
  clone.

```bash
<cr> > /tmp/commitreview.log 2>&1 &
sleep 2
grep -m1 'http://' /tmp/commitreview.log
```

- With no argument it reviews the latest commit (`HEAD~1..HEAD`).
- With a ref it reviews everything since that ref, e.g. `<cr> main` for a whole
  branch.

Pick the one that matches what the user wants reviewed. If you have made
several commits they have not seen, a base ref covering them all is usually
better than just the last one.

If the log is empty after a couple of seconds, wait and check again, since a
first run compiles. If it reports an error, show it to the user rather than
retrying blindly.

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
