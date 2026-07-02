import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streamdown/streamdown.dart';

Future<void> pumpStream(
  WidgetTester tester,
  StreamController<String> controller, {
  bool animated = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Streamdown(stream: controller.stream, animated: animated),
      ),
    ),
  );
}

void main() {
  group('Parity — cached block theme invalidation', () {
    testWidgets('closed heading rebuilds on theme change', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Streamdown(stream: controller.stream, animated: false),
          ),
        ),
      );

      controller.add('# The Title\n\n');
      await tester.pump();
      await tester.pump();

      expect(find.text('The Title'), findsOneWidget);

      controller.add('more text\n');
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Streamdown(stream: controller.stream, animated: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('The Title'), findsOneWidget);
    });

    testWidgets('closed code block rebuilds on theme change', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Streamdown(stream: controller.stream, animated: false),
          ),
        ),
      );

      controller.add('```dart\nvoid main() {}\n```\n\n');
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('main', findRichText: true), findsWidgets);

      controller.add('trailing\n');
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Streamdown(stream: controller.stream, animated: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('main', findRichText: true), findsWidgets);
    });
  });

  group('Parity — code block memo', () {
    testWidgets('closed code block survives more chunks', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await pumpStream(tester, controller);

      controller.add('```js\nconst a = 1;\n```\n\n');
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('const a = 1;', findRichText: true),
        findsWidgets,
      );

      controller.add('paragraph after\n');
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('const a = 1;', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('open code block grows as more lines stream in', (
      tester,
    ) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await pumpStream(tester, controller);

      controller.add('```dart\nline one\n');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('line one', findRichText: true), findsWidgets);

      controller.add('line two\n');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('line two', findRichText: true), findsWidgets);

      controller.add('line three\n```\n');
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('line three', findRichText: true),
        findsWidgets,
      );
    });
  });

  group('Parity — animated streaming renders without crash', () {
    testWidgets('char animation streams and settles', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Streamdown(
              stream: controller.stream,
              animated: true,
              animateConfig: const AnimateConfig(
                animation: AnimationType.fadeIn,
                sep: AnimationSeparator.char,
              ),
            ),
          ),
        ),
      );

      controller.add('Hi\n');
      await tester.pump();
      await tester.pump();
      controller.add(' there\n');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
    });

    testWidgets('word animation streams and settles', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Streamdown(
              stream: controller.stream,
              animated: true,
              animateConfig: const AnimateConfig(
                animation: AnimationType.fadeIn,
              ),
            ),
          ),
        ),
      );

      controller.add('alpha beta gamma\n');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
    });

    testWidgets('emoji char split streams and settles', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Streamdown(
              stream: controller.stream,
              animated: true,
              animateConfig: const AnimateConfig(sep: AnimationSeparator.char),
            ),
          ),
        ),
      );

      controller.add('a😊b\n');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
    });

    testWidgets('block animation survives through re-renders', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Streamdown(
              stream: controller.stream,
              animated: true,
              animateConfig: const AnimateConfig(),
            ),
          ),
        ),
      );

      controller.add('# Title\n\n');
      await tester.pump();
      await tester.pump();

      controller.add('more content\n');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Title'), findsOneWidget);
    });
  });
}
