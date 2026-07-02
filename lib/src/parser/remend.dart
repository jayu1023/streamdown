// Self-healing markdown preprocessor — Dart port of remend.
//
// Fixes  incomplete markdown formatting thatarrives mid-stream (unclosed bold,
// unclosed code spans, incomplete links, etc.) so the renderer never sees
// broken syntax. Runs on the accumulated buffer BEFORE the tokenizer.
//
// Pure Dart, zero dependencies. All handlers are context-aware (skip content
// inside fenced code blocks, inline code, math blocks, link URLs).

/// Configuration for the remend self-healing preprocessor.
class RemendOptions {
  const RemendOptions({
    this.bold = true,
    this.boldItalic = true,
    this.comparisonOperators = true,
    this.htmlTags = true,
    this.images = true,
    this.inlineCode = true,
    this.inlineKatex = false,
    this.italic = true,
    this.katex = true,
    this.linkMode = RemendLinkMode.protocol,
    this.links = true,
    this.setextHeadings = true,
    this.singleTilde = true,
    this.strikethrough = true,
    this.handlers = const [],
  });

  final bool bold;
  final bool boldItalic;
  final bool comparisonOperators;
  final bool htmlTags;
  final bool images;
  final bool inlineCode;
  final bool inlineKatex;
  final bool italic;
  final bool katex;
  final RemendLinkMode linkMode;
  final bool links;
  final bool setextHeadings;
  final bool singleTilde;
  final bool strikethrough;
  final List<RemendHandler> handlers;
}

enum RemendLinkMode { protocol, textOnly }

/// A custom remend handler that can be inserted into the pipeline.
abstract class RemendHandler {
  String get name;
  int get priority => 100;
  String handle(String text);
}

/// Run the remend pipeline on [text] and return the healed string.
String remend(String text, [RemendOptions? options]) {
  if (text.isEmpty) return text;

  final opts = options ?? const RemendOptions();

  // Strip single trailing space (markdown treats `text ` same as `text`).
  // Preserve double space (markdown line break).
  // Only strip if the space is NOT followed by more text on the same line.
  if (text.endsWith(' ') && !text.endsWith('  ')) {
    text = text.substring(0, text.length - 1);
  }

  // Collect all handlers: built-in + custom, sorted by priority.
  final allHandlers = <_HandlerEntry>[];

  if (opts.singleTilde) {
    allHandlers.add(_HandlerEntry(0, _handleSingleTildeEscape));
  }
  if (opts.comparisonOperators) {
    allHandlers.add(_HandlerEntry(5, _handleComparisonOperators));
  }
  if (opts.htmlTags) {
    allHandlers.add(_HandlerEntry(10, _handleIncompleteHtmlTag));
  }
  if (opts.setextHeadings) {
    allHandlers.add(_HandlerEntry(15, _handleIncompleteSetextHeading));
  }
  if (opts.links || opts.images) {
    final bool Function(String)? earlyReturn;
    if (opts.linkMode == RemendLinkMode.protocol) {
      earlyReturn = (r) => r.endsWith('](streamdown:incomplete-link)');
    } else {
      earlyReturn = null;
    }
    allHandlers.add(_HandlerEntry(
      20,
      (t) => _handleIncompleteLinksAndImages(t, opts.linkMode),
      earlyReturn,
    ));
  }
  if (opts.boldItalic) {
    allHandlers.add(_HandlerEntry(30, _handleIncompleteBoldItalic));
  }
  if (opts.bold) {
    allHandlers.add(_HandlerEntry(35, _handleIncompleteBold));
  }
  if (opts.italic) {
    allHandlers.add(_HandlerEntry(40, _handleIncompleteDoubleUnderscoreItalic));
    allHandlers.add(_HandlerEntry(41, _handleIncompleteSingleAsteriskItalic));
    allHandlers.add(_HandlerEntry(42, _handleIncompleteSingleUnderscoreItalic));
  }
  if (opts.inlineCode) {
    allHandlers.add(_HandlerEntry(50, _handleIncompleteInlineCode));
  }
  if (opts.strikethrough) {
    allHandlers.add(_HandlerEntry(60, _handleIncompleteStrikethrough));
  }
  if (opts.katex) {
    allHandlers.add(_HandlerEntry(70, _handleIncompleteBlockKatex));
  }
  if (opts.inlineKatex) {
    allHandlers.add(_HandlerEntry(75, _handleIncompleteInlineKatex));
  }
  for (final handler in opts.handlers) {
    allHandlers.add(_HandlerEntry(handler.priority, handler.handle));
  }

  allHandlers.sort((a, b) => a.priority.compareTo(b.priority));

  for (final entry in allHandlers) {
    text = entry.handler(text);
    if (entry.earlyReturn != null && entry.earlyReturn!(text)) {
      return text;
    }
  }

  return text;
}

