// AST → Flutter widget tree.
//
// Top-level blocks are reconciled by stream generation, block index, and
// runtime type. Parser node IDs restart whenever incomplete Markdown is
// reparsed, so they are not valid identities across streaming snapshots.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../parser/ast.dart';
import 'animation.dart';
import 'code_block.dart';
import 'inline_spans.dart';
import 'syntax_theme.dart';
import 'table.dart' as table_widget;

class AstRenderer extends StatefulWidget {
  const AstRenderer({
    super.key,
    required this.document,
    required this.syntaxTheme,
    required this.keySeed,
    this.textStyle,
    this.onLinkTap,
    this.codeBlockBuilder,
    this.latex = false,
    this.cjk = false,
    this.lineNumbers = true,
    this.animated = true,
    this.showCaret = false,
    this.animateConfig,
  });

  final DocumentNode document;
  final int keySeed;
  final TextStyle? textStyle;
  final void Function(Uri uri)? onLinkTap;
  final SyntaxTheme syntaxTheme;
  final CodeBlockBuilder? codeBlockBuilder;
  final bool latex;
  final bool cjk;
  final bool lineNumbers;
  final bool animated;
  final bool showCaret;
  final AnimateConfig? animateConfig;

  @override
  State<AstRenderer> createState() => _AstRendererState();
}

class _AstRendererState extends State<AstRenderer> {
  @override
  Widget build(BuildContext context) {
    final useBlockAnimation = widget.animated && widget.animateConfig == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        for (final (index, node) in widget.document.children.indexed)
          StreamdownAnimatedBlock(
            key: _blockKey(index, node),
            enabled: useBlockAnimation,
            config: widget.animateConfig,
            child: _renderBlock(context, index, node),
          ),
        if (widget.showCaret) const StreamdownCaret(),
      ],
    );
  }

  Widget _renderBlock(BuildContext context, int index, AstNode node) {
    final key = _blockKey(index, node);
    return switch (node) {
      HeadingNode() => _Heading(
        key: key,
        node: node,
        baseStyle: widget.textStyle,
        onLinkTap: widget.onLinkTap,
        latex: widget.latex,
        cjk: widget.cjk,
        animateConfig: widget.animateConfig,
        streaming: widget.animateConfig != null,
        keySeed: widget.keySeed,
      ),
      ParagraphNode() => _Paragraph(
        key: key,
        node: node,
        baseStyle: widget.textStyle,
        onLinkTap: widget.onLinkTap,
        latex: widget.latex,
        cjk: widget.cjk,
        animateConfig: widget.animateConfig,
        streaming: widget.animateConfig != null,
        keySeed: widget.keySeed,
      ),
      HorizontalRuleNode() => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Divider(
          color: Theme.of(context).colorScheme.outlineVariant,
          height: 1,
        ),
      ),
      BlockquoteNode() => _Blockquote(
        key: key,
        node: node,
        baseStyle: widget.textStyle,
        onLinkTap: widget.onLinkTap,
        latex: widget.latex,
        cjk: widget.cjk,
        animateConfig: widget.animateConfig,
        streaming: widget.animateConfig != null,
        keySeed: widget.keySeed,
      ),
      ListNode() => _List(
        key: key,
        node: node,
        baseStyle: widget.textStyle,
        onLinkTap: widget.onLinkTap,
        latex: widget.latex,
        cjk: widget.cjk,
        animateConfig: widget.animateConfig,
        streaming: widget.animateConfig != null,
        keySeed: widget.keySeed,
      ),
      CodeBlockNode() => CodeBlockWidget(
        key: key,
        node: node,
        syntaxTheme: widget.syntaxTheme,
        builder: widget.codeBlockBuilder,
        showLineNumbers: widget.lineNumbers,
      ),
      TableNode() => table_widget.TableWidget(
        key: key,
        node: node,
        baseStyle: widget.textStyle,
        onLinkTap: widget.onLinkTap,
        latex: widget.latex,
      ),
      DocumentNode() || ListItemNode() => const SizedBox.shrink(),
    };
  }

  ValueKey<String> _blockKey(int index, AstNode node) =>
      ValueKey<String>('${widget.keySeed}:block:$index:${node.runtimeType}');
}

