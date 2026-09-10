import 'doc.dart';
import 'git.dart';
import 'markdown.dart';
import 'model.dart';

const protocolVersions = {'2024-11-05', '2025-03-26', '2025-06-18'};

const tools = [
  {
    'name': 'review_pending',
    'description': 'Fetch review comments the user has left in the review UI '
        'that you have not seen yet. Returns markdown: each thread with its '
        'diff context, real file:line, and the full message history. Call '
        'this when the user says they have left comments or asks you to check '
        'the review.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
  },
  {
    'name': 'review_reply',
    'description': 'Post a reply into a review thread. It appears inline under '
        'that comment in the reviewer browser tab. Use this to answer a '
        'question the reviewer asked, or to say what you changed.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'thread': {
          'type': 'integer',
          'description': 'Thread id, as shown by review_pending',
        },
        'text': {'type': 'string', 'description': 'The reply body'},
      },
      'required': ['thread', 'text'],
    },
  },
  {
    'name': 'review_resolve',
    'description': 'Mark a review thread resolved once it is fully handled. '
        'Resolved threads stop showing up in review_pending.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'thread': {'type': 'integer', 'description': 'Thread id'},
      },
      'required': ['thread'],
    },
  },
  {
    'name': 'review_refresh',
    'description': 'Pick up a new commit as the next patchset and rebuild the '
        'review; the reviewer browser reloads itself within a couple of '
        'seconds. Commit your changes first — this reviews commits, not the '
        'working tree, so uncommitted edits will not show up. Open comments '
        'are carried onto the new commit using git own line mapping, so they '
        'stay on the right lines; a comment whose line was deleted is marked '
        'as no longer in the diff, but stays readable against the patchset it '
        'was raised on.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
  },
  {
    'name': 'review_status',
    'description': 'Summarise the review: what is being compared, which '
        'patchset is current, how many threads exist and how many are waiting '
        'on you, and whether there is uncommitted work the review cannot see.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
  },
];

Map<String, dynamic> mcpText(String t, {bool isError = false}) => {
      'content': [
        {'type': 'text', 'text': t}
      ],
      if (isError) 'isError': true,
    };

/// Rebuilds the review if HEAD has moved, carrying threads across. Shared by
/// the MCP tool and the browser's refresh endpoint.
String refreshReview(Session s, Doc doc) {
  final from = doc.target.poll();
  if (from == null) {
    doc.rebuild();
    final hint = doc.target.dirty
        ? ' There is uncommitted work: commit it, then call review_refresh '
            'again to review it.'
        : '';
    return 'No new commit since patchset ${doc.target.head.n} '
        '(${doc.target.head.short}).$hint';
  }
  final summary = s.advance(doc.target, from, doc.target.head.sha);
  doc.rebuild();
  s.target = doc.target;
  s.save();
  return 'Patchset ${doc.target.head.n} (${doc.target.head.short}) '
      '"${doc.target.head.subject}". $summary. '
      'The browser will reload itself.';
}

Map<String, dynamic> callTool(
    String name, Map<String, dynamic> a, Session s, Doc doc) {
  Thread? pick() {
    final id = (a['thread'] as num?)?.toInt();
    return id == null ? null : s.byId(id);
  }

  switch (name) {
    case 'review_pending':
      return mcpText(pendingMd(s, doc));

    case 'review_reply':
      final t = pick();
      if (t == null) {
        return mcpText('No thread ${a['thread']}. Call review_pending first.',
            isError: true);
      }
      final text = (a['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) return mcpText('text is required.', isError: true);
      t.msgs.add(Msg('ai', text, now()));
      t.delivered = t.msgs.length;
      s.save();
      return mcpText('Replied to thread ${t.id} (${t.where}). '
          'It is now visible in the browser.');

    case 'review_resolve':
      final t = pick();
      if (t == null) return mcpText('No thread ${a['thread']}.', isError: true);
      t.resolved = true;
      t.delivered = t.msgs.length;
      s.save();
      return mcpText('Thread ${t.id} resolved.');

    case 'review_refresh':
      return mcpText(refreshReview(s, doc));

    case 'review_status':
      final waiting = s.threads.where((t) => t.needsAgent).length;
      final done = s.threads.where((t) => t.resolved).length;
      final gone = s.threads.where((t) => t.notInLatest).length;
      final b = StringBuffer()
        ..writeln('Reviewing ${doc.label} '
            '(base ${shortSha(doc.target.base)} pinned)')
        ..writeln('Patchset ${doc.target.head.n} of '
            '${doc.target.patchsets.length}: ${doc.target.head.short} '
            '"${doc.target.head.subject}"')
        ..writeln('${doc.lines.length} diff lines, ${s.threads.length} '
            'thread(s), $waiting waiting on you, $done resolved, '
            '$gone no longer in the diff');
      if (doc.target.dirty) {
        b.writeln('Uncommitted work is present and is NOT part of the review; '
            'commit it and call review_refresh.');
      }
      return mcpText(b.toString());

    default:
      return mcpText('Unknown tool: $name', isError: true);
  }
}

Map<String, dynamic>? rpc(Map<String, dynamic> m, Session s, Doc doc) {
  final id = m['id'];
  if (id == null) return null; // notification — nothing to answer
  final method = m['method'] as String?;
  final params = (m['params'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> ok(Object result) =>
      {'jsonrpc': '2.0', 'id': id, 'result': result};

  switch (method) {
    case 'initialize':
      final pv = params['protocolVersion'] as String?;
      return ok({
        'protocolVersion': protocolVersions.contains(pv) ? pv : '2025-06-18',
        'capabilities': {'tools': <String, dynamic>{}},
        'serverInfo': {'name': 'commitreview', 'version': '0.4.0'},
      });
    case 'ping':
      return ok(<String, dynamic>{});
    case 'tools/list':
      return ok({'tools': tools});
    case 'tools/call':
      return ok(callTool(
          params['name'] as String? ?? '',
          (params['arguments'] as Map?)?.cast<String, dynamic>() ?? {},
          s,
          doc));
    default:
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32601, 'message': 'Method not found: $method'},
      };
  }
}
