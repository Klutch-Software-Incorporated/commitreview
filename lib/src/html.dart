import 'diff.dart';
import 'template.dart';

String buildHtml(List<String> lines, List<Meta> metas, String target,
    String forceView, int version) {
  final files = collectFiles(lines, metas);
  final subs = {
    '__TREE__': renderTree(treeModel(files)),
    '__UNIFIED__': buildUnified(lines, metas, files),
    '__SPLIT__': buildSplit(lines, metas, files),
    '__FORCEVIEW__': forceView,
    '__VERSION__': '$version',
    '__TARGET__': esc(target),
  };
  // Must be a single pass: chained replaceAll would re-scan already-substituted
  // content, and a diff can legitimately contain these placeholder tokens —
  // reviewing this very file does exactly that.
  return pageTemplate.replaceAllMapped(
      RegExp(r'__(?:TREE|UNIFIED|SPLIT|FORCEVIEW|VERSION|TARGET)__'),
      (m) => subs[m.group(0)]!);
}
