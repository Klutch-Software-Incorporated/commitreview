---
name: commitreview
description: Work through a code review the user has left in commitreview, a local commit-based review tool. Use when the user says they have left comments, asks you to check or read the review, refers to a review thread, or names commitreview. Also use when the user asks you to open your work for review. Do not use it for ordinary requests to review code, diffs, commits, branches, or pull requests — answer those normally.
---

# commitreview

A local review tool where the user comments on a commit's diff in their
browser and you answer inline. Each commit is a **patchset**; comments are
carried onto later commits by git, so the conversation survives your changes.

## When to use this skill

Use it when the user:

- says they have left comments, or asks you to check / read / look at the
  review
- refers to a review thread, or to something they marked in the review
- names commitreview
- asks you to open your work for review (see *Starting a review* below)

Do **not** use it for ordinary requests like "review these changes" or "find
problems in this diff". Those are answered normally, in conversation.

## Reaching the server

The user runs a long-running server, usually on port 4970. There are two ways
to talk to it, and which one is available depends on when the server started.

**Preferred — MCP tools.** If tools named `review_pending`, `review_reply`,
`review_resolve`, `review_refresh` and `review_status` are available, use
them directly.

**Fallback — HTTP.** MCP clients connect once, at session start, so if the
server was started *after* this session began, those tools will not exist.
The MCP endpoint is plain HTTP and works identically over curl:

```bash
call() {  # call <tool> '<json-args>'
  curl -s -X POST http://127.0.0.1:4970/mcp -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}"
}

call review_pending '{}'
call review_reply '{"thread":3,"text":"Fixed — see the new commit."}'
call review_resolve '{"thread":3}'
call review_refresh '{}'
```

Pass `{}` explicitly for tools that take no arguments. The reply is JSON-RPC;
the part you want is at `.result.content[0].text`:

```bash
call review_pending '{}' | python -c \
  "import json,sys; print(json.load(sys.stdin)['result']['content'][0]['text'])"
```

`curl -s http://127.0.0.1:4970/state` returns the raw thread list as JSON if
you want to inspect it directly.

Check the port before assuming 4970: the user may have started it with
`--port`. If nothing answers, say so rather than guessing — do not start a
server on their behalf unless they ask.

## The loop

1. **`review_pending`** — returns every thread with a new comment, each with
   its diff context, real `file:line`, and full message history. Threads you
   have already seen are not repeated.
2. **Address each thread.** Some ask for a change. Some ask a question and
   want an answer, not an edit — read carefully before editing anything.
3. **`review_reply(thread, text)`** — post your answer into the thread. It
   appears inline under the user's comment in their browser. Reply to every
   thread you acted on, briefly, saying what you did or answering what was
   asked.
4. **Commit your changes.** See below — this step is not optional.
5. **`review_refresh`** — picks up the new commit as the next patchset and
   carries the comments onto it. The user's tab reloads itself.
6. **`review_resolve(thread)`** — mark threads that are fully handled. Leave
   a thread open if you are still waiting on the user, or if you answered a
   question they may want to respond to.

`review_status` summarises the review: what is being compared, which patchset
is current, how many threads are waiting on you, and whether uncommitted work
exists.

## Committing is required

**commitreview reviews commits, not the working tree.** Edits you leave
uncommitted are invisible to the user — the diff will look unchanged and it
will appear that you did nothing.

So, after making changes:

```bash
git add -A && git commit -m "..."
```

then call `review_refresh`.

Either a new commit or an amend works; the tool treats both as the next
patchset. Prefer a **new commit per review round**, so the rounds stay legible
as separate patchsets. If the user has asked you to keep history tidy, amend
instead.

If `review_refresh` reports "No new commit", you have not committed yet.

## Starting a review

Only when the user asks you to open your work for review, and only if no
server is already running:

```bash
commitreview          # the latest commit (HEAD~1..HEAD)
commitreview main     # everything since main
```

It is long-running and opens a browser tab, so treat starting it as explicit
opt-in. Run it in the background, tell the user the URL, and let them drive.
Never start a second server for a repository that already has one, and never
stop a server the user started.

Note that the MCP tools will not be available in the current session for a
server started this way; use the HTTP fallback above.

## Writing replies

- Answer the question that was asked. If the user asked *why*, explain — do
  not silently change the code instead.
- Be specific about what you changed, and name the commit if it helps.
- If you disagree, say so with your reasoning rather than complying silently;
  the thread is a conversation.
- If you could not do something, say that plainly in the reply rather than
  resolving the thread.
- Never copy secrets, tokens, passwords, API keys, or other credential-like
  material out of the diff into a reply.

## Constraints

- Only works inside a git repository.
- Comments on lines you delete are not lost — they are marked *not in this
  patchset* and stay readable against the commit they were raised on. That is
  normal, and usually confirms a requested removal landed.
