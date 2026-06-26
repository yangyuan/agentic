import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const _headingSizes = <int, double>{1: 20, 2: 18, 3: 16, 4: 15, 5: 14, 6: 14};
const _inlineImageMax = 128.0;
const _listMarkerCharWidth = 6.0;
const _listSiblingGap = 4.0;
const _defaultBlockGap = 12.0;
const _listBlockKinds = <String>{'bullet', 'numbered', 'task'};

final _fencePattern = RegExp(r'^\s*```(.*)$');
final _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
final _bulletPattern = RegExp(r'^(\s*)([-*+])\s+(.*)$');
final _taskPattern = RegExp(r'^\[([ xX])\]\s+(.*)$');
final _numberedPattern = RegExp(r'^(\s*)(\d+)\.\s+(.*)$');
final _quotePattern = RegExp(r'^\s*>\s?(.*)$');
final _rulePattern = RegExp(r'^\s*(?:[-*_])(?:\s*[-*_]){2,}\s*$');
final _tableRowPattern = RegExp(r'^\s*\|.*\|\s*$');
final _tableSeparatorPattern = RegExp(
  r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$',
);

class AgenticMarkdown extends StatelessWidget {
  const AgenticMarkdown({
    super.key,
    required this.content,
    this.baseStyle,
    this.trailingCursor = false,
    this.onOpenLink,
  });

  final String content;
  final TextStyle? baseStyle;
  final bool trailingCursor;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = defaultStyle.merge(baseStyle);
    final blocks = _MarkdownParser(content).parse();
    final renderer = _MarkdownRenderer(
      baseStyle: effectiveStyle,
      colorScheme: colorScheme,
      selectionColor: colorScheme.primary.withValues(alpha: 0.28),
      onOpenLink: onOpenLink,
    );

    final children = <Widget>[];
    _MarkdownBlock? previousBlock;
    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      if (previousBlock != null) {
        children.add(SizedBox(height: _blockGap(block)));
      }
      children.add(
        renderer.render(
          block,
          trailingCursor: trailingCursor && index == blocks.length - 1,
        ),
      );
      previousBlock = block;
    }

    if (trailingCursor && blocks.isEmpty) {
      children.add(renderer.cursorWidget());
    }
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    return column;
  }
}

double _blockGap(_MarkdownBlock current) {
  if (_listBlockKinds.contains(current.kind)) {
    return _listSiblingGap;
  }
  return _defaultBlockGap;
}

class _MarkdownBlock {
  const _MarkdownBlock(
    this.kind, {
    this.lines = const <String>[],
    this.level = 0,
    this.ordinals = const <int>[],
    this.rows = const <List<String>>[],
    this.alignments = const <String>[],
    this.checked = false,
    this.children = const <_MarkdownBlock>[],
  });

  final String kind;
  final List<String> lines;
  final int level;
  final List<int> ordinals;
  final List<List<String>> rows;
  final List<String> alignments;
  final bool checked;
  final List<_MarkdownBlock> children;
}

class _MarkdownParser {
  const _MarkdownParser(this.content);

  final String content;

  List<_MarkdownBlock> parse() {
    return _parseBlocks(content.split('\n'));
  }
}