// ──────────────────────────────────────────────────────────────────────
// Block-level widgets
// ──────────────────────────────────────────────────────────────────────

class _Heading extends StatefulWidget {
  const _Heading({
    super.key,
    required this.node,
    this.baseStyle,
    this.onLinkTap,
    this.latex = false,
    this.cjk = false,
    this.animateConfig,
    this.streaming = false,
    required this.keySeed,
  });

  final HeadingNode node;
  final TextStyle? baseStyle;
  final void Function(Uri uri)? onLinkTap;
  final bool latex;
  final bool cjk;
  final AnimateConfig? animateConfig;
  final bool streaming;
  final int keySeed;

  @override
  State<_Heading> createState() => _HeadingState();
}

class _HeadingState extends State<_Heading>
    with SingleTickerProviderStateMixin {
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  Widget? _cached;
  late final AnimationController _revealController;
  int _renderedTextLength = 0;
  int _animationStartLength = 0;
  int _animationTotalMs = 1;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(vsync: this);
    _startReveal(widget.node.text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cached = null;
  }

  @override
  void didUpdateWidget(covariant _Heading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming &&
        widget.animateConfig != null &&
        widget.node.text.startsWith(oldWidget.node.text) &&
        widget.node.text.length > oldWidget.node.text.length) {
      _animationStartLength = _renderedTextLength;
      _startReveal(widget.node.text.substring(oldWidget.node.text.length));
    } else if (!widget.streaming) {
      _revealController.value = 1;
      _animationStartLength = _renderedTextLength;
    }
    if (widget.node.text != oldWidget.node.text ||
        widget.node.isComplete != oldWidget.node.isComplete ||
        widget.baseStyle != oldWidget.baseStyle ||
        widget.onLinkTap != oldWidget.onLinkTap ||
        widget.animateConfig != oldWidget.animateConfig ||
        widget.streaming != oldWidget.streaming ||
        widget.latex != oldWidget.latex ||
        widget.cjk != oldWidget.cjk) {
      _cached = null;
      if (!widget.node.text.startsWith(oldWidget.node.text)) {
        // Markdown reinterpretation (for example an emphasis marker closing)
        // is not new prose. Keep it fully visible instead of replaying the
        // animation for the whole block.
        _animationStartLength = _renderedTextLength;
        _revealController.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.streaming && widget.node.isComplete && _cached != null) {
      return _cached!;
    }
    if (!widget.streaming || widget.animateConfig == null) {
      return _buildText(context);
    }

    return AnimatedBuilder(
      animation: _revealController,
      builder: (context, _) => _buildText(context),
    );
  }

  Widget _buildText(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final theme = Theme.of(context);
    final headingStyle = switch (widget.node.level) {
      1 => theme.textTheme.headlineLarge,
      2 => theme.textTheme.headlineMedium,
      3 => theme.textTheme.headlineSmall,
      4 => theme.textTheme.titleLarge,
      5 => theme.textTheme.titleMedium,
      6 => theme.textTheme.titleSmall,
      _ => theme.textTheme.bodyLarge,
    };
    final merged = (widget.baseStyle ?? const TextStyle()).merge(headingStyle);

    final (:spans, :renderedLength) = buildInlineSpans(
      widget.node.text,
      context,
      baseStyle: merged,
      onLinkTap: widget.onLinkTap,
      recognizers: _recognizers,
      latex: widget.latex,
      cjk: widget.cjk,
      animateConfig: widget.animateConfig,
      streaming: widget.streaming,
      prevContentLength: _animationStartLength,
      animationElapsedMs: _animationElapsedMs(context),
    );

    final result = Text.rich(TextSpan(children: spans));

    _renderedTextLength = renderedLength;

    if (widget.node.isComplete) {
      _cached = result;
    }

    return result;
  }

  void _startReveal(String appendedText) {
    final config = widget.animateConfig;
    if (!widget.streaming || config == null || appendedText.isEmpty) {
      _revealController.value = 1;
      return;
    }
    _animationTotalMs = inlineRevealDurationMs(appendedText, config);
    _revealController.duration = Duration(milliseconds: _animationTotalMs);
    _revealController.forward(from: 0);
  }

  double _animationElapsedMs(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return double.infinity;
    }
    return _revealController.value * _animationTotalMs;
  }
}