class _HandlerEntry {
  const _HandlerEntry(this.priority, this.handler, [this.earlyReturn]);
  final int priority;
  final String Function(String) handler;
  final bool Function(String)? earlyReturn;
}

// ═══════════════════════════════════════════════════════════════════════════
// Context detection utilities
// ═══════════════════════════════════════════════════════════════════════════

/// Returns true if [position] is inside a fenced code block (between ``` markers).
bool isWithinCodeBlock(String text, int position) {
  var inCodeBlock = false;
  var i = 0;
  while (i < text.length && i < position) {
    if (i + 2 < text.length &&
        text[i] == '`' && text[i + 1] == '`' && text[i + 2] == '`') {
      inCodeBlock = !inCodeBlock;
      i += 3;
      while (i < text.length && text[i] != '\n') {
        i++;
      }
      continue;
    }
    i++;
  }
  return inCodeBlock;
}

/// Returns true if [position] is inside a completed inline code span
/// (both opening and closing backtick present).
bool isWithinCompleteInlineCode(String text, int position) {
  var i = 0;
  while (i < text.length && i < position) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        // Fenced code block — skip to closing fence
        i += runLen;
        while (i < text.length) {
          if (text[i] == '`') {
            final closeLen = _countRun(text, i);
            if (closeLen >= runLen) {
              i = i + closeLen;
              break;
            }
            i += closeLen;
          } else {
            i++;
          }
        }
        continue;
      }
      // Inline code — find matching close
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        if (position > i && position < closeIdx + runLen) {
          return true;
        }
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    i++;
  }
  return false;
}

int _findInlineCodeClose(String text, int from, int runLen) {
  var i = from;
  while (i < text.length) {
    if (text[i] == '`') {
      var n = 0;
      while (i + n < text.length && text[i + n] == '`') {
        n++;
      }
      if (n == runLen) return i;
      i += n;
      continue;
    }
    i++;
  }
  return -1;
}

int _countRun(String text, int start) {
  var n = 0;
  while (start + n < text.length && text[start + n] == text[start]) {
    n++;
  }
  return n;
}

/// Returns true if [position] is inside a math block ($$...$) or inline math ($...$).
bool isWithinMathBlock(String text, int position) {
  var i = 0;
  var inBlock = false;
  var inInline = false;
  while (i < text.length && i < position) {
    if (i + 1 < text.length && text[i] == r'$' && text[i + 1] == r'$') {
      inBlock = !inBlock;
      i += 2;
      continue;
    }
    if (text[i] == r'$' && !inBlock) {
      inInline = !inInline;
      i++;
      continue;
    }
    if (text[i] == '\\' && i + 1 < text.length && text[i + 1] == r'$') {
      i += 2;
      continue;
    }
    i++;
  }
  return inBlock || inInline;
}

/// Returns true if [position] is inside a link or image URL (between `(` and `)`).
bool isWithinLinkOrImageUrl(String text, int position) {
  var i = position - 1;
  // Search backwards for `)`, `(`, or `\n`
  while (i >= 0) {
    final c = text[i];
    if (c == ')') return false;
    if (c == '(') {
      // Check if preceded by `]`
      if (i > 0 && text[i - 1] == ']') {
        return true;
      }
      return false;
    }
    if (c == '\n') return false;
    i--;
  }
  return false;
}