List<_MarkdownBlock> _parseBlocks(List<String> lines) {
  final blocks = <_MarkdownBlock>[];
  _MutableBlock? currentParagraph;
  var inCode = false;
  _MutableBlock? codeBlock;

  void flushParagraph() {
    if (currentParagraph == null) {
      return;
    }
    blocks.add(currentParagraph!.toBlock());
    currentParagraph = null;
  }

  var index = 0;
  while (index < lines.length) {
    final rawLine = lines[index];
    if (inCode) {
      if (_fencePattern.hasMatch(rawLine)) {
        blocks.add(codeBlock!.toBlock());
        inCode = false;
      } else {
        codeBlock!.lines.add(rawLine);
      }
      index += 1;
      continue;
    }

    if (_fencePattern.hasMatch(rawLine)) {
      flushParagraph();
      inCode = true;
      codeBlock = _MutableBlock('code');
      index += 1;
      continue;
    }

    final stripped = rawLine.trim();
    if (stripped.isEmpty) {
      flushParagraph();
      index += 1;
      continue;
    }

    if (_rulePattern.hasMatch(rawLine)) {
      flushParagraph();
      blocks.add(const _MarkdownBlock('rule'));
      index += 1;
      continue;
    }

    if (_tableRowPattern.hasMatch(rawLine) &&
        index + 1 < lines.length &&
        _tableSeparatorPattern.hasMatch(lines[index + 1])) {
      flushParagraph();
      final table = _consumeTable(lines, index);
      blocks.add(table.block);
      index += table.consumed;
      continue;
    }

    final heading = _headingPattern.firstMatch(rawLine);
    if (heading != null) {
      flushParagraph();
      blocks.add(
        _MarkdownBlock(
          'heading',
          lines: <String>[heading.group(2)!],
          level: heading.group(1)!.length,
        ),
      );
      index += 1;
      continue;
    }

    final bullet = _bulletPattern.firstMatch(rawLine);
    final numbered = bullet == null
        ? _numberedPattern.firstMatch(rawLine)
        : null;
    if (bullet != null || numbered != null) {
      flushParagraph();

      late final int leading;
      late final int markerLength;
      late String firstBody;
      late String kind;
      late bool checked;
      late List<int> ordinals;

      if (bullet != null) {
        leading = bullet.group(1)!.length;
        markerLength = 2;
        firstBody = bullet.group(3)!;
        final task = _taskPattern.firstMatch(firstBody);
        if (task != null) {
          kind = 'task';
          checked = task.group(1) == 'x' || task.group(1) == 'X';
          firstBody = task.group(2)!;
        } else {
          kind = 'bullet';
          checked = false;
        }
        ordinals = const <int>[];
      } else {
        leading = numbered!.group(1)!.length;
        final number = numbered.group(2)!;
        markerLength = number.length + 2;
        firstBody = numbered.group(3)!;
        kind = 'numbered';
        checked = false;
        ordinals = <int>[int.parse(number)];
      }

      final contentColumn = leading + markerLength;
      final itemLines = <String>[firstBody];
      var nextIndex = index + 1;
      while (nextIndex < lines.length) {
        final nextLine = lines[nextIndex];
        if (nextLine.trim().isEmpty) {
          itemLines.add('');
          nextIndex += 1;
          continue;
        }

        final lead = nextLine.length - nextLine.trimLeft().length;
        if (lead >= contentColumn) {
          itemLines.add(nextLine.substring(contentColumn));
          nextIndex += 1;
          continue;
        }
        break;
      }

      while (itemLines.isNotEmpty && itemLines.last.trim().isEmpty) {
        itemLines.removeLast();
      }

      blocks.add(
        _MarkdownBlock(
          kind,
          children: _parseBlocks(itemLines),
          ordinals: ordinals,
          checked: checked,
        ),
      );
      index = nextIndex;
      continue;
    }

    final quote = _quotePattern.firstMatch(rawLine);
    if (quote != null) {
      if (blocks.isNotEmpty &&
          blocks.last.kind == 'quote' &&
          currentParagraph == null) {
        final previous = blocks.removeLast();
        blocks.add(
          _MarkdownBlock(
            'quote',
            lines: <String>[...previous.lines, quote.group(1)!],
          ),
        );
      } else {
        flushParagraph();
        blocks.add(_MarkdownBlock('quote', lines: <String>[quote.group(1)!]));
      }
      index += 1;
      continue;
    }

    currentParagraph ??= _MutableBlock('paragraph');
    currentParagraph!.lines.add(stripped);
    index += 1;
  }

  flushParagraph();
  if (inCode) {
    blocks.add(codeBlock!.toBlock());
  }
  return blocks;
}

class _MutableBlock {
  _MutableBlock(this.kind);

  final String kind;
  final List<String> lines = <String>[];

  _MarkdownBlock toBlock() {
    return _MarkdownBlock(kind, lines: List<String>.unmodifiable(lines));
  }
}

class _TableResult {
  const _TableResult(this.block, this.consumed);

  final _MarkdownBlock block;
  final int consumed;
}

