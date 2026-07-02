// Code-block widget with syntax highlighting + copy button + horizontal
// scroll. Uses `flutter_highlight` under the hood.
//
// Performance note: re-parses the whole code block on every rebuild.
// Because each block widget is keyed by its AST node ID, only the
// trailing OPEN block actually re-parses during a stream — closed blocks
// are preserved by Flutter's element diff and never rebuild. Per-line
// caching (further optimization) can land in Phase 8.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart' show HighlightView;

import '../parser/ast.dart';
import 'syntax_theme.dart';

class CodeBlockWidget extends StatefulWidget {
  const CodeBlockWidget({
    super.key,
    required this.node,
    required this.syntaxTheme,
    this.builder,
    this.showLineNumbers = true,
  });

  final CodeBlockNode node;
  final SyntaxTheme syntaxTheme;
  final CodeBlockBuilder? builder;
  final bool showLineNumbers;

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  Widget? _cached;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cached = null;
  }

  @override
  void didUpdateWidget(covariant CodeBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syntaxTheme != oldWidget.syntaxTheme ||
        widget.builder != oldWidget.builder ||
        widget.showLineNumbers != oldWidget.showLineNumbers) {
      _cached = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.node.isComplete && _cached != null) {
      return _cached!;
    }

    Widget result;
    if (widget.builder != null) {
      result = widget.builder!(
        context,
        widget.node.language,
        widget.node.content,
        widget.node.isComplete,
      );
    } else {
      final theme = Theme.of(context);
      final bg = widget.syntaxTheme.effectiveBackground(
        theme.colorScheme.surfaceContainerHighest,
      );
      final fg = widget.syntaxTheme.effectiveDefaultColor(
        theme.colorScheme.onSurface,
      );

      result = Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _CodeHeader(
              language: widget.node.language,
              code: widget.node.content,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: _CodeBody(
                code: widget.node.content,
                language: widget.node.language,
                syntaxTheme: widget.syntaxTheme,
                defaultColor: fg,
                showLineNumbers: widget.showLineNumbers,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.node.isComplete) {
      _cached = result;
    }

    return result;
  }
}

/// Renders the code with syntax highlighting when a language is provided,
/// or falls back to a plain monospace [Text] otherwise. [HighlightView]
/// throws on a null language, so we only delegate when we have one.
class _CodeBody extends StatelessWidget {
  const _CodeBody({
    required this.code,
    required this.language,
    required this.syntaxTheme,
    required this.defaultColor,
    this.showLineNumbers = true,
  });

  final String code;
  final String? language;
  final SyntaxTheme syntaxTheme;
  final Color defaultColor;
  final bool showLineNumbers;

  @override
  Widget build(BuildContext context) {
    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Courier', 'monospace'],
      fontSize: 13,
      height: 1.45,
      color: defaultColor,
    );

    final lines = code.split('\n');
    final codeWidget = language == null || language!.isEmpty
        ? Text(code, style: monoStyle)
        : HighlightView(
            code,
            language: language,
            theme: syntaxTheme.classes,
            textStyle: monoStyle,
          );

    if (!showLineNumbers || lines.length <= 1) return codeWidget;

    final lineNumStyle = monoStyle.copyWith(
      color: defaultColor.withValues(alpha: 0.4),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (var i = 1; i <= lines.length; i++)
              SizedBox(
                height: monoStyle.height != null
                    ? (monoStyle.fontSize! * monoStyle.height!)
                    : monoStyle.fontSize! * 1.45,
                child: Text(
                  '$i',
                  style: lineNumStyle,
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        codeWidget,
      ],
    );
  }
}

class _CodeHeader extends StatelessWidget {
  const _CodeHeader({required this.language, required this.code});

  final String? language;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: <Widget>[
          if (language != null && language!.isNotEmpty)
            Text(
              language!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          const Spacer(),
          _CopyButton(code: code),
        ],
      ),
    );
  }
}

/// Top-right copy-to-clipboard button. Briefly shows a checkmark after copy.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code});

  final String code;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _onTap() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: _copied ? 'Copied' : 'Copy',
      onPressed: widget.code.isEmpty ? null : _onTap,
      icon: Icon(
        _copied ? Icons.check : Icons.content_copy_outlined,
        size: 16,
        color: _copied
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
