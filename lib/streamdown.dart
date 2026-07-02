/// streamdown — Flicker-free streaming markdown renderer for Flutter AI apps.
///
/// Drop-in replacement for `flutter_markdown` that handles partial code
/// fences, half-finished tables, and mid-stream LaTeX without re-parsing
/// the prefix on every chunk.
///
/// See https://pub.dev/packages/streamdown for documentation.
library;

export 'src/render/streamdown_widget.dart' show Streamdown;
export 'src/render/syntax_theme.dart' show CodeBlockBuilder, SyntaxTheme;
export 'src/parser/remend.dart'
    show RemendOptions, RemendLinkMode, RemendHandler;
export 'src/render/table.dart'
    show tableDataToCSV, tableDataToTSV, tableDataToMarkdown;
export 'src/render/animation.dart'
    show AnimateConfig, AnimationSeparator, AnimationType;
