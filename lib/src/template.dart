/// The single-page UI, substituted into by [buildHtml].
library;

const pageTemplate =
    r'''<!doctype html><meta charset="utf-8"><title>commitreview</title>
<!-- assets/commitreview-icon.svg, inlined so the page stays self-contained.
     The artwork's stroke is a fixed dark navy, which disappears against a dark
     browser chrome, so the favicon carries its own colour-scheme rule. -->
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 256 256'%3E%3Cstyle%3E*%7Bstroke:%23182230%7D@media(prefers-color-scheme:dark)%7B*%7Bstroke:%23c9d1d9%7D%7D%3C/style%3E%3Cpath d='M48 36h160a20 20 0 0 1 20 20v112a20 20 0 0 1-20 20h-54l-34 32v-32H48a20 20 0 0 1-20-20V56a20 20 0 0 1 20-20Z' fill='none' stroke-width='18' stroke-linejoin='round'/%3E%3Cpath d='M64 112h48m32 0h48' fill='none' stroke-width='18' stroke-linecap='round'/%3E%3Ccircle cx='128' cy='112' r='24' fill='%2335B67A' stroke-width='14'/%3E%3C/svg%3E">
<style>
/* Light is the base palette; dark overrides follow. Three states: no
   data-theme = follow the OS, data-theme=light/dark = pinned by the button. */
:root{
  --bg:#ffffff;--fg:#1f2328;--mut:#656d76;--bd:#d0d7de;--pan:#f6f8fa;
  --acc:#0969da;--warn:#bf8700;--hov:#eef1f4;
  --add:#e6ffec;--del:#ffebe9;--hunk:#ddf4ff;--hunkfg:#0550ae;--hdr:#57606a;
  --empty:#f6f8fa;--cm:#fff8c5;--cmh:#fff1b8;--ta:#ffffff;
  --btn:#1f883d;--gbtn:#f6f8fa;
  --dbg:#ffebe9;--dfg:#cf222e;--dbd:#ffcecb;
  --hh:53px;            /* header height; sticky offsets key off this */
  --pls:#1a7f37;--mis:#cf222e;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#0d1117;--fg:#c9d1d9;--mut:#6e7681;--bd:#30363d;--pan:#161b22;
    --acc:#58a6ff;--warn:#d29922;--hov:#1f2937;
    --add:#0f2f1b;--del:#3d1418;--hunk:#12233d;--hunkfg:#79c0ff;--hdr:#8b949e;
    --empty:#090c10;--cm:#1c2128;--cmh:#22272e;--ta:#0d1117;
    --btn:#238636;--gbtn:#21262d;
    --dbg:#3d1418;--dfg:#ff9492;--dbd:#6e2b30;
  }
}
:root[data-theme="dark"]{
  --bg:#0d1117;--fg:#c9d1d9;--mut:#6e7681;--bd:#30363d;--pan:#161b22;
  --acc:#58a6ff;--warn:#d29922;--hov:#1f2937;
  --add:#0f2f1b;--del:#3d1418;--hunk:#12233d;--hunkfg:#79c0ff;--hdr:#8b949e;
  --empty:#090c10;--cm:#1c2128;--cmh:#22272e;--ta:#0d1117;
  --btn:#238636;--gbtn:#21262d;
  --dbg:#3d1418;--dfg:#ff9492;--dbd:#6e2b30;
  --pls:#3fb950;--mis:#f85149;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:13px/1.5 ui-monospace,"Cascadia Mono",Consolas,monospace}
header{position:sticky;top:0;z-index:5;background:var(--pan);border-bottom:1px solid var(--bd);
  padding:10px 16px;display:flex;gap:14px;align-items:center}
header .t{color:var(--mut)} header b{color:var(--fg)} .sp{flex:1}
/* The mark takes its stroke from the header text, so it reads in either
   theme; only the commit node keeps a fixed colour. */
#logo{width:18px;height:18px;flex:none;color:var(--fg)}
button{background:var(--btn);color:#fff;border:0;padding:7px 14px;border-radius:6px;cursor:pointer;font:inherit}
button.g{background:var(--gbtn);color:var(--fg);border:1px solid var(--bd)}
button.sm{font-size:12px;padding:4px 9px;color:var(--mut)}
button.sm:hover{color:var(--dfg);border-color:var(--dbd)}
button.dgr{background:var(--dbg);color:var(--dfg);border:1px solid var(--dbd)}
button:hover{filter:brightness(.96)}
#uni,#spl{padding-bottom:200px}
body.uni #spl,body.spl #uni{display:none}
/* layout: sticky file tree beside the diff */
#wrap{display:flex;align-items:flex-start}
#main{flex:1;min-width:0}
#tree{position:sticky;top:var(--hh);flex:none;width:262px;
  max-height:calc(100vh - var(--hh));overflow:auto;
  border-right:1px solid var(--bd);padding:10px 0 24px;background:var(--bg)}
#tree.hide{display:none}
#tree ul{list-style:none;margin:0;padding-left:13px}
#tree>ul{padding-left:6px}
#tree .dn{display:flex;gap:5px;align-items:center;color:var(--mut);
  padding:2px 8px;cursor:pointer;user-select:none;white-space:nowrap}
#tree .dn:hover{color:var(--fg)}
#tree .ar{display:inline-block;transition:transform .12s}
#tree li.dir:not(.open)>ul{display:none}
#tree li.dir:not(.open)>.dn .ar{transform:rotate(-90deg)}
#tree .fl{display:flex;gap:6px;align-items:center;padding:2px 8px;
  cursor:pointer;border-radius:5px;white-space:nowrap}
#tree .fl:hover{background:var(--hov)}
#tree .fl.sel{background:var(--hov);box-shadow:inset 2px 0 0 var(--acc)}
#tree .fn{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
#tree .fl.vd .fn{color:var(--mut);text-decoration:line-through}
#tree .badge{background:var(--warn);color:#fff;border-radius:9px;
  padding:0 6px;font-size:11px;font-style:normal}
.st{font-size:11px;font-style:normal;display:flex;gap:5px}
.st .pl{color:var(--pls);font-style:normal}
.st .mi{color:var(--mis);font-style:normal}
/* per-file sections */
section.fs{border-top:1px solid var(--bd)}
.fh{position:sticky;top:var(--hh);z-index:3;display:flex;gap:12px;align-items:center;
  background:var(--pan);border-bottom:1px solid var(--bd);padding:6px 16px}
.fp{font-weight:700;flex:1;min-width:0;overflow:hidden;
  text-overflow:ellipsis;white-space:nowrap}
.vw{display:flex;gap:5px;align-items:center;cursor:pointer;
  color:var(--mut);font-size:12px;user-select:none}
.vw input{cursor:pointer;margin:0}
.vw input:disabled,.vw:has(input:disabled){cursor:not-allowed;opacity:.5}
section.fs.vd .fb{display:none}
section.fs.vd .fp{color:var(--mut);text-decoration:line-through}
.l,.r,section.fs{scroll-margin-top:calc(var(--hh) + 32px)}
.l{display:flex;white-space:pre;cursor:pointer}
.l:hover .t{background:var(--hov)}
.ln{width:58px;flex:none;text-align:right;padding-right:12px;color:var(--mut);user-select:none}
.t{flex:1;padding-right:16px}
.a{background:var(--add)}.d{background:var(--del)}
.k{background:var(--hunk);color:var(--hunkfg)}.h{color:var(--hdr);font-weight:700}
.has .t{box-shadow:inset 3px 0 0 var(--warn)}
/* split view */
.r{display:flex;align-items:stretch}
.r.full{display:block}
.c{flex:1 1 50%;min-width:0;overflow-x:auto}
.c.e{background:var(--empty)}
.r>.c:first-child{border-right:1px solid var(--bd)}
/* comments — an inset conversation card, GitHub style */
.ed{margin:10px 16px 10px 58px;border:1px solid var(--acc);border-radius:6px;
  background:var(--pan);padding:10px 12px}
.btns{margin-top:8px;display:flex;gap:8px;align-items:center}
textarea{width:100%;height:78px;background:var(--ta);color:var(--fg);border:1px solid var(--bd);
  border-radius:6px;padding:8px;font:13px/1.5 ui-monospace,"Cascadia Mono",Consolas,monospace;
  resize:vertical;box-sizing:border-box}

.cm{margin:10px 16px 10px 58px;border:1px solid var(--bd);border-radius:6px;
  background:var(--bg);overflow:hidden}
.cm.rs{opacity:.8}

.ch{display:flex;align-items:center;gap:8px;padding:7px 12px;background:var(--pan);
  border-bottom:1px solid var(--bd);color:var(--mut);font-size:12px;
  cursor:pointer;user-select:none}
.ch:hover{color:var(--fg)}
.cv{display:inline-block;transition:transform .12s;font-size:10px}
.cm.co .cv{transform:rotate(-90deg)}
.cm.co .mg,.cm.co .cf{display:none}
.cm.co .ch{border-bottom:0}
.ch .cn{margin-left:auto}
.ch .tag{border:1px solid var(--bd);border-radius:999px;padding:1px 8px;font-size:11px}
.cm.rs .ch .tag{border-color:var(--pls);color:var(--pls)}

.mg{padding:10px 14px;border-top:1px solid var(--bd)}
.ch + .mg{border-top:0}
.mh{display:flex;align-items:center;gap:8px;margin-bottom:7px;font-size:12px}
.av{width:20px;height:20px;border-radius:50%;flex:none;display:grid;place-items:center;
  font-size:10px;font-weight:700;color:#fff;font-family:system-ui,sans-serif}
.av.u{background:#6e7781}
.av.a{background:var(--acc)}
.mh .who{font-weight:600;color:var(--fg)}
.mh .ago{color:var(--mut)}
.act{margin-left:auto;display:flex;gap:12px;opacity:0;transition:opacity .1s}
.mg:hover .act{opacity:1}
.act span{color:var(--mut);cursor:pointer}
.act span:hover{color:var(--acc);text-decoration:underline}

/* Prose reads as prose; fenced and inline code stay monospace. */
.bd{font:14px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
  color:var(--fg);white-space:pre-wrap;overflow-wrap:anywhere;max-width:84ch}
.bd pre{font:12px/1.45 ui-monospace,"Cascadia Mono",Consolas,monospace;
  background:var(--pan);border:1px solid var(--bd);border-radius:6px;padding:10px 12px;
  margin:8px 0;overflow-x:auto;white-space:pre;max-width:100%;box-sizing:border-box}
.bd code{font:12px ui-monospace,"Cascadia Mono",Consolas,monospace;
  background:var(--pan);border:1px solid var(--bd);border-radius:4px;padding:0 4px}
.bd pre code{background:none;border:0;padding:0;font-size:inherit}

.cf{padding:9px 12px;border-top:1px solid var(--bd);background:var(--pan);
  display:flex;gap:8px;align-items:center}
.cf .rin{flex:1;background:var(--ta);color:var(--mut);border:1px solid var(--bd);
  border-radius:6px;padding:7px 10px;cursor:text;font-size:13px}
.cf .rin:hover{border-color:var(--acc)}
.cf.open{display:block}
.cf button{font-size:12px;padding:5px 10px}
.tag.st{border-color:var(--warn);color:var(--warn)}
pre.snap{font:12px/1.45 ui-monospace,"Cascadia Mono",Consolas,monospace;
  background:var(--pan);border-bottom:1px solid var(--bd);margin:0;
  padding:8px 12px;overflow-x:auto;white-space:pre;color:var(--mut)}
pre.snap .at{background:var(--cm);color:var(--fg);display:inline-block;
  min-width:100%}
#outd{margin:12px 16px 0;border:1px solid var(--bd);border-radius:6px;overflow:hidden}
#outd.empty{display:none}
#outd .oh{padding:8px 12px;background:var(--pan);color:var(--mut);font-size:12px;
  cursor:pointer;user-select:none;display:flex;gap:8px;align-items:center}
#outd .oh:hover{color:var(--fg)}
#outd.co .ob{display:none}
#outd.co .cv{transform:rotate(-90deg)}
#outd .ob{border-top:1px solid var(--bd);padding:2px 0}
#outd .cm{margin:10px 12px}
#pill.warn{color:var(--acc);font-weight:600}
#rl{position:sticky;top:var(--hh);z-index:5;background:var(--hunk);
  color:var(--hunkfg);border-bottom:1px solid var(--bd);padding:8px 16px}
#rl button{font-size:12px;padding:3px 9px;margin:0 2px}
</style>
<header>
  <svg id="logo" viewBox="0 0 256 256" aria-hidden="true">
    <path d="M48 36h160a20 20 0 0 1 20 20v112a20 20 0 0 1-20 20h-54l-34 32v-32H48a20 20 0 0 1-20-20V56a20 20 0 0 1 20-20Z"
      fill="none" stroke="currentColor" stroke-width="18" stroke-linejoin="round"/>
    <path d="M64 112h48m32 0h48" fill="none" stroke="currentColor" stroke-width="18" stroke-linecap="round"/>
    <circle cx="128" cy="112" r="24" fill="#35B67A" stroke="currentColor" stroke-width="14"/>
  </svg>
  <b>commitreview</b><span class="t">__TARGET__</span>
  <span class="t" id="ps" title="Each commit reviewed is a patchset"></span>
  <span class="t"><span id="vn">0/0</span> viewed</span>
  <span class="sp"></span>
  <button class="g" id="fb" title="Show / hide the file tree">Files</button>
  <button class="g" id="tb" title="Toggle light / dark">&#9789;</button>
  <button class="g" id="vb">Split</button>
  <span class="t"><span id="n">0</span> comment(s)</span>
  <span class="t" id="pill"></span>
  <button class="g sm" id="sb"
    title="Shut the review server down and disconnect its MCP tools">Stop server</button>
</header>
<div id="rl" hidden>The diff changed &mdash; <button id="rlb">reload</button>
  to see it. Your draft will be lost.</div>
<div id="wrap">
  <aside id="tree">__TREE__</aside>
  <main id="main">
    <div class="hint">Click any line to comment. Claude reads them with review_pending and replies inline &mdash; tell it to check the review when you are ready. Ctrl+Enter saves, Esc cancels.</div>
    <div id="outd" class="empty">
      <div class="oh"><span class="cv">&#9662;</span><span class="on"></span></div>
      <div class="ob"></div>
    </div>
    <div id="uni">__UNIFIED__</div>
    <div id="spl">__SPLIT__</div>
  </main>
</div>
<script>
let T = [];                       // threads, owned by the server
const VERSION = __VERSION__;      // bumps whenever the diff is rebuilt
const uni = document.getElementById('uni'), spl = document.getElementById('spl');

// In split view a comment attaches below the whole row, not one half of it.
const hostFor = el => el.closest('.r') || el;

async function post(path, body){
  await fetch(path, {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body || {})
  });
}

// The diff itself may have been rebuilt under us; if so the whole page is
// stale, and reloading is simpler and safer than patching it in place.
function applyState(j){
  if (j.version !== VERSION) { location.reload(); return false; }
  T = j.threads;
  showPatchset(j);
  render();
  return true;
}

// Commits are the unit of review, so which one you are looking at matters.
function showPatchset(j){
  const ps = document.getElementById('ps');
  if (!ps || !j.patchset) return;
  ps.textContent = 'patchset ' + j.patchset + '/' + j.patchsets +
      ' · ' + j.sha + (j.subject ? ' · ' + j.subject : '');
  ps.title = j.dirty
    ? 'There is uncommitted work, which is not part of the review. '
      + 'Commit it, then refresh.'
    : 'Each commit reviewed is a patchset';
  ps.className = 't' + (j.dirty ? ' warn' : '');
}

async function refresh(){
  applyState(await (await fetch('/state', {cache: 'no-store'})).json());
}

// Poll for replies the agent posted. Never while an editor is open, or we
// would yank half-typed text out from under the user.
async function pull(){
  try {
    const j = await (await fetch('/state', {cache: 'no-store'})).json();
    const drafting = !!document.querySelector('textarea');
    if (j.version !== VERSION) {
      // Reloading would throw away whatever is half-typed, so offer it
      // instead of doing it. Silently skipping looked like a broken refresh.
      if (drafting) { document.getElementById('rl').hidden = false; return; }
      location.reload();
      return;
    }
    if (drafting) return;                        // never clobber a draft
    showPatchset(j);
    if (JSON.stringify(j.threads) === JSON.stringify(T)) return;
    T = j.threads;
    render();
  } catch (e) {/* server gone; keep showing what we have */}
}

const collapsed = {};   // thread id -> hidden, view-only state

function ago(iso){
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  return Math.floor(s / 86400) + 'd ago';
}

// Inline `code` spans, built as nodes so message text is never parsed as HTML.
function inlineCode(parent, s){
  const re = /`([^`\n]+)`/g;
  let last = 0, m;
  while ((m = re.exec(s))) {
    if (m.index > last) parent.appendChild(document.createTextNode(s.slice(last, m.index)));
    const c = document.createElement('code');
    c.textContent = m[1];
    parent.appendChild(c);
    last = re.lastIndex;
  }
  if (last < s.length) parent.appendChild(document.createTextNode(s.slice(last)));
}

function mkBody(text){
  const d = document.createElement('div');
  d.className = 'bd';
  const parts = text.split('```');
  parts.forEach((p, k) => {
    if (k % 2) {
      const pre = document.createElement('pre');
      pre.textContent = p.replace(/^[a-zA-Z0-9_+-]*\n/, '').replace(/\n$/, '');
      d.appendChild(pre);
    } else {
      if (k > 0) p = p.replace(/^\n/, '');
      if (k < parts.length - 1) p = p.replace(/\n$/, '');
      if (p) inlineCode(d, p);
    }
  });
  return d;
}

function mkBtn(label, cls){
  const b = document.createElement('button');
  b.textContent = label;
  if (cls) b.className = cls;
  return b;
}

// Swap a container's contents for a textarea + Save/Cancel, then restore.
function composer(host, initial, placeholder, onSave, onDone){
  const keep = [...host.childNodes];
  host.textContent = '';
  const ta = document.createElement('textarea');
  ta.value = initial;
  ta.placeholder = placeholder;
  const row = document.createElement('div');
  row.className = 'btns';
  const save = mkBtn('Save'), cancel = mkBtn('Cancel', 'g');
  row.append(save, cancel);
  host.append(ta, row);
  const restore = () => {
    host.textContent = '';
    keep.forEach(n => host.appendChild(n));
    if (onDone) onDone();
  };
  cancel.onclick = restore;
  save.onclick = async () => {
    const v = ta.value.trim();
    if (!v) return restore();
    await onSave(v);
    if (onDone) onDone();   // tear down like Cancel does
    await refresh();
  };
  ta.onkeydown = e => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) save.click();
    if (e.key === 'Escape') restore();
  };
  ta.focus();
  ta.setSelectionRange(ta.value.length, ta.value.length);
}

function mkCard(t){
  const c = document.createElement('div');
  c.className = 'cm' + (t.resolved ? ' rs' : '') + (collapsed[t.id] ? ' co' : '');
  c.dataset.i = t.idx;

  const h = document.createElement('div');
  h.className = 'ch';
  const cv = document.createElement('span');
  cv.className = 'cv';
  cv.textContent = '\u25BE';
  const where = document.createElement('span');
  where.textContent = (t.outdated ? 'Was on ' : 'Comment on ') +
      (t.where || 'this line');
  h.append(cv, where);
  if (t.resolved) {
    const tag = document.createElement('span');
    tag.className = 'tag';
    tag.textContent = 'Resolved';
    h.appendChild(tag);
  }
  if (t.outdated || t.stale) {
    const tag = document.createElement('span');
    tag.className = 'tag st';
    tag.textContent = t.outdated ? 'Not in this patchset' : 'Line edited';
    tag.title = t.outdated
      ? 'This line is not part of the current patchset. The comment is kept, '
        + 'shown against the code as it was on patchset ' + t.raisedOnShort + '.'
      : 'Git carried this comment across an edit to its line';
    h.appendChild(tag);
  }
  const cn = document.createElement('span');
  cn.className = 'cn';
  cn.textContent = t.msgs.length + (t.msgs.length === 1 ? ' comment' : ' comments');
  h.appendChild(cn);
  h.onclick = () => { collapsed[t.id] = !collapsed[t.id]; render(); };
  c.appendChild(h);

  // An outdated thread has no line to sit under, so it carries the slice of
  // diff as it looked when the comment was written.
  if (t.outdated && t.snap) {
    const pre = document.createElement('pre');
    pre.className = 'snap';
    t.snap.forEach((l, k) => {
      const row = document.createElement(k === t.snapAt ? 'span' : 'span');
      if (k === t.snapAt) row.className = 'at';
      row.textContent = l + '\n';
      pre.appendChild(row);
    });
    c.appendChild(pre);
  }

  t.msgs.forEach((m, k) => {
    const g = document.createElement('div');
    g.className = 'mg';
    const bh = document.createElement('div');
    bh.appendChild(mkBody(m.text));
    const mh = document.createElement('div');
    mh.className = 'mh';
    const av = document.createElement('span');
    av.className = 'av ' + (m.role === 'ai' ? 'a' : 'u');
    av.textContent = m.role === 'ai' ? 'C' : 'Y';
    const who = document.createElement('span');
    who.className = 'who';
    who.textContent = m.role === 'ai' ? 'claude' : 'you';
    const when = document.createElement('span');
    when.className = 'ago';
    when.textContent = ago(m.at);
    mh.append(av, who, when);

    if (m.role !== 'ai') {
      const act = document.createElement('span');
      act.className = 'act';
      const ed = document.createElement('span');
      ed.textContent = 'Edit';
      ed.onclick = () => composer(bh, m.text, 'Edit this comment…',
          v => post('/edit', {id: t.id, mi: k, text: v}));
      act.appendChild(ed);
      mh.appendChild(act);
    }
    g.append(mh, bh);
    c.appendChild(g);
  });

  const f = document.createElement('div');
  f.className = 'cf';
  const rin = document.createElement('div');
  rin.className = 'rin';
  rin.textContent = 'Write a reply\u2026';
  rin.onclick = () => {
    f.classList.add('open');
    composer(f, '', 'Write a reply…',
        v => post('/reply', {id: t.id, text: v}),
        () => f.classList.remove('open'));
  };
  const res = mkBtn(t.resolved ? 'Reopen' : 'Resolve', 'g');
  res.onclick = async () => {
    await post(t.resolved ? '/unresolve' : '/resolve', {id: t.id});
    await refresh();
  };
  const del = mkBtn('Delete', 'dgr');
  del.onclick = async () => { await post('/delete', {id: t.id}); await refresh(); };
  f.append(rin, res, del);
  c.appendChild(f);
  return c;
}

// A fresh comment on a line that has no thread yet.
function compose(i){
  document.querySelectorAll('.ed').forEach(n => n.remove());
  const active = document.body.classList.contains('spl') ? spl : uni;
  const el = active.querySelector('.l[data-i="' + i + '"]');
  if (!el) return;
  const ed = document.createElement('div');
  ed.className = 'ed';
  const host = hostFor(el);
  let at = host;
  for (let n = host.nextElementSibling;
       n && n.classList.contains('cm') && n.dataset.i === String(i);
       n = n.nextElementSibling) {
    at = n;
  }
  at.after(ed);
  composer(ed, '', 'Leave a comment\u2026',
      v => post('/comment', {idx: +i, text: v}),
      () => ed.remove());
}

document.addEventListener('click', e => {
  if (e.target.closest('.cm') || e.target.closest('.ed')) return;
  const l = e.target.closest('.l');
  if (!l || l.dataset.i === undefined) return;
  compose(l.dataset.i);   // a new conversation; replies live on each card
});

// ---- file tree + per-file "viewed" state ----
const FILES = [...document.querySelectorAll('#tree .fl')].map(li => ({
  f: li.dataset.f, from: +li.dataset.from, to: +li.dataset.to, li
}));
const viewed = {};

const inFile = f =>
  T.filter(t => !t.outdated && t.idx >= f.from && t.idx <= f.to);
const commentsIn = f => inFile(f).length;
const openIn = f => inFile(f).filter(t => !t.resolved).length;

function applyFiles(){
  let nv = 0;
  for (const f of FILES) {
    const n = commentsIn(f), o = openIn(f);
    if (o > 0) viewed[f.f] = false;   // an unresolved thread can't stay collapsed
    const on = !!viewed[f.f];
    if (on) nv++;
    document.querySelectorAll('section.fs[data-f="' + f.f + '"]').forEach(s => {
      s.classList.toggle('vd', on);
      const cb = s.querySelector('.vw input');
      cb.checked = on;
      cb.disabled = o > 0;
      cb.closest('.vw').title = o > 0
        ? 'Has unresolved comments — resolve them before marking viewed'
        : 'Collapse this file as reviewed';
    });
    f.li.classList.toggle('vd', on);
    const b = f.li.querySelector('.badge');
    b.textContent = n;
    b.hidden = n === 0;
  }
  document.getElementById('vn').textContent = nv + '/' + FILES.length;
}

for (const f of FILES) {
  f.li.onclick = () => {
    document.querySelectorAll('#tree .fl.sel').forEach(n => n.classList.remove('sel'));
    f.li.classList.add('sel');
    const active = document.body.classList.contains('spl') ? spl : uni;
    const s = active.querySelector('section.fs[data-f="' + f.f + '"]');
    if (s) s.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
}

document.querySelectorAll('#tree .dn').forEach(dn => {
  dn.onclick = () => dn.parentElement.classList.toggle('open');
});

document.addEventListener('change', e => {
  const cb = e.target.closest('.vw input');
  if (!cb) return;
  viewed[cb.closest('section.fs').dataset.f] = cb.checked;
  applyFiles();
});

document.getElementById('fb').onclick = () =>
  document.getElementById('tree').classList.toggle('hide');

document.getElementById('rlb').onclick = () => location.reload();

document.querySelector('#outd .oh').onclick = () =>
  document.getElementById('outd').classList.toggle('co');

// Threads are drawn into BOTH views, so switching views keeps them in place.
function render(){
  document.querySelectorAll('.cm').forEach(n => n.remove());
  document.querySelectorAll('.has').forEach(n => n.classList.remove('has'));
  const outd = document.getElementById('outd');
  const ob = outd.querySelector('.ob');
  ob.textContent = '';
  const tail = new Map();   // host row -> last card placed under it
  let nout = 0;
  for (const t of T) {
    if (t.outdated) { nout++; ob.appendChild(mkCard(t)); continue; }
    const hosts = new Set();
    document.querySelectorAll('.l[data-i="' + t.idx + '"]').forEach(l => {
      l.classList.add('has');
      hosts.add(hostFor(l));
    });
    // Several threads can share a line; keep them in order under it.
    hosts.forEach(h => {
      const card = mkCard(t);
      (tail.get(h) || h).after(card);
      tail.set(h, card);
    });
  }
  outd.classList.toggle('empty', nout === 0);
  outd.querySelector('.on').textContent = nout +
      (nout === 1 ? ' comment not in this patchset' : ' comments not in this patchset');
  document.getElementById('n').textContent = T.length;
  const waiting = T.filter(t =>
    !t.resolved && t.msgs.length && t.msgs[t.msgs.length - 1].role !== 'ai').length;
  const pill = document.getElementById('pill');
  pill.textContent = !T.length ? '' : waiting ? waiting + ' awaiting claude' : 'all answered';
  pill.className = 't' + (waiting ? ' warn' : '');
  applyFiles();
}

function view(v){
  document.body.className = v;
  document.getElementById('vb').textContent = v === 'spl' ? 'Unified' : 'Split';
  try { localStorage.setItem('reviewView', v); } catch (e) {}
  render();
}
document.getElementById('vb').onclick = () =>
  view(document.body.classList.contains('spl') ? 'uni' : 'spl');

let start = '__FORCEVIEW__';
if (!start) { try { start = localStorage.getItem('reviewView'); } catch (e) {} }
view(start === 'spl' ? 'spl' : 'uni');

// Theme: untouched = follow the OS. Once toggled, the choice is pinned.
const tb = document.getElementById('tb');
const sysDark = () => matchMedia('(prefers-color-scheme: dark)').matches;
const isDark = () => (document.documentElement.dataset.theme || (sysDark() ? 'dark' : 'light')) === 'dark';
function paintTb(){ tb.innerHTML = isDark() ? '&#9788;' : '&#9789;'; }

function theme(t){
  document.documentElement.dataset.theme = t;
  try { localStorage.setItem('reviewTheme', t); } catch (e) {}
  paintTb();
}
tb.onclick = () => theme(isDark() ? 'light' : 'dark');

let savedTheme = null;
try { savedTheme = localStorage.getItem('reviewTheme'); } catch (e) {}
if (savedTheme === 'light' || savedTheme === 'dark') theme(savedTheme);
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', paintTb);
paintTb();

const sb = document.getElementById('sb');

// Nothing is "submitted" here: comments post as you write them and Claude
// reads them over MCP. The button only ends the session, so it is demoted
// and guarded rather than sitting there looking like Submit.
sb.onclick = async () => {
  if (!confirm("Stop the review server?\n\nYour comments are saved. This ends the session and disconnects Claude's review tools.")) return;
  await post('/shutdown');
  document.body.innerHTML =
    '<div style="padding:48px;font:15px ui-monospace,monospace">' +
    'Server stopped. You can close this tab.</div>';
};

refresh();
setInterval(pull, 2000);
</script>
''';
