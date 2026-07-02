import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streamdown/streamdown.dart';
import 'package:streamdown/src/render/ast_renderer.dart';

/// Pump a [Streamdown.text] inside a [MaterialApp] scaffold.
Future<void> pumpStatic(
  WidgetTester tester,
  String markdown, {
  void Function(Uri uri)? onLinkTap,
  bool selectable = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Streamdown.text(
          markdown,
          onLinkTap: onLinkTap,
          selectable: selectable,
        ),
      ),
    ),
  );
}

void main() {
  group('Streamdown — block-level rendering', () {
    testWidgets('renders a single H1', (tester) async {
      await pumpStatic(tester, '# Hello\n');
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('renders all 6 heading levels', (tester) async {
      await pumpStatic(tester, '# A\n## B\n### C\n#### D\n##### E\n###### F\n');
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
    });

    testWidgets('renders a paragraph', (tester) async {
      await pumpStatic(tester, 'Hello, world.\n');
      expect(find.textContaining('Hello, world.'), findsWidgets);
    });

    testWidgets('renders horizontal rule as a Divider', (tester) async {
      await pumpStatic(tester, '---\n');
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('renders a blockquote', (tester) async {
      await pumpStatic(tester, '> quoted text\n');
      expect(find.textContaining('quoted text'), findsWidgets);
    });

    testWidgets('renders an unordered list', (tester) async {
      await pumpStatic(tester, '- one\n- two\n- three\n');
      expect(find.textContaining('one'), findsWidgets);
      expect(find.textContaining('two'), findsWidgets);
      expect(find.textContaining('three'), findsWidgets);
      // Bullet markers
      expect(find.text('•'), findsNWidgets(3));
    });

    testWidgets('renders an ordered list with numbered markers', (
      tester,
    ) async {
      await pumpStatic(tester, '1. first\n2. second\n');
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets('renders task list with checkbox glyphs', (tester) async {
      await pumpStatic(tester, '- [ ] todo\n- [x] done\n');
      expect(find.text('☐'), findsOneWidget);
      expect(find.text('☑'), findsOneWidget);
    });

    testWidgets('renders a fenced code block', (tester) async {
      await pumpStatic(tester, '```dart\nprint(42);\n```\n');
      expect(
        find.textContaining('print(42);', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('renders a GFM table', (tester) async {
      await pumpStatic(tester, '| h1 | h2 |\n|----|----|\n| a  | b  |\n');
      expect(find.text('h1'), findsOneWidget);
      expect(find.text('h2'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
    });
  });

  group('Streamdown — inline formatting', () {
    testWidgets('inline code span', (tester) async {
      await pumpStatic(tester, 'use `printf` for output\n');
      // The code span text should appear as part of a TextSpan.
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      expect(richText.text.toPlainText(), contains('printf'));
    });

    testWidgets('bold text', (tester) async {
      await pumpStatic(tester, 'a **bold** word\n');
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      final plain = richText.text.toPlainText();
      expect(plain, contains('bold'));
      // The '**' delimiters should not appear in the rendered text.
      expect(plain, isNot(contains('**')));
    });

    testWidgets('italic text', (tester) async {
      await pumpStatic(tester, 'a *italic* word\n');
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      expect(richText.text.toPlainText(), contains('italic'));
      expect(richText.text.toPlainText(), isNot(contains('*italic*')));
    });

    testWidgets('strikethrough', (tester) async {
      await pumpStatic(tester, 'a ~~gone~~ word\n');
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      expect(richText.text.toPlainText(), contains('gone'));
      expect(richText.text.toPlainText(), isNot(contains('~~')));
    });

    testWidgets('link tap fires callback', (tester) async {
      Uri? tapped;
      await pumpStatic(
        tester,
        'visit [the site](https://example.com)\n',
        onLinkTap: (uri) => tapped = uri,
      );
      // Find the link text and tap on it.
      final finder = find.textContaining('the site');
      expect(finder, findsWidgets);
      // Tap directly using SelectableText: tap on the surrounding container.
      await tester.tap(find.byType(SelectionArea).first);
      // Selection tap may not fire link recognizer; manual recognizer fires
      // via the gesture system. We verify by exercising the recognizer
      // directly via the RichText's TextSpan tree.
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      // Walk spans to find the link span and invoke its recognizer.
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.recognizer is TapGestureRecognizer && tapped == null) {
            (span.recognizer! as TapGestureRecognizer).onTap?.call();
          }
          span.children?.forEach(visit);
        }
      }

      visit(richText.text);
      expect(tapped, Uri.parse('https://example.com'));
    });

    testWidgets('autolink renders the URL text', (tester) async {
      await pumpStatic(tester, 'see <https://example.com> for more\n');
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      expect(richText.text.toPlainText(), contains('https://example.com'));
    });
  });

  group('Streamdown — selection', () {
    testWidgets('SelectionArea wraps content when selectable=true', (
      tester,
    ) async {
      await pumpStatic(tester, 'paragraph\n');
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('No SelectionArea when selectable=false', (tester) async {
      await pumpStatic(tester, 'paragraph\n', selectable: false);
      expect(find.byType(SelectionArea), findsNothing);
    });
  });

  group('Streamdown — streaming stability', () {
    testWidgets('static text replacement does not reuse cached block output', (
      tester,
    ) async {
      await pumpStatic(tester, 'first paragraph\n');
      expect(find.textContaining('first paragraph'), findsWidgets);

      await pumpStatic(tester, 'second paragraph\n');

      expect(find.textContaining('second paragraph'), findsWidgets);
      expect(find.textContaining('first paragraph'), findsNothing);
    });

    testWidgets(
      'closed widgets persist across chunk feeds (no element churn)',
      (tester) async {
        final controller = StreamController<String>();
        addTearDown(controller.close);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Streamdown(stream: controller.stream)),
          ),
        );

        controller.add('# First heading\n\n');
        await tester.pump();
        await tester.pump();
        expect(find.text('First heading'), findsOneWidget);
        final firstElement = tester.element(find.text('First heading'));

        // Add more content — the first heading should not be torn down.
        controller.add('Some paragraph text.\n\n');
        await tester.pump();
        await tester.pump();
        controller.add('## Second heading\n\n');
        await tester.pump();
        await tester.pump();
        controller.add('Even more text after second.\n');
        await tester.pump();
        await tester.pump();

        expect(find.text('First heading'), findsOneWidget);
        expect(find.text('Second heading'), findsOneWidget);
        final firstElementAfter = tester.element(find.text('First heading'));
        expect(
          identical(firstElement, firstElementAfter),
          isTrue,
          reason: 'first heading element should be preserved across feeds',
        );
      },
    );

    testWidgets('stream complete finalizes open paragraph', (tester) async {
      final controller = StreamController<String>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Streamdown(stream: controller.stream)),
        ),
      );

      controller.add('hello world\n');
      await tester.pump();
      expect(find.textContaining('hello world'), findsWidgets);

      // Don't await the close — in flutter_test's fake-async zone, the close
      // future only resolves after the subscription's onDone runs, which
      // requires another pump. Awaiting here would deadlock.
      unawaited(controller.close());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('hello world'), findsWidgets);
    });

    testWidgets('parseIncompleteMarkdown renders a partial trailing line', (
      tester,
    ) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Streamdown(
              stream: controller.stream,
              parseIncompleteMarkdown: true,
            ),
          ),
        ),
      );

      controller.add('hello while still streaming');
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('hello while still streaming', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('remended inline markdown does not skip later real text', (
      tester,
    ) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Streamdown(
              stream: controller.stream,
              parseIncompleteMarkdown: true,
            ),
          ),
        ),
      );

      controller.add('a **bol');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('a bol', findRichText: true), findsWidgets);

      controller.add('d** after');
      await tester.pump();
      await tester.pump();

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      expect(richText.text.toPlainText(), contains('a bold after'));
    });

    testWidgets(
      'animated stream keeps prose out of WidgetSpans after reparse',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Streamdown(
                stream: controller.stream,
                parseIncompleteMarkdown: true,
                animated: true,
                animateConfig: const AnimateConfig(stagger: 0),
              ),
            ),
          ),
        );

        controller.add('hello');
        await tester.pump();
        await tester.pump();

        expect(_widgetSpanCount(tester), 0);

        controller.add(' world');
        await tester.pump();
        await tester.pump();

        expect(
          _widgetSpanCount(tester),
          0,
          reason: 'ordinary prose must use native TextSpan layout',
        );

        unawaited(controller.close());
        await tester.pump();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'animated iPhone-width stream wraps identically before and after completion',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 345,
                  child: Streamdown(
                    stream: controller.stream,
                    parseIncompleteMarkdown: true,
                    animated: true,
                    animateConfig: const AnimateConfig(stagger: 18),
                  ),
                ),
              ),
            ),
          ),
        );

        controller.add('Sure — here’s a clean sam');
        await tester.pump();
        controller.add('ple CV you can use as a template.');
        await tester.pump();
        await tester.pump();

        final streamingParagraph = tester.widget<RichText>(
          find.byType(RichText).first,
        );
        final streamingHeight = tester
            .getSize(find.byType(RichText).first)
            .height;
        expect(
          streamingParagraph.text.toPlainText(),
          'Sure — here’s a clean sample CV you can use as a template.',
        );
        expect(_countWidgetSpans(streamingParagraph.text), 0);

        unawaited(controller.close());
        await tester.pump();
        await tester.pumpAndSettle();

        final completedParagraph = tester.widget<RichText>(
          find.byType(RichText).first,
        );
        final completedHeight = tester
            .getSize(find.byType(RichText).first)
            .height;
        expect(
          completedParagraph.text.toPlainText(),
          streamingParagraph.text.toPlainText(),
        );
        expect(completedHeight, streamingHeight);
        expect(_countWidgetSpans(completedParagraph.text), 0);
      },
    );

    testWidgets('animated markdown preserves soft breaks, blocks, and lists', (
      tester,
    ) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 345,
              child: Streamdown(
                stream: controller.stream,
                animated: true,
                animateConfig: const AnimateConfig(),
              ),
            ),
          ),
        ),
      );

      controller.add(
        'A soft\nline with **bold** text.\n\n'
        '1. Full name\n2. Phone number and email\n\n'
        '- First skill\n- Second skill\n',
      );
      await tester.pump();
      await tester.pump();

      final prose = tester.widget<RichText>(find.byType(RichText).first);
      expect(prose.text.toPlainText(), 'A soft line with bold text.');
      for (final richText in tester.widgetList<RichText>(
        find.byType(RichText),
      )) {
        expect(_countWidgetSpans(richText.text), 0);
      }
      expect(find.text('1.', findRichText: true), findsOneWidget);
      expect(find.text('2.', findRichText: true), findsOneWidget);
      expect(find.text('•', findRichText: true), findsNWidgets(2));

      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'PDF response reconciles provisional paragraphs into lists before completion',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 345,
                child: Streamdown(
                  stream: controller.stream,
                  animated: true,
                  parseIncompleteMarkdown: true,
                ),
              ),
            ),
          ),
        );

        const chunks = <String>[
          'Yes',
          ' — I can',
          ' create a PDF for you.\n\nSend me:\n-',
          ' the text/content\n-',
          ' any title or layout',
          ' preference\n- if you want',
          ' it from a file, upload it\n\nI can also turn a',
          ' document into PDF if you want.',
        ];

        for (final chunk in chunks) {
          controller.add(chunk);
          await tester.pump();
          await tester.pump();
        }

        expect(find.text('•', findRichText: true), findsNWidgets(3));
        expect(
          find.textContaining(
            'any title or layout preference',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'if you want it from a file, upload it',
            findRichText: true,
          ),
          findsOneWidget,
        );

        final rendererBeforeCompletion = tester.element(
          find.byType(AstRenderer),
        );
        unawaited(controller.close());
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          identical(
            rendererBeforeCompletion,
            tester.element(find.byType(AstRenderer)),
          ),
          isTrue,
          reason: 'completion must reconcile through the existing renderer',
        );
        expect(find.text('•', findRichText: true), findsNWidgets(3));
      },
    );

    testWidgets('block type changes replace the keyed child immediately', (
      tester,
    ) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Streamdown(
              stream: controller.stream,
              parseIncompleteMarkdown: true,
            ),
          ),
        ),
      );

      controller.add('Send me:\n-');
      await tester.pump();
      await tester.pump();
      expect(find.text('•', findRichText: true), findsNothing);

      controller.add(' the text/content');
      await tester.pump();
      await tester.pump();
      expect(find.text('•', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('the text/content', findRichText: true),
        findsOneWidget,
      );
    });
  });
}

int _widgetSpanCount(WidgetTester tester) {
  final richText = tester.widget<RichText>(find.byType(RichText).first);
  return _countWidgetSpans(richText.text);
}

int _countWidgetSpans(InlineSpan span) {
  var count = span is WidgetSpan ? 1 : 0;
  if (span is TextSpan) {
    for (final child in span.children ?? const <InlineSpan>[]) {
      count += _countWidgetSpans(child);
    }
  }
  return count;
}