class _Paragraph extends StatefulWidget {
  const _Paragraph({
    super.key,
    required this.node,
    this.baseStyle,
    this.onLinkTap,
    this.latex = false,
    this.cjk = false,
    this.animateConfig,
    this.streaming = false,
    required this.keySeed,
  });

  final ParagraphNode node;
  final TextStyle? baseStyle;
  final void Function(Uri uri)? onLinkTap;
  final bool latex;
  final bool cjk;
  final AnimateConfig? animateConfig;
  final bool streaming;
  final int keySeed;

  @override
  State<_Paragraph> createState() => _ParagraphState();
}

class _ParagraphState extends State<_Paragraph>
    with SingleTickerProviderStateMixin {
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  Widget? _cached;
  late final AnimationController _revealController;
  int _renderedTextLength = 0;
  int _animationStartLength = 0;
  int _animationTotalMs = 1;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(vsync: this);
    _startReveal(widget.node.text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cached = null;
  }

  @override
  void didUpdateWidget(covariant _Paragraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming &&
        widget.animateConfig != null &&
        widget.node.text.startsWith(oldWidget.node.text) &&
        widget.node.text.length > oldWidget.node.text.length) {
      _animationStartLength = _renderedTextLength;
      _startReveal(widget.node.text.substring(oldWidget.node.text.length));
    } else if (!widget.streaming) {
      _revealController.value = 1;
      _animationStartLength = _renderedTextLength;
    }
    if (widget.node.text != oldWidget.node.text ||
        widget.node.isComplete != oldWidget.node.isComplete ||
        widget.baseStyle != oldWidget.baseStyle ||
        widget.onLinkTap != oldWidget.onLinkTap ||
        widget.animateConfig != oldWidget.animateConfig ||
        widget.streaming != oldWidget.streaming ||
        widget.latex != oldWidget.latex ||
        widget.cjk != oldWidget.cjk) {
      _cached = null;
      if (!widget.node.text.startsWith(oldWidget.node.text)) {
        _animationStartLength = _renderedTextLength;
        _revealController.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.streaming && widget.node.isComplete && _cached != null) {
      return _cached!;
    }
    if (!widget.streaming || widget.animateConfig == null) {
      return _buildText(context);
    }

    return AnimatedBuilder(
      animation: _revealController,
      builder: (context, _) => _buildText(context),
    );
  }

  Widget _buildText(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final (:spans, :renderedLength) = buildInlineSpans(
      widget.node.text,
      context,
      baseStyle: widget.baseStyle,
      onLinkTap: widget.onLinkTap,
      recognizers: _recognizers,
      latex: widget.latex,
      cjk: widget.cjk,
      animateConfig: widget.animateConfig,
      streaming: widget.streaming,
      prevContentLength: _animationStartLength,
      animationElapsedMs: _animationElapsedMs(context),
    );

    final result = Text.rich(TextSpan(children: spans));

    _renderedTextLength = renderedLength;

    if (widget.node.isComplete) {
      _cached = result;
    }

    return result;
  }

  void _startReveal(String appendedText) {
    final config = widget.animateConfig;
    if (!widget.streaming || config == null || appendedText.isEmpty) {
      _revealController.value = 1;
      return;
    }
    _animationTotalMs = inlineRevealDurationMs(appendedText, config);
    _revealController.duration = Duration(milliseconds: _animationTotalMs);
    _revealController.forward(from: 0);
  }

  double _animationElapsedMs(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return double.infinity;
    }
    return _revealController.value * _animationTotalMs;
  }
}

