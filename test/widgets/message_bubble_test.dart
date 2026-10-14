import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/widgets/message_bubble.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

// 1x1 PNGs: red and blue.
const _redPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
const _bluePng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC';

void main() {
  group('MessageBubble.safeLinkTarget', () {
    test('allows http and https URLs with a host', () {
      expect(MessageBubble.safeLinkTarget('http://example.com/a?b=1'),
          Uri.parse('http://example.com/a?b=1'));
      expect(MessageBubble.safeLinkTarget('https://example.com'),
          Uri.parse('https://example.com'));
      expect(MessageBubble.safeLinkTarget('HTTPS://Example.com/x')?.scheme,
          'https');
    });

    test('refuses every other scheme', () {
      expect(MessageBubble.safeLinkTarget('tel:+123456789'), isNull);
      expect(MessageBubble.safeLinkTarget('sms:+123456789?body=hi'), isNull);
      expect(MessageBubble.safeLinkTarget('javascript:alert(1)'), isNull);
      expect(MessageBubble.safeLinkTarget('file:///etc/passwd'), isNull);
      expect(
          MessageBubble.safeLinkTarget('intent://x#Intent;scheme=a;end'),
          isNull);
      expect(MessageBubble.safeLinkTarget('myapp://open/deep'), isNull);
    });

    test('refuses scheme-less, hostless, null and malformed hrefs', () {
      expect(MessageBubble.safeLinkTarget('example.com/page'), isNull);
      expect(MessageBubble.safeLinkTarget('/relative/path'), isNull);
      expect(MessageBubble.safeLinkTarget('http:///nohost'), isNull);
      expect(MessageBubble.safeLinkTarget(''), isNull);
      expect(MessageBubble.safeLinkTarget(null), isNull);
      // Uri.parse throws on this one; the tap handler must not.
      expect(MessageBubble.safeLinkTarget('http://[::1'), isNull);
    });
  });

  group('MessageBubble', () {
    testWidgets('user message shows content', (tester) async {
      final msg = ChatMessage(role: 'user', content: 'Hello world');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('assistant message shows label and content', (tester) async {
      final msg = ChatMessage(role: 'assistant', content: 'Hi there');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // Flag header shows the model name (or fallback) in uppercase
      expect(find.text('ASSISTANT'), findsOneWidget);
      expect(
        find.textContaining('Hi there', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('error message shows retry button', (tester) async {
      bool retried = false;
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Connection failed',
        isError: true,
      );

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onRetry: () => retried = true),
      ));
      await tester.pump();

      // verify retry button works
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('thinking section renders and collapses', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'The answer is 42',
        thinking: 'Deep thought process here',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // thinking header should be there
      expect(find.text('Thinking'), findsOneWidget);

      // content should be hidden initially
      expect(find.text('Deep thought process here'), findsNothing);

      // tap to expand
      await tester.tap(find.text('Thinking'));
      await tester.pump();
      expect(find.text('Deep thought process here'), findsOneWidget);
    });

    testWidgets('assistant message shows copy button', (tester) async {
      final msg = ChatMessage(role: 'assistant', content: 'Some response');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets('user message shows visible copy and edit actions',
        (tester) async {
      bool edited = false;
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onEdit: () => edited = true),
      ));
      await tester.pump();

      // discoverable without long-pressing
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(edited, isTrue);
    });

    testWidgets('user message renders every attached image', (tester) async {
      // 1x1 transparent PNG
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      final msg = ChatMessage(
        role: 'user',
        content: 'two pics',
        images: [png, png],
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('user message without onEdit shows no edit action',
        (tester) async {
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('user message shows a delete action when onDelete is set',
        (tester) async {
      var deleted = false;
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: msg,
          onEdit: () {},
          onDelete: () => deleted = true,
        ),
      ));
      await tester.pump();

      // reachable without the long-press sheet (which SelectableText eats)
      expect(find.byTooltip('Delete'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      expect(deleted, isTrue);
    });

    testWidgets('user message without onDelete shows no delete action',
        (tester) async {
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onEdit: () {}),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('empty finished response still offers retry, not copy',
        (tester) async {
      var retried = false;
      final msg = ChatMessage(role: 'assistant', content: '');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onRetry: () => retried = true),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      expect(retried, isTrue);
    });

    testWidgets('empty response without onRetry shows no actions',
        (tester) async {
      final msg = ChatMessage(role: 'assistant', content: '');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
    });

    testWidgets('a streaming bubble hides retry even with onRetry',
        (tester) async {
      final msg = ChatMessage(role: 'assistant', content: '');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, isStreaming: true, onRetry: () {}),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox()); // stop the typing animation
    });
  });

  group('markdown images', () {
    testWidgets('are never fetched: a placeholder replaces them',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Look: ![a chart](http://x.test/y.png?q=secret) done',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.text('a chart'), findsOneWidget);
    });

    testWidgets('file and scheme-less sources get a placeholder too',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: '![local](file:///etc/hostname)\n\n![rel](pics/a.png)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('local'), findsOneWidget);
      expect(find.text('rel'), findsOneWidget);
    });

    testWidgets('without alt text the placeholder shows the host',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: '![](https://img.example.org/p.png)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('img.example.org'), findsOneWidget);
    });

    testWidgets('tapping a placeholder is safe for any URL', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: '![web](http://x.test/a.png)\n\n![local](file:///etc/hostname)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // http(s) goes to the launcher (absent in tests: the failure must be
      // swallowed); anything else is dropped before it gets that far.
      await tester.tap(find.text('web'));
      await tester.pump();
      await tester.tap(find.text('local'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long alt text is truncated, not overflowed',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final msg = ChatMessage(
        role: 'assistant',
        content: '![${'wide ' * 60}](http://x.test/a.png)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('are not fetched while streaming either', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'partial ![pic](http://x.test/y.png)',
      );

      await tester.pumpWidget(
          _wrap(MessageBubble(message: msg, isStreaming: true)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('pic'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // cancel the render timer
    });
  });

  group('attached image data', () {
    testWidgets('malformed base64 shows a broken-image icon, not an error',
        (tester) async {
      final msg = ChatMessage(
        role: 'user',
        content: 'bad pic',
        images: ['this is !!! not base64'],
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('undecodable image bytes fall back to the broken icon',
        (tester) async {
      final msg = ChatMessage(
        role: 'user',
        content: 'garbage pic',
        images: [base64Encode([1, 2, 3, 4, 5, 6, 7, 8])],
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      // The engine decodes outside the fake clock; give it real time.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('a reused bubble element shows the new message\'s image',
        (tester) async {
      Uint8List shownBytes() {
        final image = tester.widget<Image>(find.byType(Image));
        return (image.image as MemoryImage).bytes;
      }

      final first = ChatMessage(role: 'user', content: 'one', images: [_redPng]);
      final second =
          ChatMessage(role: 'user', content: 'two', images: [_bluePng]);

      await tester.pumpWidget(_wrap(MessageBubble(message: first)));
      expect(shownBytes(), base64Decode(_redPng));

      // Same widget type and position -> the element and its state are
      // reused for a different message, as in an unkeyed list.
      await tester.pumpWidget(_wrap(MessageBubble(message: second)));
      expect(shownBytes(), base64Decode(_bluePng));
    });
  });
}
