// GFM table widget with copy controls.
//
// Each cell can contain inline markdown (bold, italic, links, inline code).
// Column widths use `IntrinsicColumnWidth` — they grow as wider content
// arrives but never shrink, which gives stable layout during streaming.
//
// Wide tables wrap in a horizontal `SingleChildScrollView`. A copy dropdown
// above the table lets users export as CSV, TSV, or Markdown.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../parser/ast.dart';
import '../parser/token.dart';
import 'inline_spans.dart';

// ──────────────────────────────────────────────────────────────────────────
// Format utilities (exported for direct use)
// ──────────────────────────────────────────────────────────────────────────

String tableDataToCSV(TableNode node) {
  final buf = StringBuffer();
  if (node.headers.isNotEmpty) {
    buf.writeln(node.headers.map(_escapeCSV).join(','));
  }
  for (final row in node.rows) {
    final padded = _padRow(row, node.headers.length);
    buf.writeln(padded.map(_escapeCSV).join(','));
  }
  return buf.toString().trimRight();
}

String tableDataToTSV(TableNode node) {
  final buf = StringBuffer();
  if (node.headers.isNotEmpty) {
    buf.writeln(node.headers.map(_escapeTSV).join('\t'));
  }
  for (final row in node.rows) {
    final padded = _padRow(row, node.headers.length);
    buf.writeln(padded.map(_escapeTSV).join('\t'));
  }
  return buf.toString().trimRight();
}

String tableDataToMarkdown(TableNode node) {
  if (node.headers.isEmpty) return '';
  final buf = StringBuffer();
  final escaped = node.headers.map(_escapeMDCell).join(' | ');
  buf.writeln('| $escaped |');
  buf.writeln('| ${node.headers.map((_) => '---').join(' | ')} |');
  for (final row in node.rows) {
    final padded = _padRow(row, node.headers.length);
    buf.writeln('| ${padded.map(_escapeMDCell).join(' | ')} |');
  }
  return buf.toString().trimRight();
}

List<String> _padRow(List<String> row, int count) {
  if (row.length >= count) return row;
  return [...row, ...List.filled(count - row.length, '')];
}

String _escapeCSV(String v) {
  if (!v.contains(RegExp(r'["\n,]'))) return v;
  return '"${v.replaceAll('"', '""')}"';
}

String _escapeTSV(String v) =>
    v.replaceAll('\t', '\\t').replaceAll('\n', '\\n').replaceAll('\r', '\\r');

String _escapeMDCell(String v) =>
    v.replaceAll('\\', '\\\\').replaceAll('|', '\\|');

// ──────────────────────────────────────────────────────────────────────────
// Widget
// ──────────────────────────────────────────────────────────────────────────

class TableWidget extends StatefulWidget {
  const TableWidget({
    super.key,
    required this.node,
    this.baseStyle,
    this.onLinkTap,
    this.latex = false,
  });

  final TableNode node;
  final TextStyle? baseStyle;
  final void Function(Uri uri)? onLinkTap;
  final bool latex;

  @override
  State<TableWidget> createState() => _TableWidgetState();
}

class _TableWidgetState extends State<TableWidget> {
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  bool _showMenu = false;
  bool _copied = false;
  Timer? _resetTimer;

  void _copy(String format) {
    final content = switch (format) {
      'csv' => tableDataToCSV(widget.node),
      'tsv' => tableDataToTSV(widget.node),
      _ => tableDataToMarkdown(widget.node),
    };
    Clipboard.setData(ClipboardData(text: content));
    setState(() {
      _copied = true;
      _showMenu = false;
    });
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;
    final headerBg = theme.colorScheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            SizedBox(
              height: 32,
              child: Stack(
                children: <Widget>[
                  IconButton(
                    tooltip: _copied ? 'Copied' : 'Copy table',
                    icon: Icon(
                      _copied ? Icons.check : Icons.content_copy_outlined,
                      size: 16,
                      color: _copied
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => setState(() => _showMenu = !_showMenu),
                  ),
                  if (_showMenu)
                    Positioned(
                      top: 32,
                      right: 0,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(6),
                        child: IntrinsicWidth(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _menuItem('Markdown', () => _copy('md')),
                              _menuItem('CSV', () => _copy('csv')),
                              _menuItem('TSV', () => _copy('tsv')),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: borderColor),
            children: <TableRow>[
              TableRow(
                decoration: BoxDecoration(color: headerBg),
                children: <Widget>[
                  for (var i = 0; i < widget.node.headers.length; i++)
                    _Cell(
                      text: widget.node.headers[i],
                      alignment: _safeAlignment(i),
                      recognizers: _recognizers,
                      baseStyle: (widget.baseStyle ?? const TextStyle())
                          .copyWith(fontWeight: FontWeight.bold),
                      onLinkTap: widget.onLinkTap,
                      latex: widget.latex,
                    ),
                ],
              ),
              for (final row in widget.node.rows)
                TableRow(
                  children: <Widget>[
                    for (var i = 0; i < widget.node.headers.length; i++)
                      _Cell(
                        text: i < row.length ? row[i] : '',
                        alignment: _safeAlignment(i),
                        recognizers: _recognizers,
                        baseStyle: widget.baseStyle,
                        onLinkTap: widget.onLinkTap,
                        latex: widget.latex,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _menuItem(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  TableAlignment _safeAlignment(int column) =>
      column < widget.node.alignments.length
          ? widget.node.alignments[column]
          : TableAlignment.none;
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.alignment,
    required this.recognizers,
    this.baseStyle,
    this.onLinkTap,
    this.latex = false,
  });

  final String text;
  final TableAlignment alignment;
  final TextStyle? baseStyle;
  final List<GestureRecognizer> recognizers;
  final void Function(Uri uri)? onLinkTap;
  final bool latex;

  @override
  Widget build(BuildContext context) {
    final result = buildInlineSpans(
      text,
      context,
      baseStyle: baseStyle,
      onLinkTap: onLinkTap,
      recognizers: recognizers,
      latex: latex,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text.rich(
        TextSpan(children: result.spans),
        textAlign: _textAlign(alignment),
      ),
    );
  }

  TextAlign _textAlign(TableAlignment a) => switch (a) {
    TableAlignment.left => TextAlign.left,
    TableAlignment.center => TextAlign.center,
    TableAlignment.right => TextAlign.right,
    TableAlignment.none => TextAlign.start,
  };
}
