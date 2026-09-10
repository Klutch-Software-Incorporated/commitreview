import 'dart:convert';
import 'dart:io';

import 'anchor.dart';
import 'doc.dart';
import 'git.dart';
import 'markdown.dart';
import 'mcp.dart';
import 'model.dart';

/// Set when the browser asks the server to stop; the accept loop checks it
/// after finishing the request so the response still gets flushed.
bool _stop = false;

/// Opaque per-run id handed back on the MCP transport.
final _sid = DateTime.now().microsecondsSinceEpoch.toRadixString(16);

void launch(String url) {
  try {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else {
      Process.run('xdg-open', [url]);
    }
  } catch (_) {/* browser is a convenience, not a requirement */}
}

Future<Map<String, dynamic>> readJson(HttpRequest req) async {
  final raw = await utf8.decoder.bind(req).join();
  if (raw.trim().isEmpty) return {};
  return (jsonDecode(raw) as Map).cast<String, dynamic>();
}

Future<void> sendJson(HttpResponse r, Object o) async {
  r.headers.contentType = ContentType.json;
  r.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  r.write(jsonEncode(o));
  await r.close();
}

Future<void> route(HttpRequest req, Session s, Doc doc) async {
  final r = req.response;
  final p = req.uri.path;

  // Already bound to loopback; this additionally stops a hostile page in the
  // user's browser from driving the server via DNS rebinding.
  final origin = req.headers.value('origin');
  if (origin != null &&
      !origin.startsWith('http://127.0.0.1') &&
      !origin.startsWith('http://localhost')) {
    r.statusCode = HttpStatus.forbidden;
    await r.close();
    return;
  }

  if (p == '/mcp') {
    if (req.method == 'DELETE') {
      r.statusCode = HttpStatus.noContent;
      await r.close();
      return;
    }
    if (req.method != 'POST') {
      // No server-initiated SSE stream, so refusing GET is legal.
      r.statusCode = HttpStatus.methodNotAllowed;
      await r.close();
      return;
    }
    final decoded = jsonDecode(await utf8.decoder.bind(req).join());
    final batch = decoded is List ? decoded : [decoded];
    final out = <Map<String, dynamic>>[];
    for (final m in batch.cast<Map<String, dynamic>>()) {
      final res = rpc(m, s, doc);
      if (res != null) out.add(res);
    }
    r.headers.set('Mcp-Session-Id', _sid);
    if (out.isEmpty) {
      r.statusCode = HttpStatus.accepted;
      await r.close();
      return;
    }
    await sendJson(r, decoded is List ? out : out.first);
    return;
  }

  if (p == '/state') {
    await sendJson(r, {
      'target': doc.label,
      'version': doc.version,
      'patchset': doc.target.head.n,
      'patchsets': doc.target.patchsets.length,
      'sha': doc.target.head.short,
      'subject': doc.target.head.subject,
      'dirty': doc.target.dirty,
      'threads': s.threads.map((t) {
        final idx = doc.locate(t);
        return t.toJson()
          ..['where'] = t.where
          // The client still positions cards by raw diff index; it just is not
          // what the thread is anchored to any more.
          ..['idx'] = idx ?? -1
          ..['outdated'] = idx == null
          ..['stale'] = t.changed
          ..['raisedOnShort'] = shortSha(t.raisedOn);
      }).toList(),
    });
    return;
  }

  if (req.method == 'POST') {
    final b = await readJson(req);
    switch (p) {
      case '/comment':
        final idx = (b['idx'] as num?)?.toInt();
        final text = (b['text'] as String?)?.trim() ?? '';
        if (idx == null || idx < 0 || idx >= doc.lines.length || text.isEmpty) {
          r.statusCode = HttpStatus.badRequest;
          await r.close();
          return;
        }
        // Structural rows (hunk headers, file headers) carry no line number,
        // so there is nothing to anchor a comment to.
        final c = doc.coordsOf(idx);
        if (c == null) {
          r.statusCode = HttpStatus.badRequest;
          await r.close();
          return;
        }
        // Always a new conversation: one line can have several distinct
        // problems worth raising separately. Follow-ups go to /reply.
        final t = s.create(doc.target.head.sha, c.file, c.side, c.line);
        final snap = snapshotAt(doc.lines, idx);
        t.snap = snap.snap;
        t.snapAt = snap.at;
        t.msgs.add(Msg('user', text, now()));
        s.save();
        break;
      case '/reply':
        final t = s.byId((b['id'] as num?)?.toInt() ?? -1);
        final text = (b['text'] as String?)?.trim() ?? '';
        if (t == null || text.isEmpty) {
          r.statusCode = HttpStatus.badRequest;
          await r.close();
          return;
        }
        t.msgs.add(Msg('user', text, now()));
        t.resolved = false;
        s.save();
        break;
      case '/edit':
        final t = s.byId((b['id'] as num?)?.toInt() ?? -1);
        final mi = (b['mi'] as num?)?.toInt() ?? -1;
        final text = (b['text'] as String?)?.trim() ?? '';
        if (t == null || mi < 0 || mi >= t.msgs.length || text.isEmpty) {
          r.statusCode = HttpStatus.badRequest;
          await r.close();
          return;
        }
        final old = t.msgs[mi];
        t.msgs[mi] = Msg(old.role, text, old.at);
        if (t.delivered > mi) t.delivered = mi; // re-deliver the edited text
        s.save();
        break;
      case '/delete':
        s.threads
            .removeWhere((t) => t.id == ((b['id'] as num?)?.toInt() ?? -1));
        s.save();
        break;
      case '/resolve':
      case '/unresolve':
        final t = s.byId((b['id'] as num?)?.toInt() ?? -1);
        if (t == null) {
          r.statusCode = HttpStatus.notFound;
          await r.close();
          return;
        }
        t.resolved = p == '/resolve';
        s.save();
        break;
      case '/refresh':
        refreshReview(s, doc);
        break;
      case '/shutdown':
        _stop = true;
        break;
      default:
        r.statusCode = HttpStatus.notFound;
        await r.close();
        return;
    }
    r.statusCode = HttpStatus.noContent;
    await r.close();
    return;
  }

  // A page load is the other natural moment to notice a new commit.
  if (p == '/') refreshReview(s, doc);
  r.headers.contentType = ContentType.html;
  // The URL never changes, so without this a reload can legitimately be
  // answered from cache and look like the rebuild did nothing.
  r.headers.set(HttpHeaders.cacheControlHeader, 'no-store, must-revalidate');
  r.write(doc.html);
  await r.close();
}