/// Returns true if [position] is inside an HTML tag.
bool _isWithinHtmlTag(String text, int position) {
  var i = position - 1;
  while (i >= 0) {
    final c = text[i];
    if (c == '>') return false;
    if (c == '<') {
      if (i + 1 < text.length) {
        final next = text.codeUnitAt(i + 1);
        if ((next >= 0x61 && next <= 0x7A) || // a-z
            (next >= 0x41 && next <= 0x5A) || // A-Z
            next == 0x2F) { // /
          return true;
        }
      }
      return false;
    }
    if (c == '\n') return false;
    i--;
  }
  return false;
}

bool _isHorizontalRule(String text, int markerIndex, String marker) {
  // Find the line containing markerIndex
  final searchEnd = markerIndex > 0 ? markerIndex - 1 : 0;
  var lineStart = text.lastIndexOf('\n', searchEnd) + 1;
  var lineEnd = text.indexOf('\n', markerIndex);
  if (lineEnd == -1) lineEnd = text.length;
  final line = text.substring(lineStart, lineEnd).trim();
  if (line.isEmpty) return false;
  // Check if the line is 3+ of the marker character
  final ch = line[0];
  if (ch != '-' && ch != '*' && ch != '_') return false;
  for (var i = 1; i < line.length; i++) {
    final c = line[i];
    if (c != ch && c != ' ' && c != '\t') return false;
  }
  final stripped = line.replaceAll(' ', '').replaceAll('\t', '');
  return stripped.length >= 3 && stripped.split('').every((c) => c == ch);
}

bool _isWordChar(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || // 0-9
      (code >= 0x41 && code <= 0x5A) || // A-Z
      (code >= 0x61 && code <= 0x7A) || // a-z
      code == 0x5F || // _
      code >= 0x80; // non-ASCII
}

// ═══════════════════════════════════════════════════════════════════════════
// Handler implementations
// ═══════════════════════════════════════════════════════════════════════════

// Priority 0: Escape single tilde between word characters.
String _handleSingleTildeEscape(String text) {
  if (!text.contains('~')) return text;
  if (isWithinCodeBlock(text, text.indexOf('~'))) return text;

  final result = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text[i] == '~' &&
        i > 0 &&
        i + 1 < text.length &&
        _isWordChar(text[i - 1]) &&
        _isWordChar(text[i + 1]) &&
        (i + 1 >= text.length || text[i + 1] != '~')) {
      result.write(r'\~');
      i++;
      continue;
    }
    result.write(text[i]);
    i++;
  }
  return result.toString();
}

// Priority 5: Escape > in list items that are comparison operators.
String _handleComparisonOperators(String text) {
  if (!text.contains('>')) return text;
  if (isWithinCodeBlock(text, text.indexOf('>'))) return text;

  return text.replaceAllMapped(
    RegExp(r'^(\s*(?:[-*+]|\d+[.)]) +)>(=?\s*[$]?\d)', multiLine: true),
    (m) => '${m.group(1)!}\\>${m.group(2)!}',
  );
}

// Priority 10: Strip incomplete HTML tags at end of text.
String _handleIncompleteHtmlTag(String text) {
  final match = RegExp(r'<[a-zA-Z/][^>]*$').firstMatch(text);
  if (match == null) return text;
  if (isWithinCodeBlock(text, match.start)) return text;
  return text.substring(0, match.start).trimRight();
}

// Priority 15: Prevent setext heading misinterpretation.
String _handleIncompleteSetextHeading(String text) {
  final lastNewline = text.lastIndexOf('\n');
  if (lastNewline == -1) return text;

  final lastLine = text.substring(lastNewline + 1).trim();
  if (lastLine.isEmpty) return text;

  // Only 1-2 dashes or equals (3+ are horizontal rules)
  if (RegExp(r'^-{1,2}$').hasMatch(lastLine) ||
      RegExp(r'^={1,2}$').hasMatch(lastLine)) {
    // Must have trailing space after dashes/equals? No — if exactly 1-2
    // markers, break the pattern with zero-width space.
    if (lastLine.length <= 2) {
      return '$text\u200B';
    }
  }
  return text;
}

