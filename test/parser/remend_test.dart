import 'package:flutter_test/flutter_test.dart';
import 'package:streamdown/src/parser/remend.dart';

void main() {
  group('remend — pipeline', () {
    test('empty string returns empty', () {
      expect(remend(''), '');
    });

    test('plain text passes through unchanged', () {
      expect(remend('Hello world'), 'Hello world');
    });

    test('strips single trailing space', () {
      expect(remend('Hello '), 'Hello');
    });

    test('preserves double trailing space (line break)', () {
      expect(remend('Hello  '), 'Hello  ');
    });
  });

  group('remend — singleTilde (priority 0)', () {
    test('escapes tilde between word chars', () {
      expect(remend(r'20~25°C'), r'20\~25°C');
    });

    test('does not escape double tilde', () {
      expect(remend('20~~25'), '20~~25');
    });

    test('does not escape tilde at word boundary', () {
      expect(remend('~hello'), '~hello');
      expect(remend('hello~'), 'hello~');
    });

    test('skips content inside code blocks', () {
      expect(remend('```\n20~25\n```'), '```\n20~25\n```');
    });
  });

  group('remend — comparisonOperators (priority 5)', () {
    test('escapes > in list items', () {
      expect(
        remend('- > 25: expensive'),
        r'- \> 25: expensive',
      );
    });

    test('escapes >= in numbered list', () {
      expect(
        remend('1. >= 100'),
        r'1. \>= 100',
      );
    });

    test('does not escape > in blockquotes', () {
      expect(remend('> hello'), '> hello');
    });

    test('skips code blocks', () {
      expect(remend('```\n- > 25\n```'), '```\n- > 25\n```');
    });
  });

  group('remend — htmlTags (priority 10)', () {
    test('strips incomplete opening tag', () {
      expect(remend('text <div class="foo'), 'text');
    });

    test('strips incomplete closing tag', () {
      expect(remend('text </div'), 'text');
    });

    test('does not strip complete tags', () {
      expect(remend('text <div>more</div>'), 'text <div>more</div>');
    });

    test('does not strip < followed by space', () {
      expect(remend('text < 25'), 'text < 25');
    });

    test('does not strip HTML comments', () {
      expect(remend('text <!-- comment -->'), 'text <!-- comment -->');
    });

    test('skips code blocks', () {
      expect(remend('```\n<div\n```'), '```\n<div\n```');
    });
  });

  group('remend — setextHeadings (priority 15)', () {
    test('breaks single dash after text', () {
      expect(remend('text\n-'), 'text\n-\u200B');
    });

    test('breaks double dash after text', () {
      expect(remend('text\n--'), 'text\n--\u200B');
    });

    test('does not break 3+ dashes (horizontal rule)', () {
      expect(remend('text\n---'), 'text\n---');
    });

    test('breaks single equals after text', () {
      expect(remend('text\n='), 'text\n=\u200B');
    });

    test('does not break 3+ equals', () {
      expect(remend('text\n==='), 'text\n===');
    });
  });

  group('remend — links (priority 20)', () {
    test('completes incomplete link with placeholder URL', () {
      expect(
        remend('[click here](https://example.com'),
        '[click here](streamdown:incomplete-link)',
      );
    });

    test('completes link with no URL at all', () {
      expect(
        remend('[click]('),
        '[click](streamdown:incomplete-link)',
      );
    });

    test('strips incomplete image', () {
      expect(remend('![alt text](https://example.com'), '');
    });

    test('handles incomplete bracket without parens', () {
      expect(
        remend('text [incomplete'),
        'text [incomplete](streamdown:incomplete-link)',
      );
    });

    test('text-only mode strips brackets', () {
      expect(
        remend('[click here](https://example.com',
            const RemendOptions(linkMode: RemendLinkMode.textOnly)),
        'click here',
      );
    });

    test('does not modify complete links', () {
      expect(
        remend('[text](https://example.com)'),
        '[text](https://example.com)',
      );
    });

    test('handles nested brackets', () {
      expect(
        remend('[text [nested]](https://example.com'),
        '[text [nested]](streamdown:incomplete-link)',
      );
    });
  });

  group('remend — boldItalic (priority 30)', () {
    test('completes incomplete bold-italic', () {
      expect(remend('***bold italic'), '***bold italic***');
    });

    test('does not complete 4+ consecutive asterisks', () {
      expect(remend('****'), '****');
    });

    test('skips code blocks', () {
      expect(remend('```\n***bold italic\n```'), '```\n***bold italic\n```');
    });

    test('skips horizontal rules', () {
      expect(remend('***'), '***');
    });
  });

  group('remend — bold (priority 35)', () {
    test('completes incomplete bold', () {
      expect(remend('**bold text'), '**bold text**');
    });

    test('handles half-complete closing', () {
      expect(remend('**bold*'), '**bold**');
    });

    test('skips code blocks', () {
      expect(remend('```\n**bold\n```'), '```\n**bold\n```');
    });

    test('skips empty content', () {
      expect(remend('**'), '**');
    });

    test('skips horizontal rules', () {
      expect(remend('---\n**'), '---\n**');
    });
  });

  group('remend — italicDoubleUnderscore (priority 40)', () {
    test('completes incomplete double underscore italic', () {
      expect(remend('__italic text'), '__italic text__');
    });

    test('handles half-complete closing', () {
      expect(remend('__italic_'), '__italic__');
    });

    test('skips code blocks', () {
      expect(remend('```\n__italic\n```'), '```\n__italic\n```');
    });
  });

  group('remend — italicSingleAsterisk (priority 41)', () {
    test('completes incomplete single asterisk italic', () {
      expect(remend('italic *text'), 'italic *text*');
    });

    test('skips word-internal asterisks', () {
      expect(remend('foo*bar'), 'foo*bar');
    });

    test('skips code blocks', () {
      expect(remend('```\n*italic\n```'), '```\n*italic\n```');
    });

    test('skips math blocks', () {
      expect(remend('\$x^* + y\$'), '\$x^* + y\$');
    });
  });

  group('remend — italicSingleUnderscore (priority 42)', () {
    test('completes incomplete single underscore italic', () {
      expect(remend('_italic text'), '_italic text_');
    });

    test('skips word-internal underscores', () {
      expect(remend('foo_bar'), 'foo_bar');
    });

    test('skips code blocks', () {
      expect(remend('```\n_italic\n```'), '```\n_italic\n```');
    });

    test('skips link URLs', () {
      expect(
        remend('[text](http://example.com_path'),
        '[text](streamdown:incomplete-link)',
      );
    });

    test('skips math blocks', () {
      expect(remend('\$x_1 + y\$'), '\$x_1 + y\$');
    });
  });

  group('remend — inlineCode (priority 50)', () {
    test('completes incomplete single backtick', () {
      expect(remend('`code span'), '`code span`');
    });

    test('completes incomplete triple backtick (inline)', () {
      expect(remend('```code``'), '```code```');
    });

    test('skips fenced code blocks', () {
      expect(remend('```\ncode\n```'), '```\ncode\n```');
    });

    test('counts backticks correctly', () {
      // Two backticks outside code blocks = even count, no change
      expect(remend('`a` `b`'), '`a` `b`');
    });
  });

  group('remend — strikethrough (priority 60)', () {
    test('completes incomplete strikethrough', () {
      expect(remend('~~strikethrough'), '~~strikethrough~~');
    });

    test('handles half-complete closing', () {
      expect(remend('~~strike~'), '~~strike~~');
    });

    test('skips code blocks', () {
      expect(remend('```\n~~strike\n```'), '```\n~~strike\n```');
    });
  });

  group('remend — katex (priority 70)', () {
    test('completes incomplete block KaTeX', () {
      expect(remend('\$\$formula'), '\$\$formula\$\$');
    });

    test('completes block KaTeX with newline', () {
      expect(remend('\$\$formula'), '\$\$formula\$\$');
    });

    test(r'adds closing $$ to incomplete formula', () {
      expect(remend('\$\$x = 1'), '\$\$x = 1\$\$');
    });

    test(r'does not modify balanced $$', () {
      expect(remend('\$\$x = 1\$\$'), '\$\$x = 1\$\$');
    });
  });

  group('remend — inlineKatex (priority 75, opt-in)', () {
    test('does not modify by default', () {
      expect(remend('\$formula'), '\$formula');
    });

    test('completes when opt-in enabled', () {
      expect(
        remend('\$formula', const RemendOptions(inlineKatex: true)),
        '\$formula\$',
      );
    });
  });

  group('remend — context detection', () {
    test('isWithinCodeBlock detects fenced blocks', () {
      expect(isWithinCodeBlock('```\ncode\n```', 5), true);
      expect(isWithinCodeBlock('```\ncode\n```', 0), false);
      expect(isWithinCodeBlock('```\ncode\n```', 12), false);
    });

    test(r'isWithinMathBlock detects $$ blocks', () {
      expect(isWithinMathBlock('\$\$x^2\$\$', 3), true);
      expect(isWithinMathBlock('\$\$x^2\$\$', 0), false);
      expect(isWithinMathBlock('\$\$x^2\$\$', 7), false);
    });

    test(r'isWithinMathBlock detects inline $', () {
      expect(isWithinMathBlock('\$x^2\$', 2), true);
      expect(isWithinMathBlock('\$x^2\$', 0), false);
    });

    test('isWithinLinkOrImageUrl detects link URLs', () {
      expect(isWithinLinkOrImageUrl('[text](http://example.com)', 15), true);
      expect(isWithinLinkOrImageUrl('[text](http://example.com)', 5), false);
    });
  });

  group('remend — custom handlers', () {
    test('custom handler runs at specified priority', () {
      final handler = _TestHandler();
      final result = remend('hello', RemendOptions(handlers: [handler]));
      expect(result, 'HELLO');
    });

    test('custom handler runs after built-ins by default', () {
      final handler = _TestHandler();
      final result = remend('**bold', RemendOptions(handlers: [handler]));
      // Bold handler runs first (priority 35), then custom (priority 100)
      expect(result, '**BOLD**');
    });
  });

  group('remend — streaming scenarios', () {
    test('multi-chunk bold', () {
      var buffer = '';
      buffer += 'This is **';
      // React: skips when content after ** is empty
      expect(remend(buffer), 'This is **');
      buffer += 'bold';
      expect(remend(buffer), 'This is **bold**');
      buffer += ' text**';
      expect(remend(buffer), 'This is **bold text**');
    });

    test('multi-chunk code block', () {
      var buffer = '';
      buffer += '```dart\n';
      expect(remend(buffer), '```dart\n');
      buffer += 'void main() {\n';
      expect(remend(buffer), '```dart\nvoid main() {\n');
    });

    test('nested formatting', () {
      expect(remend('**bold and *italic'), '**bold and *italic**');
    });
  });

  group('remend — edge cases', () {
    test('standalone markers pass through', () {
      expect(remend('**'), '**');
      expect(remend('*'), '*');
      expect(remend('__'), '__');
      expect(remend('_'), '_');
      expect(remend('~~'), '~~');
      expect(remend('`'), '`');
    });

    test('long text with incomplete formatting', () {
      final longText = '${'A' * 1000}**';
      expect(remend(longText), longText); // React: skips when content is empty
    });

    test('multiple incomplete formats simultaneously', () {
      // React priority: bold(35) closes first, then inlineCode(50) closes
      expect(remend('**bold and `code'), '**bold and `code**`');
    });
  });
}

class _TestHandler extends RemendHandler {
  @override
  String get name => 'test';

  @override
  String handle(String text) => text.toUpperCase();
}
