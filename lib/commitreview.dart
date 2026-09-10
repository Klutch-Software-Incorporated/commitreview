/// A local code review tool built around commits. Renders a commit's diff in
/// the browser, lets you comment on any line, and exposes those threads to an
/// agent over MCP so it can reply inline and pick up your next commit.
library;

export 'src/anchor.dart';
export 'src/git.dart';
export 'src/mapping.dart';
export 'src/diff.dart';
export 'src/doc.dart';
export 'src/html.dart';
export 'src/markdown.dart';
export 'src/mcp.dart';
export 'src/model.dart';
export 'src/server.dart';
export 'src/target.dart';