// Priority 20: Complete incomplete links and strip incomplete images.
String _handleIncompleteLinksAndImages(String text, RemendLinkMode mode) {
  // Phase 1: Handle ]( pattern — incomplete URL (no closing paren yet).
  // Find the LAST ]( in the text (handles nested brackets correctly).
  final closeParen = text.lastIndexOf('](');
  if (closeParen != -1) {
    // Only treat as incomplete if there's no closing ) after the (
    if (closeParen + 2 >= text.length || !text.contains(')', closeParen + 2)) {
      // Search backward from closeParen to find the matching [
      var depth = 0;
      var linkStart = -1;
      for (var i = closeParen; i >= 0; i--) {
        if (text[i] == ']') {
          depth++;
        } else if (text[i] == '[') {
          depth--;
          if (depth == 0) {
            linkStart = i;
            break;
          }
        }
      }
      if (linkStart != -1) {
        final isImage = linkStart > 0 && text[linkStart - 1] == '!';
        final prefixEnd = isImage ? linkStart - 1 : linkStart;
        final prefix = text.substring(0, prefixEnd);
        final linkText = text.substring(linkStart + 1, closeParen);

        if (isImage) {
          return prefix; // Strip incomplete image entirely
        }
        if (mode == RemendLinkMode.textOnly) {
          return prefix + linkText;
        }
        return '$prefix[$linkText](streamdown:incomplete-link)';
      }
    }
  }

  // Phase 2: Handle [ without ] — incomplete text.
  // Find the LAST [ in the text; if there's no matching ] after it,
  // treat it as an unclosed link.
  var bracketPos = -1;
  final lastBracket = text.lastIndexOf('[');
  if (lastBracket != -1) {
    final closeIdx = text.indexOf(']', lastBracket);
    if (closeIdx == -1) {
      bracketPos = lastBracket;
    }
  }

  if (bracketPos != -1) {
    final isImage = bracketPos > 0 && text[bracketPos - 1] == '!';
    final prefixEnd = isImage ? bracketPos - 1 : bracketPos;
    final prefix = text.substring(0, prefixEnd);

    if (isImage) {
      return prefix; // Strip incomplete image entirely
    }

    final linkText = text.substring(bracketPos + 1);
    if (mode == RemendLinkMode.textOnly) {
      return prefix + linkText;
    }
    return '$prefix[$linkText](streamdown:incomplete-link)';
  }

  return text;
}

// Priority 30: Complete incomplete bold-italic ***.
String _handleIncompleteBoldItalic(String text) {
  if (RegExp(r'^\*{4,}$').hasMatch(text)) return text;

  final match = RegExp(r'(\*\*\*)([^*]*?)$').firstMatch(text);
  if (match == null) return text;
  if (isWithinCodeBlock(text, match.start)) return text;

  final content = match.group(2)!;
  if (content.trim().isEmpty) return text;

  final markerStart = match.start;
  if (_isHorizontalRule(text, markerStart, '*')) return text;

  // Count triple-asterisk groups
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (i + 2 < text.length &&
        text[i] == '*' && text[i + 1] == '*' && text[i + 2] == '*' &&
        (i == 0 || text[i - 1] != '*') &&
        (i + 3 >= text.length || text[i + 3] != '*')) {
      count++;
    }
    i++;
  }

  if (count.isOdd) {
    // Check if ** and * are both balanced (e.g., `**bold and *italic***`)
    final doubleCount = _countDoubleAsterisksOutsideCode(text);
    final singleCount = _countSingleAsterisksOutsideCode(text);
    if (doubleCount.isEven && singleCount.isEven) {
      // The *** is closing both, not opening bold-italic
      return text;
    }
    return '$text***';
  }
  return text;
}