_TableResult _consumeTable(List<String> lines, int start) {
  final headerCells = _splitTableRow(lines[start]);
  final alignments = _parseAlignmentRow(lines[start + 1], headerCells.length);
  final rows = <List<String>>[headerCells];
  var cursor = start + 2;
  while (cursor < lines.length && _tableRowPattern.hasMatch(lines[cursor])) {
    var rowCells = _splitTableRow(lines[cursor]);
    if (rowCells.length < headerCells.length) {
      rowCells = <String>[
        ...rowCells,
        ...List<String>.filled(headerCells.length - rowCells.length, ''),
      ];
    } else if (rowCells.length > headerCells.length) {
      rowCells = rowCells.sublist(0, headerCells.length);
    }
    rows.add(rowCells);
    cursor += 1;
  }
  return _TableResult(
    _MarkdownBlock('table', rows: rows, alignments: alignments),
    cursor - start,
  );
}

List<String> _splitTableRow(String line) {
  var stripped = line.trim();
  if (stripped.startsWith('|')) {
    stripped = stripped.substring(1);
  }
  if (stripped.endsWith('|')) {
    stripped = stripped.substring(0, stripped.length - 1);
  }
  return stripped.split('|').map((cell) => cell.trim()).toList();
}

List<String> _parseAlignmentRow(String line, int expectedCount) {
  final cells = _splitTableRow(line);
  final alignments = <String>[];
  for (final cell in cells) {
    final cleaned = cell.trim();
    final starts = cleaned.startsWith(':');
    final ends = cleaned.endsWith(':');
    if (starts && ends) {
      alignments.add('center');
    } else if (ends) {
      alignments.add('right');
    } else {
      alignments.add('left');
    }
  }
  while (alignments.length < expectedCount) {
    alignments.add('left');
  }
  return alignments.take(expectedCount).toList();
}

int _listMarkerWidth(_MarkdownBlock block) {
  if (block.kind == 'numbered') {
    final ordinal = block.ordinals.isEmpty ? 1 : block.ordinals.first;
    final width = '$ordinal.'.length;
    return width < 3 ? 3 : width;
  }
  return 3;
}

double _lineHeight(TextStyle style) {
  final fontSize = style.fontSize ?? 14;
  return (fontSize * (style.height ?? 1.0)).clamp(
    fontSize + 2,
    double.infinity,
  );
}

class _MarkdownRenderer {
  const _MarkdownRenderer({
    required this.baseStyle,
    required this.colorScheme,
    required this.selectionColor,
    required this.onOpenLink,
  });

  final TextStyle baseStyle;
  final ColorScheme colorScheme;
  final Color selectionColor;
  final ValueChanged<String>? onOpenLink;

  Widget render(_MarkdownBlock block, {bool trailingCursor = false}) {
    return switch (block.kind) {
      'heading' => _renderHeading(block, trailingCursor: trailingCursor),
      'bullet' => _renderListItem(
        block,
        marker: Text('\u2022', style: baseStyle),
        trailingCursor: trailingCursor,
      ),
      'task' => _renderListItem(
        block,
        marker: _taskCheckboxWidget(block.checked),
        trailingCursor: trailingCursor,
      ),
      'numbered' => _renderListItem(
        block,
        marker: Text(
          '${block.ordinals.isEmpty ? 1 : block.ordinals.first}.',
          style: baseStyle,
        ),
        trailingCursor: trailingCursor,
      ),
      'code' => _renderCodeBlock(block, trailingCursor: trailingCursor),
      'quote' => _renderQuote(block, trailingCursor: trailingCursor),
      'rule' => _renderRule(),
      'table' => _renderTable(block),
      _ => _renderParagraph(block, trailingCursor: trailingCursor),
    };
  }

  Widget cursorWidget() {
    return Container(
      width: 1.5,
      height: baseStyle.fontSize,
      margin: const EdgeInsets.only(left: 2),
      color: colorScheme.primary,
    );
  }

