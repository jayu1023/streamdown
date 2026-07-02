// Streaming animation helpers.
//
// Prose must remain a continuous TextSpan run. TextSpans participate in one
// native paragraph layout; WidgetSpans do not and must never be used for
// ordinary animated text.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Mirrors React's AnimateOptions.animation.
enum AnimationType { fadeIn, blurIn, slideUp }

/// Controls how streaming text is split for inline animation.
enum AnimationSeparator { word, char }

/// Mirrors React's AnimateOptions.
class AnimateConfig {
  const AnimateConfig({
    this.animation = AnimationType.fadeIn,
    this.duration = 150,
    this.sep = AnimationSeparator.word,
    this.stagger = 40,
  });

  final AnimationType animation;
  final int duration;

  final AnimationSeparator sep;

  final int stagger;

  List<Effect<dynamic>> effects(double delayMs) {
    final d = Duration(milliseconds: duration);
    final delay = Duration(milliseconds: delayMs.round());
    switch (animation) {
      case AnimationType.blurIn:
        return [
          BlurEffect(begin: const Offset(0, 6), end: Offset.zero, delay: delay),
          FadeEffect(begin: 0, end: 1, duration: d, delay: delay),
        ];
      case AnimationType.slideUp:
        return [
          MoveEffect(begin: const Offset(0, 8), end: Offset.zero, delay: delay),
          FadeEffect(begin: 0, end: 1, duration: d, delay: delay),
        ];
      case AnimationType.fadeIn:
        return [FadeEffect(begin: 0, end: 1, duration: d, delay: delay)];
    }
  }
}

/// Builds native inline spans for a plain-text run. Splitting a RichText into
/// TextSpans does not change Flutter's paragraph line breaking.
int buildAnimatedSpans(
  String text,
  TextStyle style, {
  required AnimateConfig? config,
  required bool streaming,
  required int prevContentLength,
  required int charOffset,
  required List<InlineSpan> out,
  double animationElapsedMs = double.infinity,
  int newSpanOffset = 0,
}) {
  final oldLength = (prevContentLength - charOffset).clamp(0, text.length);
  if (oldLength > 0) {
    out.add(TextSpan(text: text.substring(0, oldLength), style: style));
  }

  final appended = text.substring(oldLength);
  if (!streaming || config == null || appended.isEmpty) {
    if (appended.isNotEmpty) out.add(TextSpan(text: appended, style: style));
    return charOffset + text.length;
  }

  final parts = config.sep == AnimationSeparator.char
      ? _splitCharacters(appended)
      : _splitWords(appended);
  var animatedIndex = newSpanOffset;
  for (final part in parts) {
    if (part.trim().isEmpty) {
      out.add(TextSpan(text: part, style: style));
      continue;
    }
    final opacity =
        ((animationElapsedMs - animatedIndex * config.stagger) /
                config.duration)
            .clamp(0.0, 1.0);
    final color = style.color;
    out.add(
      TextSpan(
        text: part,
        style: color == null
            ? style
            : style.copyWith(color: color.withValues(alpha: color.a * opacity)),
      ),
    );
    animatedIndex += 1;
  }
  return charOffset + text.length;
}

List<String> _splitWords(String text) =>
    RegExp(r'\s+|\S+').allMatches(text).map((match) => match[0]!).toList();

List<String> _splitCharacters(String text) => text.characters.toList();

int inlineRevealDurationMs(String appendedText, AnimateConfig config) {
  final count = animatedSegmentCount(appendedText, config);
  if (count <= 1) return config.duration;
  return config.duration + (count - 1) * config.stagger;
}

int animatedSegmentCount(String text, AnimateConfig config) =>
    config.sep == AnimationSeparator.char
    ? text.characters.where((char) => char.trim().isNotEmpty).length
    : RegExp(r'\S+').allMatches(text).length;

// ──────────────────────────────────────────────────────────────────────────
// Block-level helpers (kept from earlier)
// ──────────────────────────────────────────────────────────────────────────

class StreamdownAnimatedBlock extends StatefulWidget {
  const StreamdownAnimatedBlock({
    super.key,
    required this.child,
    this.enabled = false,
    this.config,
  });

  final Widget child;
  final bool enabled;
  final AnimateConfig? config;

  @override
  State<StreamdownAnimatedBlock> createState() =>
      _StreamdownAnimatedBlockState();
}

class _StreamdownAnimatedBlockState extends State<StreamdownAnimatedBlock>
    with SingleTickerProviderStateMixin {
  var _animate = false;

  @override
  void initState() {
    super.initState();
    _animate = widget.enabled;
  }

  @override
  void didUpdateWidget(covariant StreamdownAnimatedBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != oldWidget.key || widget.enabled != oldWidget.enabled) {
      _animate = widget.enabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    final config = widget.config;
    if (config == null) {
      return widget.child.animate().fadeIn(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    return Animate(effects: config.effects(0), child: widget.child);
  }
}

class StreamdownCaret extends StatefulWidget {
  const StreamdownCaret({super.key});

  @override
  State<StreamdownCaret> createState() => _StreamdownCaretState();
}

class _StreamdownCaretState extends State<StreamdownCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: Curves.easeInOut)),
      child: Text(' ▋', style: DefaultTextStyle.of(context).style),
    );
  }
}