// Priority 35: Complete incomplete bold **.
String _handleIncompleteBold(String text) {
  final match = RegExp(r'(\*\*)((?:[^*]|\*(?!\*))*)$').firstMatch(text);
  if (match == null) return text;
  if (isWithinCodeBlock(text, match.start)) return text;

  final content = match.group(2)!;
  if (content.trim().isEmpty) return text;

  final markerStart = match.start;
  if (_isHorizontalRule(text, markerStart, '*')) return text;

  // Check if inside a list item with multiline content
  if (_isInsideListItem(text, markerStart)) return text;

  final count = _countDoubleAsterisksOutsideCode(text);
  if (count.isOdd) {
    if (content.endsWith('*')) {
      return '$text*'; // Half-complete closing
    }
    return '$text**';
  }
  return text;
}

// Priority 40: Complete incomplete double-underscore italic __.
String _handleIncompleteDoubleUnderscoreItalic(String text) {
  final match = RegExp(r'(__)([^_]*?)$').firstMatch(text);
  if (match != null) {
    if (isWithinCodeBlock(text, match.start)) return text;
    final content = match.group(2)!;
    if (content.trim().isEmpty) return text;

    final markerStart = match.start;
    if (_isHorizontalRule(text, markerStart, '_')) return text;
    if (_isInsideListItem(text, markerStart)) return text;

    final count = _countDoubleUnderscoresOutsideCode(text);
    if (count.isOdd) {
      return '${text}__';
    }
  }

  // Check half-complete closing: __content_
  final halfMatch = RegExp(r'(__)([^_]+)_$').firstMatch(text);
  if (halfMatch != null) {
    if (isWithinCodeBlock(text, halfMatch.start)) return text;
    final count = _countDoubleUnderscoresOutsideCode(text);
    if (count.isOdd) {
      return '${text}_';
    }
  }

  return text;
}

// Priority 41: Complete incomplete single-asterisk italic *.
String _handleIncompleteSingleAsteriskItalic(String text) {
  // Skip if text ends with **, ***, or more (handled by bold/boldItalic)
  if (RegExp(r'\*{2,}$').hasMatch(text)) return text;

  final match = RegExp(r'(\*)([^*]*?)$').firstMatch(text);
  if (match == null) return text;
  if (isWithinCodeBlock(text, match.start)) return text;

  final markerIndex = match.start;
  if (_isHorizontalRule(text, markerIndex, '*')) return text;
  if (isWithinMathBlock(text, markerIndex)) return text;

  // Skip if part of a ** pair (not an italic delimiter)
  if (markerIndex > 0 && text[markerIndex - 1] == '*') return text;

  // Skip word-internal asterisks
  if (markerIndex > 0 && markerIndex + 1 < text.length &&
      _isWordChar(text[markerIndex - 1]) &&
      _isWordChar(text[markerIndex + 1])) {
    return text;
  }

  final content = match.group(2)!;
  if (content.trim().isEmpty) return text;

  final count = _countSingleAsterisksOutsideCode(text);
  if (count.isOdd) {
    return '$text*';
  }
  return text;
}

// Priority 42: Complete incomplete single-underscore italic _.
String _handleIncompleteSingleUnderscoreItalic(String text) {
  // Skip if text ends with __ or more (handled by double underscore)
  if (RegExp(r'_{2,}$').hasMatch(text)) return text;

  final match = RegExp(r'(_)([^_]*?)$').firstMatch(text);
  if (match == null) return text;
  if (isWithinCodeBlock(text, match.start)) return text;

  final markerIndex = match.start;
  if (_isHorizontalRule(text, markerIndex, '_')) return text;
  if (isWithinMathBlock(text, markerIndex)) return text;
  if (isWithinLinkOrImageUrl(text, markerIndex)) return text;
  if (_isWithinHtmlTag(text, markerIndex)) return text;

  // Skip word-internal underscores
  if (markerIndex > 0 && markerIndex + 1 < text.length &&
      _isWordChar(text[markerIndex - 1]) &&
      _isWordChar(text[markerIndex + 1])) {
    return text;
  }

  final content = match.group(2)!;
  if (content.trim().isEmpty) return text;

  final count = _countSingleUnderscoresOutsideCode(text);
  if (count.isOdd) {
    // Handle trailing asterisks — underscore closes before **
    if (text.endsWith('*') || text.endsWith('**')) {
      // Insert closing _ before trailing asterisks
      final trailingStarLen = _trailingCharCount(text, '*');
      final before = text.substring(0, text.length - trailingStarLen);
      return '${before}_';
    }
    return '${text}_';
  }
  return text;
}