  InlineSpan _cursorSpan() {
    return WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: SelectionContainer.disabled(child: cursorWidget()),
    );
  }

  Widget _renderParagraph(_MarkdownBlock block, {bool trailingCursor = false}) {
    final spans = _inlineSpans(
      block.lines.map((line) => line.trim()).join('\n'),
    );
    if (trailingCursor) {
      spans.add(_cursorSpan());
    }
    return _richText(spans, style: baseStyle);
  }

  Widget _renderHeading(_MarkdownBlock block, {bool trailingCursor = false}) {
    final style = baseStyle.copyWith(
      fontSize: _headingSizes[block.level] ?? 14,
      fontWeight: FontWeight.w700,
    );
    final spans = _inlineSpans(block.lines.firstOrNull ?? '');
    if (trailingCursor) {
      spans.add(_cursorSpan());
    }
    return _richText(spans, style: style);
  }

  Widget _renderListItem(
    _MarkdownBlock block, {
    required Widget marker,
    bool trailingCursor = false,
  }) {
    final markerColumn = Container(
      width: _listMarkerWidth(block) * _listMarkerCharWidth,
      height: _lineHeight(baseStyle),
      alignment: Alignment.centerLeft,
      child: marker,
    );
    final bodyChildren = <Widget>[];
    for (var index = 0; index < block.children.length; index += 1) {
      if (index > 0) {
        bodyChildren.add(const SizedBox(height: _listSiblingGap));
      }
      bodyChildren.add(
        render(
          block.children[index],
          trailingCursor: trailingCursor && index == block.children.length - 1,
        ),
      );
    }
    if (bodyChildren.isEmpty) {
      return markerColumn;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        markerColumn,
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: bodyChildren,
          ),
        ),
      ],
    );
  }

  Widget _taskCheckboxWidget(bool checked) {
    final iconData = checked ? Icons.check_box : Icons.check_box_outline_blank;
    final size = (baseStyle.fontSize ?? 14) + 2;
    return SelectionContainer.disabled(
      child: Icon(
        iconData,
        size: size,
        color: checked ? colorScheme.primary : colorScheme.outline,
      ),
    );
  }

  Widget _renderCodeBlock(_MarkdownBlock block, {bool trailingCursor = false}) {
    final body = block.lines.join('\n');
    final style = baseStyle.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Menlo', 'Monaco', 'Consolas'],
    );
    final textWidget = trailingCursor
        ? Text.rich(
            TextSpan(text: body, children: <InlineSpan>[_cursorSpan()]),
            style: style,
            selectionColor: selectionColor,
          )
        : Text(body, style: style, selectionColor: selectionColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(width: 1, color: colorScheme.outlineVariant),
      ),
      child: textWidget,
    );
  }

  Widget _renderQuote(_MarkdownBlock block, {bool trailingCursor = false}) {
    final quotedStyle = baseStyle.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    final spans = _inlineSpans(block.lines.join('\n'));
    if (trailingCursor) {
      spans.add(_cursorSpan());
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            width: 3,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: _richText(spans, style: quotedStyle),
    );
  }

  Widget _richText(
    List<InlineSpan> children, {
    required TextStyle style,
    TextAlign? textAlign,
  }) {
    return Text.rich(
      TextSpan(style: style, children: children),
      style: style,
      textAlign: textAlign,
      selectionColor: selectionColor,
    );
  }

  List<InlineSpan> _inlineSpans(String text) {
    final spans = <InlineSpan>[];
    final plain = StringBuffer();
    var cursor = 0;

    void flushPlain() {
      if (plain.isEmpty) {
        return;
      }
      spans.add(TextSpan(text: plain.toString()));
      plain.clear();
    }

    while (cursor < text.length) {
      final match = _InlineMatch.tryParse(text, cursor);
      if (match == null) {
        plain.write(text[cursor]);
        cursor += 1;
        continue;
      }

      flushPlain();
      spans.add(_inlineSpanFor(match));
      cursor = match.end;
    }

    flushPlain();
    return spans;
  }

  InlineSpan _inlineSpanFor(_InlineMatch match) {
    return switch (match.kind) {
      _InlineKind.escape => TextSpan(text: match.text),
      _InlineKind.code => _inlineCodeSpan(match.text),
      _InlineKind.boldItalic => TextSpan(
        text: match.text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        ),
      ),
      _InlineKind.bold => TextSpan(
        text: match.text,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      _InlineKind.strike => TextSpan(
        text: match.text,
        style: TextStyle(
          decoration: TextDecoration.lineThrough,
          decorationThickness: 2,
          decorationColor: baseStyle.color,
        ),
      ),
      _InlineKind.italic => TextSpan(
        text: match.text,
        style: const TextStyle(fontStyle: FontStyle.italic),
      ),
      _InlineKind.link => _linkSpan(text: match.text, url: match.url!),
      _InlineKind.image => _imageSpan(alt: match.text, url: match.url!),
    };
  }

  InlineSpan _inlineCodeSpan(String body) {
    final codeStyle = baseStyle.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Menlo', 'Monaco', 'Consolas'],
      height: baseStyle.height,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(body, style: codeStyle),
      ),
    );
  }

  InlineSpan _linkSpan({required String text, required String url}) {
    final linkStyle = TextStyle(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
      fontSize: baseStyle.fontSize,
    );
    final open = onOpenLink;
    return TextSpan(
      text: text,
      style: linkStyle,
      recognizer: open == null
          ? null
          : (TapGestureRecognizer()..onTap = () => open(url)),
      mouseCursor: open == null ? MouseCursor.defer : SystemMouseCursors.click,
    );
  }

  InlineSpan _imageSpan({required String alt, required String url}) {
    final imageWidget = _buildImage(url);
    if (imageWidget == null) {
      return _linkSpan(text: '[image] ${alt.isEmpty ? url : alt}', url: url);
    }

    Widget child = Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(width: 1, color: colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: imageWidget,
      ),
    );

    final open = onOpenLink;
    if (open != null) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => open(url),
            borderRadius: BorderRadius.circular(4),
            child: child,
          ),
        ),
      );
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SelectionContainer.disabled(child: child),
    );
  }

  Widget _renderRule() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: 1,
      color: colorScheme.outlineVariant,
    );
  }

  Widget _renderTable(_MarkdownBlock block) {
    if (block.rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final columnCount = block.rows.first.length;
    final alignments = <String>[...block.alignments];
    while (alignments.length < columnCount) {
      alignments.add('left');
    }

    final rows = <Widget>[];
    for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex += 1) {
      final isHeader = rowIndex == 0;
      final cells = block.rows[rowIndex];
      final rowChildren = <Widget>[];
      for (var columnIndex = 0; columnIndex < columnCount; columnIndex += 1) {
        final cellText = columnIndex < cells.length ? cells[columnIndex] : '';
        rowChildren.add(
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  left: columnIndex > 0
                      ? BorderSide(width: 1, color: colorScheme.outlineVariant)
                      : BorderSide.none,
                ),
              ),
              child: _renderTableCell(
                cellText,
                alignment: alignments[columnIndex],
                isHeader: isHeader,
              ),
            ),
          ),
        );
      }

      rows.add(
        Container(
          decoration: BoxDecoration(
            color: isHeader ? colorScheme.surfaceContainerHigh : null,
            border: rowIndex < block.rows.length - 1
                ? Border(
                    bottom: BorderSide(
                      width: 1,
                      color: colorScheme.outlineVariant,
                    ),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowChildren,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(width: 1, color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _renderTableCell(
    String text, {
    required String alignment,
    required bool isHeader,
  }) {
    final cellStyle = baseStyle.copyWith(
      fontWeight: isHeader ? FontWeight.w700 : null,
    );
    final textAlign = switch (alignment) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return _richText(
      _inlineSpans(text),
      style: cellStyle,
      textAlign: textAlign,
    );
  }
}

Widget? _buildImage(String url) {
  if (url.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  return Image.network(
    url,
    width: _inlineImageMax,
    height: _inlineImageMax,
    fit: BoxFit.contain,
  );
}

enum _InlineKind { escape, code, boldItalic, bold, strike, italic, link, image }

class _InlineMatch {
  const _InlineMatch(this.kind, this.text, this.end, {this.url});

  final _InlineKind kind;
  final String text;
  final int end;
  final String? url;

  static _InlineMatch? tryParse(String source, int start) {
    final escape = _tryEscape(source, start);
    if (escape != null) {
      return escape;
    }

    final code = _tryCode(source, start);
    if (code != null) {
      return code;
    }

    final boldItalic = _tryDelimited(
      source,
      start,
      '***',
      _InlineKind.boldItalic,
      excludedCharacter: '*',
    );
    if (boldItalic != null) {
      return boldItalic;
    }

    final boldItalicUnderscore = _tryDelimited(
      source,
      start,
      '___',
      _InlineKind.boldItalic,
      excludedCharacter: '_',
    );
    if (boldItalicUnderscore != null) {
      return boldItalicUnderscore;
    }

    final bold = _tryDelimited(
      source,
      start,
      '**',
      _InlineKind.bold,
      excludedCharacter: '*',
    );
    if (bold != null) {
      return bold;
    }

    final boldUnderscore = _tryDelimited(
      source,
      start,
      '__',
      _InlineKind.bold,
      excludedCharacter: '_',
    );
    if (boldUnderscore != null) {
      return boldUnderscore;
    }

    final strike = _tryDelimited(source, start, '~~', _InlineKind.strike);
    if (strike != null) {
      return strike;
    }

    final italicStar = _tryDelimited(
      source,
      start,
      '*',
      _InlineKind.italic,
      excludedCharacter: '*',
    );
    if (italicStar != null) {
      return italicStar;
    }

    final italicUnderscore = _tryUnderscoreItalic(source, start);
    if (italicUnderscore != null) {
      return italicUnderscore;
    }

    final image = _tryLinkOrImage(source, start, image: true);
    if (image != null) {
      return image;
    }

    return _tryLinkOrImage(source, start, image: false);
  }

  static _InlineMatch? _tryEscape(String source, int start) {
    if (source[start] != '\\' || start + 1 >= source.length) {
      return null;
    }
    final escaped = source[start + 1];
    if (!'\\`*_{}[]()#+-.!>~|'.contains(escaped)) {
      return null;
    }
    return _InlineMatch(_InlineKind.escape, escaped, start + 2);
  }

  static _InlineMatch? _tryCode(String source, int start) {
    if (source[start] != '`') {
      return null;
    }
    var tickCount = 1;
    while (start + tickCount < source.length &&
        source[start + tickCount] == '`') {
      tickCount += 1;
    }

    final ticks = '`' * tickCount;
    final close = source.indexOf(ticks, start + tickCount);
    if (close < 0) {
      return null;
    }
    final body = source.substring(start + tickCount, close);
    if (body.isEmpty || body.contains('\n')) {
      return null;
    }
    return _InlineMatch(_InlineKind.code, body, close + tickCount);
  }

  static _InlineMatch? _tryDelimited(
    String source,
    int start,
    String delimiter,
    _InlineKind kind, {
    String? excludedCharacter,
  }) {
    if (!source.startsWith(delimiter, start)) {
      return null;
    }
    final close = source.indexOf(delimiter, start + delimiter.length);
    if (close < 0) {
      return null;
    }
    final body = source.substring(start + delimiter.length, close);
    if (body.isEmpty || body.contains('\n')) {
      return null;
    }
    if (excludedCharacter != null && body.contains(excludedCharacter)) {
      return null;
    }
    return _InlineMatch(kind, body, close + delimiter.length);
  }

  static _InlineMatch? _tryUnderscoreItalic(String source, int start) {
    if (source[start] != '_' || !_isUnderscoreItalicStart(source, start)) {
      return null;
    }
    var close = source.indexOf('_', start + 1);
    while (close >= 0) {
      final body = source.substring(start + 1, close);
      if (body.isNotEmpty &&
          !body.contains('\n') &&
          !body.contains('_') &&
          _isUnderscoreItalicEnd(source, close)) {
        return _InlineMatch(_InlineKind.italic, body, close + 1);
      }
      close = source.indexOf('_', close + 1);
    }
    return null;
  }

  static bool _isUnderscoreItalicStart(String source, int start) {
    if (start == 0) {
      return true;
    }
    return !_isAsciiAlphanumeric(source.codeUnitAt(start - 1));
  }

  static bool _isUnderscoreItalicEnd(String source, int close) {
    if (close + 1 >= source.length) {
      return true;
    }
    return !_isAsciiAlphanumeric(source.codeUnitAt(close + 1));
  }

  static _InlineMatch? _tryLinkOrImage(
    String source,
    int start, {
    required bool image,
  }) {
    final marker = image ? '![' : '[';
    final kind = image ? _InlineKind.image : _InlineKind.link;
    if (!source.startsWith(marker, start)) {
      return null;
    }
    final labelStart = start + marker.length;
    final labelEnd = source.indexOf(']', labelStart);
    if (labelEnd < 0 ||
        labelEnd + 1 >= source.length ||
        source[labelEnd + 1] != '(') {
      return null;
    }
    final urlStart = labelEnd + 2;
    final urlEnd = source.indexOf(')', urlStart);
    if (urlEnd < 0) {
      return null;
    }
    final label = source.substring(labelStart, labelEnd);
    final url = source.substring(urlStart, urlEnd);
    if (label.contains('\n') || url.isEmpty || url.contains(RegExp(r'\s'))) {
      return null;
    }
    return _InlineMatch(kind, label, urlEnd + 1, url: url);
  }
}

bool _isAsciiAlphanumeric(int codeUnit) {
  return (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122);
}
