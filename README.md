# streamdown

[![pub package](https://img.shields.io/pub/v/streamdown.svg)](https://pub.dev/packages/streamdown)
[![CI](https://github.com/jayu1023/streamdown/actions/workflows/ci.yml/badge.svg)](https://github.com/jayu1023/streamdown/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

**Flicker-free streaming markdown for Flutter AI apps. 188× faster than `flutter_markdown` on chunked input. Drop-in API.**

▶ **[Try it live](https://jayu1023.github.io/streamdown/)** — side-by-side comparison in your browser, no install needed.

![streamdown vs flutter_markdown — same stream, side by side](example/screenshots/split_screen_demo.gif)

## 30-second adoption

```dart
// Before
Markdown(data: response)

// After
Streamdown(stream: openai.responseStream)
```

```yaml
dependencies:
  streamdown: ^0.1.0
```

That's it. Theme, code highlighting, link tap, and selectable text Just Work out of the box.

---

## Why streamdown?

`flutter_markdown` re-parses the entire string on every chunk. For a 2000-token GPT response, that's ~400 re-parses + full re-highlight of code blocks + LaTeX re-renders. Result: visible flicker, jumping cursor, code blocks that flash unstyled → styled.

**streamdown** keeps an append-only AST, renders incomplete blocks provisionally (e.g., a half-finished ` ```dart ` becomes a code block immediately), and uses stable widget keys so Flutter's diff doesn't tear down + rebuild on every token.

|  | `flutter_markdown` | `streamdown` |
|---|---|---|
| Re-parse on every chunk | ✅ (slow) | ❌ (incremental) |
| Provisional code fence rendering | ❌ | ✅ |
| Provisional table rows | ❌ | ✅ |
| Stable widget keys during stream | ❌ | ✅ |
| Word/char-level streaming animation | ❌ | ✅ |
| Blinking caret cursor | ❌ | ✅ |
| CJK-friendly emphasis | ❌ | ✅ |
| Code block line numbers | ❌ | ✅ |
| Table copy (CSV/TSV/Markdown) | ❌ | ✅ |
| Per-line syntax highlighting cache | ❌ | ✅ |
| LaTeX (optional) | ✅ | ✅ |
| Bundle size | ~80KB | <50KB |

**Headline benchmark** — 5KB markdown, 4-char chunks (typical AI stream cadence): streamdown is **~188× faster** than re-parsing from scratch on every chunk. See [`test/perf/benchmark_test.dart`](test/perf/benchmark_test.dart).

---

## Advanced usage

```dart
Streamdown(
  stream: openai.responseStream,
  syntaxTheme: SyntaxTheme.githubDark,
  latex: true,
  selectable: true,
  onLinkTap: (uri) => launchUrl(uri),
  codeBlockBuilder: (lang, code, isComplete) => MyCustomCodeBlock(...),
)
```

### Animation

Streaming Markdown fades in at block level while prose remains continuous text with native Flutter line wrapping:

```dart
Streamdown(
  stream: myStream,
  animated: true,                         // Fade in the active Markdown block
  showCaret: true,                        // Blinking cursor at end of stream
  animateConfig: AnimateConfig(            // Optional: tune the animation
    animation: AnimationType.fadeIn,
    duration: 150,
  ),
)
```

`sep` and `stagger` remain accepted for source compatibility but are deprecated. Inline word widgets are intentionally avoided because they alter line breaking on narrow screens.

### Code blocks

```dart
Streamdown(
  stream: myStream,
  lineNumbers: true,      // Gutter line numbers (default: true)
  codeBlockBuilder: (lang, code, isComplete) => MyCustomWidget(...),
)
```

### CJK text

```dart
Streamdown(
  stream: myStream,
  cjk: true,              // Enables CJK-friendly emphasis and autolink boundary splitting
)
```

When enabled, `_强调_` and `*强调*。` work correctly. Bare URLs like `https://example.com。` split at CJK punctuation.

### Table copy

Tables include a dropdown button to copy as Markdown, CSV, or TSV. The formatters are also exported for direct use:

```dart
import 'package:streamdown/streamdown.dart';

final csv = tableDataToCSV(tableNode);
final md  = tableDataToMarkdown(tableNode);
```

See [`example/`](example/) for runnable scenarios including a side-by-side comparison with `flutter_markdown`.

---

## How it works

Three tricks combined:

1. **Incremental token-level parser** — new tokens extend the trailing AST node; the prefix is never re-tokenized.
2. **Provisional rendering** — an unclosed code fence renders as a code block immediately, then continues filling as lines stream in.
3. **Diff-stable widget keys** — every AST node gets a deterministic key so Flutter's element diff doesn't tear down existing widgets.

See [the architecture notes in CLAUDE.md](CLAUDE.md#architecture-the-moat).

---

## Run the demos

```bash
git clone https://github.com/jayu1023/streamdown
cd streamdown/example
flutter run
```

Six scenarios are included:

1. **Comparison demo** — same stream rendered by `flutter_markdown` (janky) vs `streamdown` (smooth).
2. **AI chat simulator** — mocked LLM stream you can wire to your own provider.
3. **Syntax theme gallery** — `githubLight`, `atomOneDark`, and `auto` side-by-side.
4. **Custom code block builder** — replace the default with your own widget.
5. **Long-form article** — static render of a multi-section markdown doc.
6. **LaTeX math** — inline and block math via `flutter_math_fork`.

---

## Used by

Building something with streamdown? Open a PR adding your project here, or drop a note in [Discussions](https://github.com/jayu1023/streamdown/discussions).

---

## Contributing

Issues and PRs welcome. See [GitHub Issues](https://github.com/jayu1023/streamdown/issues).

## License

BSD-3-Clause. See [LICENSE](LICENSE).