// Priority 50: Complete incomplete inline code `.
String _handleIncompleteInlineCode(String text) {
  // Check inline triple backticks first (no newlines allowed)
  if (text.contains('```') && !text.contains('\n')) {
    // Pattern: 3+ backticks, content, then 0-2 closing backticks (incomplete)
    final tripleMatch = RegExp(r'^```[^`\n]*``?$').firstMatch(text);
    if (tripleMatch != null && text.endsWith('`')) {
      if (text.endsWith('```')) {
        // Already complete (3 opening, 3 closing) — no change
        return text;
      } else if (text.endsWith('``')) {
        // 2 backticks at end — add 1 more to close
        return '$text`';
      } else {
        // 1 backtick at end — add 2 more
        return '$text``';
      }
    }
  }

  // Count backticks at the end
  var endBackticks = 0;
  var i = text.length - 1;
  while (i >= 0 && text[i] == '`') {
    endBackticks++;
    i--;
  }

  // Check if we're inside a code block
  if (endBackticks > 0 && isWithinCodeBlock(text, text.length - endBackticks)) {
    return text;
  }

  // If we're inside an incomplete fenced code block (odd triple backticks), skip
  var tripleCount = 0;
  var j = 0;
  final checkEnd = endBackticks > 0 ? text.length - endBackticks : text.length;
  while (j < checkEnd) {
    if (j + 2 < text.length &&
        text[j] == '`' && text[j + 1] == '`' && text[j + 2] == '`') {
      tripleCount++;
      j += 3;
      continue;
    }
    j++;
  }
  if (tripleCount.isOdd) return text;

  // Count single backticks
  final singleCount = _countSingleBackticksOutsideCode(text);
  if (singleCount.isOdd) {
    // Don't complete lone backtick(s) with no content
    if (text.replaceAll('`', '').trim().isEmpty) return text;
    return '$text`';
  }

  return text;
}

// Priority 60: Complete incomplete strikethrough ~~.
String _handleIncompleteStrikethrough(String text) {
  final match = RegExp(r'(~~)([^~]*?)$').firstMatch(text);
  if (match != null) {
    if (isWithinCodeBlock(text, match.start)) return text;
    final content = match.group(2)!;
    if (content.trim().isEmpty) return text;

    // Check if ~~ is preceded by a word character (not a space or start of text)
    // If so, it's likely not an opening strikethrough delimiter
    final markerIndex = match.start;
    if (markerIndex > 0 && _isWordChar(text[markerIndex - 1])) {
      return text;
    }

    final count = _countDoubleTildesOutsideCode(text);
    if (count.isOdd) {
      return '$text~~';
    }
  }

  // Check half-complete closing: ~~content~
  final halfMatch = RegExp(r'(~~)([^~]+)~$').firstMatch(text);
  if (halfMatch != null) {
    if (isWithinCodeBlock(text, halfMatch.start)) return text;
    final count = _countDoubleTildesOutsideCode(text);
    if (count.isOdd) {
      return '$text~';
    }
  }

  return text;
}

