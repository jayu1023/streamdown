// Inline tokenizer.
//
// Called by the parser on accumulated paragraph / heading / list-item text.
// Produces a flat sequence of inline tokens; pairing of strong/em/strike
// delimiters is performed at parse time (CommonMark §6.2 "process emphasis").
//
// Non-incremental on purpose: paragraphs are small and re-tokenizing the
// whole string on each chunk is cheap. The expensive incremental work
// (block detection, code-block highlighting) happens elsewhere.

import 'token.dart';

class InlineTokenizer {
  const InlineTokenizer._();

  /// Tokenize [text] into a flat list of inline tokens.
  ///
  /// [latex] enables `$...$` (inline) and `$$...$$` (block) math detection.
  /// When false (default), `$` is plain text — important so dollar amounts
  /// like `$10` don't accidentally start math mode.
  static List<Token> tokenize(String text, {bool latex = false, bool cjk = false}) {
    final out = <Token>[];
    final buf = StringBuffer();
    var i = 0;

    // CJK punctuation chars that should be stripped from trailing autolinks.
    const cjkTrailing = <int>{
      0x3002, // 。
      0x3001, // 、
      0xFF01, // ！
      0xFF1F, // ？
      0xFF1A, // ：
      0xFF1B, // ；
      0x300C, // 「
       0x300D, // 」
    };

    void flushText() {
      if (buf.isNotEmpty) {
        out.add(InlineTextToken(buf.toString()));
        buf.clear();
      }
    }

    while (i < text.length) {
      final c = text[i];
      final code = text.codeUnitAt(i);

      // Backslash escape: \X → literal X.
      if (c == r'\' && i + 1 < text.length) {
        final next = text[i + 1];
        if (_escapableRe.hasMatch(next)) {
          buf.write(next);
          i += 2;
          continue;
        }
      }

      // Hard line break: trailing 2+ spaces before \n, or trailing `\` before \n.
      if (code == 0x0A) {
        // bare newline already handled below as soft break (we just drop it
        // and let the renderer treat consecutive runs as joined).
        // But if buf ends with 2+ spaces or last token is `\`, emit hard break.
        final s = buf.toString();
        if (s.endsWith('  ')) {
          buf.clear();
          buf.write(s.replaceFirst(RegExp(r' +$'), ''));
          flushText();
          out.add(const HardBreakToken());
          i++;
          continue;
        }
        if (s.endsWith(r'\')) {
          buf.clear();
          buf.write(s.substring(0, s.length - 1));
          flushText();
          out.add(const HardBreakToken());
          i++;
          continue;
        }
        // Soft break — collapse to a single space.
        buf.write(' ');
        i++;
        continue;
      }

      // Inline code: `…`, ``…``, etc. Match opening run, find matching closing run.
      if (c == '`') {
        var runLen = 0;
        while (i + runLen < text.length && text[i + runLen] == '`') {
          runLen++;
        }
        final closeIdx = _findCodeSpanClose(text, i + runLen, runLen);
        if (closeIdx != -1) {
          flushText();
          var content = text.substring(i + runLen, closeIdx);
          // CommonMark: strip a single space on each side if both present and
          // content is not all spaces.
          if (content.length >= 2 &&
              content.startsWith(' ') &&
              content.endsWith(' ') &&
              content.trim().isNotEmpty) {
            content = content.substring(1, content.length - 1);
          }
          out.add(CodeSpanToken(content));
          i = closeIdx + runLen;
          continue;
        }
        // No close — treat as literal.
        for (var k = 0; k < runLen; k++) {
          buf.write('`');
        }
        i += runLen;
        continue;
      }

      // Bare URL autolink: http(s)://...
      if (c == 'h' &&
          (text.startsWith('http://', i) || text.startsWith('https://', i))) {
        var end = i;
        while (end < text.length) {
          final ch = text.codeUnitAt(end);
          if (ch == 0x20 ||
              ch == 0x09 ||
              ch == 0x0A ||
              ch == 0x3C ||
              ch == 0x3E ||
              ch == 0x22 ||
              ch == 0x27) {
            break;
          }
          end++;
        }
        // Strip trailing sentence punctuation that's almost certainly not
        // part of the URL.
        while (end > i + 8) {
          final last = text.codeUnitAt(end - 1);
          if (last == 0x2E /* . */ ||
              last == 0x2C /* , */ ||
              last == 0x21 /* ! */ ||
              last == 0x3F /* ? */ ||
              last == 0x29 /* ) */ ||
              last == 0x3A /* : */ ||
              last == 0x3B /* ; */ ||
              (cjk && cjkTrailing.contains(last))) {
            end--;
          } else {
            break;
          }
        }
        flushText();
        out.add(AutolinkToken(text.substring(i, end)));
        i = end;
        continue;
      }

      // LaTeX math (only when enabled).
      if (latex && c == r'$') {
        // Block math: $$...$$
        if (i + 1 < text.length && text[i + 1] == r'$') {
          final closeIdx = text.indexOf(r'$$', i + 2);
          if (closeIdx != -1 && closeIdx > i + 2) {
            flushText();
            out.add(MathToken(text.substring(i + 2, closeIdx), isBlock: true));
            i = closeIdx + 2;
            continue;
          }
        }
        // Inline math: $X$ where X starts and ends with non-space.
        if (i + 1 < text.length && text[i + 1] != ' ' && text[i + 1] != r'$') {
          final closeIdx = text.indexOf(r'$', i + 1);
          if (closeIdx != -1 && closeIdx > i + 1 && text[closeIdx - 1] != ' ') {
            flushText();
            out.add(MathToken(text.substring(i + 1, closeIdx)));
            i = closeIdx + 1;
            continue;
          }
        }
      }

      // Autolink: <http(s)://…> or <mailto:…>.
      if (c == '<') {
        final closeIdx = text.indexOf('>', i + 1);
        if (closeIdx != -1) {
          final inner = text.substring(i + 1, closeIdx);
          if (_autolinkRe.hasMatch(inner)) {
            flushText();
            out.add(AutolinkToken(inner));
            i = closeIdx + 1;
            continue;
          }
        }
      }

      // Image: ![alt](url) — must come before link check because `!` is the marker.
      if (c == '!' && i + 1 < text.length && text[i + 1] == '[') {
        final parsed = _tryParseLink(text, i + 1, isImage: true);
        if (parsed != null) {
          flushText();
          out.add(parsed.token);
          i = parsed.end;
          continue;
        }
      }

      // Link: [text](url) or [text](url "title").
      if (c == '[') {
        final parsed = _tryParseLink(text, i, isImage: false);
        if (parsed != null) {
          flushText();
          out.add(parsed.token);
          i = parsed.end;
          continue;
        }
      }

      // Strong / emphasis: `**`, `__`, `*`, `_`.
      if (c == '*' || c == '_') {
        var runLen = 0;
        while (i + runLen < text.length && text[i + runLen] == c) {
          runLen++;
        }
        // CommonMark §6.2: `_` is more restrictive than `*` — it cannot
        // open/close emphasis intra-word. If a `_` run is flanked by word
        // characters on BOTH sides (e.g. `macOS_System`, `foo_bar_baz`),
        // emit it as literal text instead of an emphasis delimiter.
        if (c == '_') {
            final beforeIsWord =
                i > 0 && _isWordChar(text.codeUnitAt(i - 1), cjk: cjk);
            final afterIsWord = i + runLen < text.length &&
                _isWordChar(text.codeUnitAt(i + runLen), cjk: cjk);
          if (beforeIsWord && afterIsWord) {
            for (var k = 0; k < runLen; k++) {
              buf.write('_');
            }
            i += runLen;
            continue;
          }
        }
        flushText();
        // Emit one StrongDelim per `**` pair, plus one Emphasis for any leftover.
        var emitted = 0;
        while (emitted + 2 <= runLen) {
          out.add(const StrongDelimToken());
          emitted += 2;
        }
        if (emitted < runLen) {
          out.add(EmphasisDelimToken(c));
          emitted++;
        }
        i += runLen;
        continue;
      }

      // Strikethrough: ~~.
      if (c == '~' && i + 1 < text.length && text[i + 1] == '~') {
        flushText();
        out.add(const StrikeDelimToken());
        i += 2;
        continue;
      }

      buf.write(c);
      i++;
    }

    flushText();
    return out;
  }

  // ──────────────────────────────────────────────────────────────────────

  static int _findCodeSpanClose(String text, int from, int runLen) {
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

  static _LinkParseResult? _tryParseLink(
    String text,
    int start, {
    required bool isImage,
  }) {
    // Expects text[start] == '['.
    if (start >= text.length || text[start] != '[') return null;

    // Find matching `]` allowing one level of nested brackets in the text.
    var depth = 1;
    var i = start + 1;
    while (i < text.length && depth > 0) {
      final c = text[i];
      if (c == r'\' && i + 1 < text.length) {
        i += 2;
        continue;
      }
      if (c == '[') depth++;
      if (c == ']') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    if (depth != 0) return null;
    final closeBracket = i;
    if (closeBracket + 1 >= text.length || text[closeBracket + 1] != '(') {
      return null;
    }

    // Parse the (url "title") part.
    var j = closeBracket + 2;
    // Skip leading whitespace.
    while (j < text.length && (text[j] == ' ' || text[j] == '\t')) {
      j++;
    }
    final urlStart = j;
    // URL: until whitespace or `)` or `"`.
    while (j < text.length) {
      final c = text[j];
      if (c == ')' || c == ' ' || c == '\t' || c == '"') break;
      if (c == r'\' && j + 1 < text.length) {
        j += 2;
        continue;
      }
      j++;
    }
    final urlEnd = j;

    // Optional title.
    String? title;
    while (j < text.length && (text[j] == ' ' || text[j] == '\t')) {
      j++;
    }
    if (j < text.length && text[j] == '"') {
      final titleStart = j + 1;
      var k = titleStart;
      while (k < text.length && text[k] != '"') {
        if (text[k] == r'\' && k + 1 < text.length) {
          k += 2;
          continue;
        }
        k++;
      }
      if (k >= text.length) return null;
      title = text.substring(titleStart, k);
      j = k + 1;
      while (j < text.length && (text[j] == ' ' || text[j] == '\t')) {
        j++;
      }
    }

    if (j >= text.length || text[j] != ')') return null;

    final linkText = text.substring(start + 1, closeBracket);
    final url = text.substring(urlStart, urlEnd);
    return _LinkParseResult(
      LinkToken(text: linkText, url: url, title: title, isImage: isImage),
      j + 1,
    );
  }
}

class _LinkParseResult {
  const _LinkParseResult(this.token, this.end);

  final LinkToken token;
  final int end;
}

bool _isWordChar(int code, {bool cjk = false}) {
  if (cjk) {
    // CJK mode: exclude CJK ideographs and punctuation from word char
    // detection so `_强调_` and `*强调*。` work as emphasis.
    // CJK Unified Ideographs: U+4E00-U+9FFF, U+3400-U+4DBF
    // CJK Symbols & Punctuation: U+3000-U+303F
    // Fullwidth forms: U+FF00-U+FFEF (includes ！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠ etc.)
    if ((code >= 0x3000 && code <= 0x303F) ||
        (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0xFF00 && code <= 0xFFEF)) {
      return false;
    }
  }
  return (code >= 0x30 && code <= 0x39) || // 0-9
      (code >= 0x41 && code <= 0x5A) || // A-Z
      (code >= 0x61 && code <= 0x7A) || // a-z
      code >= 0x80; // non-ASCII letters (conservative — treat as word)
}

final RegExp _escapableRe = RegExp(r'[\\`*_{}\[\]()#+\-.!~|]');

final RegExp _autolinkRe = RegExp(
  r'^(?:https?://[^\s<>]+|mailto:[^\s<>@]+@[^\s<>]+)$',
);
