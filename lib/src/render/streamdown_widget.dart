// Public Streamdown widget.
//
// Two construction modes:
//   * `Streamdown(stream: ...)` — incremental rendering of a token stream
//     emitting markdown chunks (typical AI chat use case).
//   * `Streamdown.text(...)` — render a complete markdown string in one shot.
//
// Both modes share the same incremental path internally; the static
// constructor just feeds the entire string and immediately completes.

import 'dart:async';

import 'package:flutter/material.dart';

import '../parser/parser.dart';
import '../parser/remend.dart';
import '../parser/tokenizer.dart';
import 'animation.dart';
import 'ast_renderer.dart';
import 'syntax_theme.dart';

class Streamdown extends StatefulWidget {
  /// Streaming constructor — render markdown as chunks arrive on [stream].
  const Streamdown({
    super.key,
    required Stream<String> stream,
    this.textStyle,
    this.selectable = true,
    this.onLinkTap,
    this.padding,
    this.syntaxTheme,
    this.codeBlockBuilder,
    this.latex = false,
    this.errorBuilder,
    this.parseIncompleteMarkdown = true,
    this.remendOptions,
    this.lineNumbers = true,
    this.cjk = false,
    this.animated = false,
    this.animateConfig,
    this.showCaret = false,
  }) : _stream = stream,
       _text = null;

  /// Static constructor — render a complete markdown string.
  const Streamdown.text(
    String text, {
    super.key,
    this.textStyle,
    this.selectable = true,
    this.onLinkTap,
    this.padding,
    this.syntaxTheme,
    this.codeBlockBuilder,
    this.latex = false,
    this.errorBuilder,
    this.parseIncompleteMarkdown = true,
    this.remendOptions,
    this.lineNumbers = true,
    this.cjk = false,
    this.animated = false,
    this.animateConfig,
    this.showCaret = false,
  }) : _stream = null,
       _text = text;

  final Stream<String>? _stream;
  final String? _text;

  final TextStyle? textStyle;
  final bool selectable;
  final void Function(Uri uri)? onLinkTap;
  final EdgeInsetsGeometry? padding;
  final SyntaxTheme? syntaxTheme;
  final CodeBlockBuilder? codeBlockBuilder;
  final bool latex;
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  )?
  errorBuilder;
  final bool parseIncompleteMarkdown;
  final RemendOptions? remendOptions;
  final bool lineNumbers;
  final bool cjk;
  final bool animated;
  final AnimateConfig? animateConfig;
  final bool showCaret;

  @override
  State<Streamdown> createState() => _StreamdownState();
}

class _StreamdownState extends State<Streamdown> {
  Tokenizer _tokenizer = Tokenizer();
  Parser _parser = Parser();
  StreamSubscription<String>? _sub;
  Object? _streamError;
  StackTrace? _streamStack;
  String _accumulatedBuffer = '';
  int _renderGeneration = 0;
  bool _streamActive = false;
  bool _rebuildScheduled = false;

  void _scheduleRebuild() {
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    scheduleMicrotask(() {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _initPipeline();
  }

  @override
  void didUpdateWidget(covariant Streamdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final streamChanged = widget._stream != oldWidget._stream;
    final textChanged = widget._text != oldWidget._text;
    if (streamChanged || textChanged) {
      _sub?.cancel();
      _initPipeline();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _initPipeline() {
    _tokenizer = Tokenizer();
    _parser = Parser();
    _renderGeneration += 1;
    _streamError = null;
    _streamStack = null;
    _accumulatedBuffer = '';
    _streamActive = true;
    _rebuildScheduled = false;
    final text = widget._text;
    if (text != null) {
      _consume(text);
      _completeStream();
      return;
    }
    final stream = widget._stream;
    if (stream != null) {
      _sub = stream.listen(
        _consume,
        onDone: _completeStream,
        onError: _onStreamError,
        cancelOnError: false,
      );
    }
  }

  void _onStreamError(Object error, StackTrace stack) {
    if (!mounted) return;
    setState(() {
      _streamError = error;
      _streamStack = stack;
    });
  }

  void _consume(String chunk) {
    _accumulatedBuffer += chunk;
    if (widget.parseIncompleteMarkdown) {
      final healed = remend(_accumulatedBuffer, widget.remendOptions);
      _tokenizer = Tokenizer();
      _parser = Parser();
      _parser.feed(_tokenizer.feed(healed));
      _parser.feed(_tokenizer.complete());
    } else {
      _parser.feed(_tokenizer.feed(chunk));
    }
    if (mounted) _scheduleRebuild();
  }

  void _completeStream() {
    if (widget.parseIncompleteMarkdown) {
      // The streaming snapshots are healed provisionally. Reconcile the final
      // raw source through the same renderer instead of leaving synthetic
      // remend characters in the completed document.
      _tokenizer = Tokenizer();
      _parser = Parser();
      _parser.feed(_tokenizer.feed(_accumulatedBuffer));
    }
    _parser.feed(_tokenizer.complete());
    _parser.complete();
    _streamActive = false;
    if (mounted) _scheduleRebuild();
  }

  @override
  Widget build(BuildContext context) {
    if (_streamError != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _streamError!, _streamStack);
    }
    final animateConfig =
        widget.animateConfig ??
        (widget.animated ? const AnimateConfig() : null);

    final renderer = AstRenderer(
      document: _parser.document,
      keySeed: _renderGeneration,
      textStyle: widget.textStyle,
      onLinkTap: widget.onLinkTap,
      syntaxTheme: widget.syntaxTheme ?? SyntaxTheme.auto(context),
      codeBlockBuilder: widget.codeBlockBuilder,
      latex: widget.latex,
      cjk: widget.cjk,
      lineNumbers: widget.lineNumbers,
      animated: widget.animated && _streamActive,
      showCaret: widget.showCaret && _streamActive,
      animateConfig: _streamActive ? animateConfig : null,
    );
    final padded = widget.padding != null
        ? Padding(padding: widget.padding!, child: renderer)
        : renderer;
    return widget.selectable ? SelectionArea(child: padded) : padded;
  }
}