class _Blockquote extends StatelessWidget {
  const _Blockquote({
    super.key,
    required this.node,
    this.baseStyle,
    this.onLinkTap,
    this.latex = false,
    this.cjk = false,
    this.animateConfig,
    this.streaming = false,
    required this.keySeed,
  });

  final BlockquoteNode node;
  final TextStyle? baseStyle;
  final void Function(Uri uri)? onLinkTap;
  final bool latex;
  final bool cjk;
  final AnimateConfig? animateConfig;
  final bool streaming;
  final int keySeed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: <Widget>[
          for (final child in node.children) _renderInner(context, child),
        ],
      ),
    );
  }

  Widget _renderInner(BuildContext context, AstNode child) {
    return switch (child) {
      ParagraphNode() => _Paragraph(
        key: _nodeKey(child),
        node: child,
        baseStyle: baseStyle,
        onLinkTap: onLinkTap,
        latex: latex,
        cjk: cjk,
        animateConfig: animateConfig,
        streaming: streaming,
        keySeed: keySeed,
      ),
      HeadingNode() => _Heading(
        key: _nodeKey(child),
        node: child,
        baseStyle: baseStyle,
        onLinkTap: onLinkTap,
        latex: latex,
        cjk: cjk,
        animateConfig: animateConfig,
        streaming: streaming,
        keySeed: keySeed,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  ValueKey<String> _nodeKey(AstNode node) =>
      ValueKey<String>('$keySeed:${node.runtimeType}:${node.id}');
}

class _List extends StatelessWidget {
  const _List({
    super.key,
    required this.node,
    this.baseStyle,
    this.onLinkTap,
    this.latex = false,
    this.cjk = false,
    this.animateConfig,
    this.streaming = false,
    required this.keySeed,
  });

  final ListNode node;
  final TextStyle? baseStyle;
  final void Function(Uri uri)? onLinkTap;
  final bool latex;
  final bool cjk;
  final AnimateConfig? animateConfig;
  final bool streaming;
  final int keySeed;

  @override
  Widget build(BuildContext context) {
    final start = node.startNumber ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: <Widget>[
        for (var i = 0; i < node.items.length; i++)
          _ListItem(
            key: ValueKey<String>('$keySeed:list-item:$i'),
            node: node.items[i],
            marker: _markerFor(node, i, start),
            baseStyle: baseStyle,
            onLinkTap: onLinkTap,
            latex: latex,
            cjk: cjk,
            animateConfig: animateConfig,
            streaming: streaming,
            keySeed: keySeed,
          ),
      ],
    );
  }

  String _markerFor(ListNode list, int index, int start) {
    final item = list.items[index];
    if (item.isTask) {
      return item.isChecked ? '☑' : '☐';
    }
    return list.ordered ? '${start + index}.' : '•';
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({
    super.key,
    required this.node,
    required this.marker,
    this.baseStyle,
    this.onLinkTap,
    this.latex = false,
    this.cjk = false,
    this.animateConfig,
    this.streaming = false,
    required this.keySeed,
  });

  final ListItemNode node;
  final String marker;
  final TextStyle? baseStyle;
  final void Function(Uri uri)? onLinkTap;
  final bool latex;
  final bool cjk;
  final AnimateConfig? animateConfig;
  final bool streaming;
  final int keySeed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 24, child: Text(marker, textAlign: TextAlign.right)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: <Widget>[
              for (final (index, child) in node.children.indexed)
                if (child is ParagraphNode)
                  _Paragraph(
                    key: ValueKey<String>('$keySeed:list-paragraph:$index'),
                    node: child,
                    baseStyle: baseStyle,
                    onLinkTap: onLinkTap,
                    latex: latex,
                    cjk: cjk,
                    animateConfig: animateConfig,
                    streaming: streaming,
                    keySeed: keySeed,
                  )
                else
                  const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