Future<void> serve(
    String repo, int port, bool open, Doc doc, String? outPath) async {
  final target = doc.target;
  final store = storeFor(repoRoot(repo));
  final s = Session(store, target.base)..load();
  s.target = target;

  // HEAD may have moved between runs; carry threads across before serving.
  final prior = target.patchsets.length > 1
      ? target.patchsets[target.patchsets.length - 2].sha
      : null;
  if (s.threads.isNotEmpty && prior != null) {
    stderr.writeln('review: ${s.advance(target, prior, target.head.sha)}');
  }
  doc.rebuild();
  s.save();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final url = 'http://127.0.0.1:${server.port}';
  stderr.writeln('review: $url  ${doc.label}  '
      '(${doc.lines.length} diff lines)');
  stderr.writeln('review: patchset ${target.head.n} ${target.head.short} '
      '"${target.head.subject}"');
  stderr.writeln('review: MCP endpoint $url/mcp');
  stderr.writeln('review: threads -> ${store.path}');
  if (target.dirty) {
    stderr.writeln('review: note — uncommitted changes are NOT reviewed; '
        'commit them and refresh to see them.');
  }
  if (open) launch(url);

  await for (final req in server) {
    try {
      await route(req, s, doc);
    } catch (e) {
      stderr.writeln('review: ${req.uri.path} failed: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {/* already closed */}
    }
    if (_stop) break;
  }
  await server.close(force: true);

  final md = transcript(s, doc);
  stdout.write(md);
  if (outPath != null) File(outPath).writeAsStringSync(md);
}