// Priority 70: Complete incomplete block KaTeX $$.
String _handleIncompleteBlockKatex(String text) {
  final count = _countDollarPairsOutsideCode(text);
  if (count.isOdd) {
    if (text.endsWith('\$') && !text.endsWith('\$\$')) {
      return '$text\$';
    }
    if (text.contains('\n')) {
      return '$text\n\$\$';
    }
    return '$text\$\$';
  }
  return text;
}

// Priority 75: Complete incomplete inline KaTeX $.
String _handleIncompleteInlineKatex(String text) {
  final count = _countSingleDollarsOutsideCode(text);
  if (count.isOdd) {
    return '$text\$';
  }
  return text;
}

// ═══════════════════════════════════════════════════════════════════════════
// Counting helpers
// ═══════════════════════════════════════════════════════════════════════════

int _countDoubleAsterisksOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        i += runLen;
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
      count++;
      i += 2;
      continue;
    }
    i++;
  }
  return count;
}

int _countSingleAsterisksOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        i += runLen;
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    if (text[i] == '*' &&
        (i + 1 >= text.length || text[i + 1] != '*')) {
      // Skip escaped
      if (i > 0 && text[i - 1] == '\\') {
        i++;
        continue;
      }
      count++;
      i++;
      continue;
    }
    i++;
  }
  return count;
}

int _countDoubleUnderscoresOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        i += runLen;
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    if (i + 1 < text.length && text[i] == '_' && text[i + 1] == '_') {
      count++;
      i += 2;
      continue;
    }
    i++;
  }
  return count;
}

int _countSingleUnderscoresOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        i += runLen;
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    if (text[i] == '_' &&
        (i + 1 >= text.length || text[i + 1] != '_')) {
      if (i > 0 && text[i - 1] == '\\') {
        i++;
        continue;
      }
      count++;
      i++;
      continue;
    }
    i++;
  }
  return count;
}

int _countDoubleTildesOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        i += runLen;
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    if (i + 1 < text.length && text[i] == '~' && text[i + 1] == '~') {
      count++;
      i += 2;
      continue;
    }
    i++;
  }
  return count;
}

int _countDollarPairsOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        i += runLen;
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    if (i + 1 < text.length && text[i] == r'$' && text[i + 1] == r'$') {
      count++;
      i += 2;
      continue;
    }
    i++;
  }
  return count;
}

int _countSingleDollarsOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        i += runLen;
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      i++;
      continue;
    }
    // Skip $$
    if (i + 1 < text.length && text[i] == r'$' && text[i + 1] == r'$') {
      i += 2;
      continue;
    }
    if (text[i] == r'$') {
      count++;
      i++;
      continue;
    }
    i++;
  }
  return count;
}

int _countSingleBackticksOutsideCode(String text) {
  var count = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '`') {
      final runLen = _countRun(text, i);
      if (runLen >= 3) {
        // Fenced code block — skip to closing fence
        i += runLen;
        while (i < text.length) {
          if (text[i] == '`') {
            final closeLen = _countRun(text, i);
            if (closeLen >= runLen) {
              i = i + closeLen;
              break;
            }
            i += closeLen;
          } else {
            i++;
          }
        }
        continue;
      }
      // Inline code — skip to matching close
      final closeIdx = _findInlineCodeClose(text, i + 1, runLen);
      if (closeIdx != -1) {
        i = closeIdx + runLen;
        continue;
      }
      count++;
      i++;
      continue;
    }
    i++;
  }
  return count;
}

bool _isInsideListItem(String text, int position) {
  final lastNewline = text.lastIndexOf('\n', position);
  final lineStart = lastNewline + 1;
  final line = text.substring(lineStart, position);
  return RegExp(r'^\s*[-*+]\s+$').hasMatch(line) ||
      RegExp(r'^\s*\d+[.)]\s+$').hasMatch(line);
}

int _trailingCharCount(String text, String char) {
  if (text.isEmpty || char.isEmpty) return 0;
  final charCode = char.codeUnitAt(0);
  var count = 0;
  var i = text.length - 1;
  while (i >= 0 && text.codeUnitAt(i) == charCode) {
    count++;
    i--;
  }
  return count;
}
